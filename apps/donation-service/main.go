package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sqs"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/joho/godotenv"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/trace"
)

const (
	dbConnectMaxAttempts = 10
	dbConnectMaxBackoff  = 30 * time.Second
	ngoValidationTimeout = 2 * time.Second
)

// Golden metrics (SLIs) do donation-service.
var (
	httpRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total de requisições HTTP recebidas, por método, rota e status.",
		},
		[]string{"method", "path", "status"},
	)
	httpRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "Duração das requisições HTTP, por método e rota.",
			Buckets: []float64{0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5},
		},
		[]string{"method", "path"},
	)
)

type Donation struct {
	ID        int       `json:"id"`
	NgoID     int       `json:"ngo_id"`
	Amount    float64   `json:"amount"`
	DonorName string    `json:"donor_name"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

type App struct {
	DB            *sql.DB
	SqsSvc        *sqs.SQS
	SqsQueueURL   string
	NgoServiceURL string
	HTTPClient    *http.Client
	Tracer        trace.Tracer
}

func main() {
	_ = godotenv.Load()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8082"
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL é obrigatória")
	}

	shutdownTracing, err := initTracing(context.Background())
	if err != nil {
		log.Printf("Tracing OTel desabilitado: %v", err)
	}
	defer shutdownTracing(context.Background())

	db := connectWithRetry(dbURL, dbConnectMaxAttempts)
	defer db.Close()
	log.Println("Conectado ao PostgreSQL (donation-service).")

	var sqsSvc *sqs.SQS
	queueURL := os.Getenv("AWS_SQS_URL")
	region := os.Getenv("AWS_REGION")
	if queueURL != "" && region != "" {
		sess, _ := session.NewSession(&aws.Config{Region: aws.String(region)})
		sqsSvc = sqs.New(sess)
		log.Println("Integração com AWS SQS ativada.")
	}

	app := &App{
		DB:            db,
		SqsSvc:        sqsSvc,
		SqsQueueURL:   queueURL,
		NgoServiceURL: os.Getenv("NGO_SERVICE_URL"),
		HTTPClient: &http.Client{
			Transport: otelhttp.NewTransport(http.DefaultTransport),
			Timeout:   ngoValidationTimeout,
		},
		Tracer: otel.Tracer("donation-service"),
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", withMetrics("/health", app.HealthHandler))
	mux.HandleFunc("/ready", withMetrics("/ready", app.ReadyHandler))
	mux.HandleFunc("/donations", withMetrics("/donations", app.DonationHandler))
	mux.Handle("/metrics", promhttp.Handler())

	handler := otelhttp.NewHandler(mux, "donation-service")

	srv := &http.Server{
		Addr:    ":" + port,
		Handler: handler,
	}

	go func() {
		log.Printf("donation-service rodando na porta %s", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Erro ao iniciar servidor: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = srv.Shutdown(ctx)
}

// connectWithRetry tenta abrir e validar (Ping) a conexão com o banco com
// backoff exponencial, evitando que o processo morra imediatamente enquanto
// o RDS/Postgres ainda está subindo (ex.: durante o rollout de um Pod).
func connectWithRetry(dbURL string, maxAttempts int) *sql.DB {
	var db *sql.DB
	var lastErr error
	backoff := time.Second

	for attempt := 1; attempt <= maxAttempts; attempt++ {
		db, lastErr = sql.Open("pgx", dbURL)
		if lastErr == nil {
			if pingErr := db.Ping(); pingErr != nil {
				lastErr = pingErr
			} else {
				return db
			}
		}

		log.Printf("Tentativa %d/%d de conexão com o banco falhou: %v", attempt, maxAttempts, lastErr)
		if attempt == maxAttempts {
			break
		}

		time.Sleep(backoff)
		if backoff < dbConnectMaxBackoff {
			backoff *= 2
		}
	}

	log.Fatalf("Não foi possível conectar ao banco de dados após %d tentativas: %v", maxAttempts, lastErr)
	return nil
}

// withMetrics instrumenta um handler com as duas golden metrics (SLIs) do
// donation-service: contagem de requisições por status e latência.
func withMetrics(path string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next(rec, r)

		httpRequestsTotal.WithLabelValues(r.Method, path, strconv.Itoa(rec.status)).Inc()
		httpRequestDuration.WithLabelValues(r.Method, path).Observe(time.Since(start).Seconds())
	}
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func (a *App) HealthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"ok","service":"donation-service"}`))
}

// ReadyHandler indica se o serviço está apto a receber tráfego (readiness
// probe): a dependência crítica do hot path, o Postgres, precisa responder.
func (a *App) ReadyHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	if err := a.DB.PingContext(ctx); err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		w.Write([]byte(`{"status":"not ready","service":"donation-service"}`))
		return
	}

	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"ready","service":"donation-service"}`))
}

func (a *App) DonationHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	if r.Method == http.MethodPost {
		var d Donation
		if err := json.NewDecoder(r.Body).Decode(&d); err != nil {
			http.Error(w, `{"error":"Payload inválido"}`, http.StatusBadRequest)
			return
		}

		if err := a.validateNgo(r.Context(), d.NgoID); err != nil {
			http.Error(w, fmt.Sprintf(`{"error":%q}`, err.Error()), http.StatusBadRequest)
			return
		}

		d.Status = "APPROVED" // Simulação de gateway de pagamento
		err := a.DB.QueryRowContext(r.Context(),
			"INSERT INTO donations (ngo_id, amount, donor_name, status) VALUES ($1, $2, $3, $4) RETURNING id, created_at",
			d.NgoID, d.Amount, d.DonorName, d.Status,
		).Scan(&d.ID, &d.CreatedAt)

		if err != nil {
			log.Printf("Erro ao salvar doação: %v", err)
			http.Error(w, `{"error":"Erro interno"}`, http.StatusInternalServerError)
			return
		}

		if a.SqsSvc != nil {
			go a.sendNotificationEvent(d)
		}

		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(d)
		return
	}

	if r.Method == http.MethodGet {
		rows, err := a.DB.QueryContext(r.Context(), "SELECT id, ngo_id, amount, donor_name, status, created_at FROM donations ORDER BY id DESC")
		if err != nil {
			http.Error(w, `{"error":"Erro interno"}`, http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		donations := []Donation{}
		for rows.Next() {
			var d Donation
			rows.Scan(&d.ID, &d.NgoID, &d.Amount, &d.DonorName, &d.Status, &d.CreatedAt)
			donations = append(donations, d)
		}

		json.NewEncoder(w).Encode(donations)
		return
	}

	http.Error(w, `{"error":"Método não permitido"}`, http.StatusMethodNotAllowed)
}

// validateNgo confirma que a ONG existe antes de registrar a doação.
//
// O donation-service é o Hot Path da plataforma: doações não podem parar
// mesmo que o ngo-service esteja indisponível ou lento (Golden Rule do
// desafio). Por isso a validação é "fail-open" — só rejeita a doação quando
// o ngo-service responde explicitamente 404 (ONG não existe); qualquer erro
// de rede, timeout ou 5xx é logado e a doação segue normalmente.
func (a *App) validateNgo(ctx context.Context, ngoID int) error {
	if a.NgoServiceURL == "" {
		return nil
	}

	ctx, cancel := context.WithTimeout(ctx, ngoValidationTimeout)
	defer cancel()

	url := fmt.Sprintf("%s/ngos/%d", a.NgoServiceURL, ngoID)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		log.Printf("validateNgo: falha ao montar requisição: %v", err)
		return nil
	}

	resp, err := a.HTTPClient.Do(req)
	if err != nil {
		log.Printf("validateNgo: ngo-service indisponível, prosseguindo (fail-open): %v", err)
		return nil
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return fmt.Errorf("ngo_id %d não encontrado", ngoID)
	}

	return nil
}

func (a *App) sendNotificationEvent(d Donation) {
	body, _ := json.Marshal(d)
	_, err := a.SqsSvc.SendMessage(&sqs.SendMessageInput{
		MessageBody: aws.String(string(body)),
		QueueUrl:    aws.String(a.SqsQueueURL),
	})
	if err != nil {
		log.Printf("Falha ao despachar evento SQS: %v", err)
	}
}

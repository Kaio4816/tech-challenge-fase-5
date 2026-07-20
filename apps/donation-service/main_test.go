package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
)

func TestHealthHandler(t *testing.T) {
	app := &App{}
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()

	app.HealthHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("esperado status 200, obtido %d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), `"status":"ok"`) {
		t.Fatalf("corpo inesperado: %s", rec.Body.String())
	}
}

func TestDonationHandler_InvalidPayload(t *testing.T) {
	app := &App{}
	req := httptest.NewRequest(http.MethodPost, "/donations", bytes.NewBufferString("{invalido"))
	rec := httptest.NewRecorder()

	app.DonationHandler(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("esperado status 400, obtido %d", rec.Code)
	}
}

func TestDonationHandler_MethodNotAllowed(t *testing.T) {
	app := &App{}
	req := httptest.NewRequest(http.MethodPut, "/donations", nil)
	rec := httptest.NewRecorder()

	app.DonationHandler(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("esperado status 405, obtido %d", rec.Code)
	}
}

func TestDonationHandler_POSTSuccess(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("erro ao criar sqlmock: %v", err)
	}
	defer db.Close()

	rows := sqlmock.NewRows([]string{"id", "created_at"}).AddRow(1, time.Now())
	mock.ExpectQuery("INSERT INTO donations").
		WithArgs(42, 100.0, "Maria", "APPROVED").
		WillReturnRows(rows)

	app := &App{DB: db, HTTPClient: http.DefaultClient} // NgoServiceURL vazia: validação desligada

	body, _ := json.Marshal(map[string]interface{}{
		"ngo_id":     42,
		"amount":     100.0,
		"donor_name": "Maria",
	})
	req := httptest.NewRequest(http.MethodPost, "/donations", bytes.NewReader(body))
	rec := httptest.NewRecorder()

	app.DonationHandler(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("esperado status 201, obtido %d: %s", rec.Code, rec.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("expectativas do sqlmock não atendidas: %v", err)
	}
}

func TestReadyHandler(t *testing.T) {
	t.Run("banco disponível retorna 200", func(t *testing.T) {
		db, mock, err := sqlmock.New(sqlmock.MonitorPingsOption(true))
		if err != nil {
			t.Fatalf("erro ao criar sqlmock: %v", err)
		}
		defer db.Close()
		mock.ExpectPing()

		app := &App{DB: db}
		req := httptest.NewRequest(http.MethodGet, "/ready", nil)
		rec := httptest.NewRecorder()

		app.ReadyHandler(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("esperado status 200, obtido %d", rec.Code)
		}
	})

	t.Run("banco indisponível retorna 503", func(t *testing.T) {
		db, mock, err := sqlmock.New(sqlmock.MonitorPingsOption(true))
		if err != nil {
			t.Fatalf("erro ao criar sqlmock: %v", err)
		}
		defer db.Close()
		mock.ExpectPing().WillReturnError(errors.New("conexão recusada"))

		app := &App{DB: db}
		req := httptest.NewRequest(http.MethodGet, "/ready", nil)
		rec := httptest.NewRecorder()

		app.ReadyHandler(rec, req)

		if rec.Code != http.StatusServiceUnavailable {
			t.Fatalf("esperado status 503, obtido %d", rec.Code)
		}
	})
}

func TestValidateNgo(t *testing.T) {
	t.Run("desabilitada quando NgoServiceURL vazia", func(t *testing.T) {
		app := &App{HTTPClient: http.DefaultClient}
		if err := app.validateNgo(context.Background(), 1); err != nil {
			t.Fatalf("esperado nil, obtido %v", err)
		}
	})

	t.Run("fail-open quando ngo-service está indisponível", func(t *testing.T) {
		app := &App{NgoServiceURL: "http://127.0.0.1:1", HTTPClient: http.DefaultClient}
		if err := app.validateNgo(context.Background(), 1); err != nil {
			t.Fatalf("esperado fail-open (nil), obtido %v", err)
		}
	})

	t.Run("rejeita quando ngo-service responde 404", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusNotFound)
		}))
		defer srv.Close()

		app := &App{NgoServiceURL: srv.URL, HTTPClient: http.DefaultClient}
		if err := app.validateNgo(context.Background(), 999); err == nil {
			t.Fatal("esperado erro para ONG inexistente, obtido nil")
		}
	})

	t.Run("aceita quando ngo-service responde 200", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
		}))
		defer srv.Close()

		app := &App{NgoServiceURL: srv.URL, HTTPClient: http.DefaultClient}
		if err := app.validateNgo(context.Background(), 1); err != nil {
			t.Fatalf("esperado nil, obtido %v", err)
		}
	})
}

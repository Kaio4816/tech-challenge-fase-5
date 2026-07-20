import os
import sys
import time
import logging
import psycopg2
from psycopg2.extras import RealDictCursor
from psycopg2.pool import SimpleConnectionPool
from flask import Flask, request, jsonify
from dotenv import load_dotenv
from prometheus_flask_exporter import PrometheusMetrics

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

load_dotenv()

app = Flask(__name__)
metrics = PrometheusMetrics(app, group_by='endpoint')
metrics.info('ngo_service_info', 'ngo-service build info', service='ngo-service')

DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    log.critical("Erro: DATABASE_URL não definida.")
    sys.exit(1)

DB_CONNECT_MAX_ATTEMPTS = int(os.getenv("DB_CONNECT_MAX_ATTEMPTS", "10"))
DB_CONNECT_MAX_BACKOFF_SECONDS = 30


def create_pool_with_retry(dsn, max_attempts):
    """Cria o pool de conexões com retry e backoff exponencial.

    Evita que o processo morra imediatamente (sys.exit) enquanto o
    Postgres/RDS ainda está subindo, o que causaria CrashLoopBackOff no
    Kubernetes durante o rollout inicial do ambiente.
    """
    backoff = 1
    last_error = None
    for attempt in range(1, max_attempts + 1):
        try:
            new_pool = SimpleConnectionPool(1, 10, dsn=dsn)
            log.info("Pool de conexões com o PostgreSQL (ngo-service) inicializado.")
            return new_pool
        except Exception as e:
            last_error = e
            log.warning(f"Tentativa {attempt}/{max_attempts} de conexão com o banco falhou: {e}")
            if attempt == max_attempts:
                break
            time.sleep(backoff)
            backoff = min(backoff * 2, DB_CONNECT_MAX_BACKOFF_SECONDS)

    log.critical(f"Erro ao conectar ao PostgreSQL após {max_attempts} tentativas: {last_error}")
    sys.exit(1)


pool = create_pool_with_retry(DATABASE_URL, DB_CONNECT_MAX_ATTEMPTS)


@app.route('/health')
def health():
    return jsonify({"status": "ok", "service": "ngo-service"})


@app.route('/ready')
def ready():
    conn = None
    try:
        conn = pool.getconn()
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
        return jsonify({"status": "ready", "service": "ngo-service"}), 200
    except Exception as e:
        log.error(f"Readiness check falhou: {e}")
        return jsonify({"status": "not ready", "service": "ngo-service"}), 503
    finally:
        if conn is not None:
            pool.putconn(conn)


@app.route('/ngos', methods=['POST'])
def create_ngo():
    data = request.get_json()
    if not data or not all(k in data for k in ('name', 'email', 'cause', 'city')):
        return jsonify({"error": "Campos obrigatórios ausentes"}), 400

    conn = pool.getconn()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "INSERT INTO ngos (name, email, cause, city) VALUES (%s, %s, %s, %s) RETURNING *",
                (data['name'], data['email'], data['cause'], data['city'])
            )
            new_ngo = cur.fetchone()
            conn.commit()
            return jsonify(new_ngo), 201
    except psycopg2.IntegrityError:
        conn.rollback()
        return jsonify({"error": "E-mail já cadastrado"}), 409
    except Exception as e:
        conn.rollback()
        log.error(f"Erro ao criar ONG: {e}")
        return jsonify({"error": "Erro interno"}), 500
    finally:
        pool.putconn(conn)


@app.route('/ngos', methods=['GET'])
def get_ngos():
    conn = pool.getconn()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT * FROM ngos ORDER BY id DESC")
            return jsonify(cur.fetchall()), 200
    except Exception as e:
        log.error(f"Erro ao buscar ONGs: {e}")
        return jsonify({"error": "Erro interno"}), 500
    finally:
        pool.putconn(conn)


@app.route('/ngos/<int:ngo_id>', methods=['GET'])
def get_ngo(ngo_id):
    """Usado pelo donation-service para validar a existência da ONG antes
    de registrar uma doação (ver docs/architecture.md — distributed tracing).
    """
    conn = pool.getconn()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT * FROM ngos WHERE id = %s", (ngo_id,))
            ngo = cur.fetchone()
            if ngo is None:
                return jsonify({"error": "ONG não encontrada"}), 404
            return jsonify(ngo), 200
    except Exception as e:
        log.error(f"Erro ao buscar ONG {ngo_id}: {e}")
        return jsonify({"error": "Erro interno"}), 500
    finally:
        pool.putconn(conn)

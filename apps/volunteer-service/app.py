import os
import sys
import time
import uuid
import logging
import boto3
from boto3.dynamodb.conditions import Attr
from flask import Flask, request, jsonify
from dotenv import load_dotenv
from prometheus_flask_exporter import PrometheusMetrics

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

load_dotenv()

app = Flask(__name__)
metrics = PrometheusMetrics(app, group_by='endpoint')
metrics.info('volunteer_service_info', 'volunteer-service build info', service='volunteer-service')

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
DYNAMODB_TABLE = os.getenv("AWS_DYNAMODB_TABLE")
# Só usada localmente, contra um DynamoDB Local (docker-compose); em AWS real
# a variável fica ausente e o SDK resolve o endpoint padrão da região.
DYNAMODB_ENDPOINT_URL = os.getenv("AWS_DYNAMODB_ENDPOINT_URL")

if not DYNAMODB_TABLE:
    log.critical("Erro: AWS_DYNAMODB_TABLE não definida.")
    sys.exit(1)

DB_CONNECT_MAX_ATTEMPTS = int(os.getenv("DB_CONNECT_MAX_ATTEMPTS", "10"))
DB_CONNECT_MAX_BACKOFF_SECONDS = 30


def connect_dynamodb_with_retry(table_name, region, endpoint_url, max_attempts):
    """Conecta e valida (DescribeTable via table.load()) a tabela DynamoDB
    com retry e backoff exponencial, pelo mesmo motivo do ngo-service: não
    matar o processo enquanto a dependência ainda está subindo.
    """
    backoff = 1
    last_error = None
    for attempt in range(1, max_attempts + 1):
        try:
            kwargs = {"region_name": region}
            if endpoint_url:
                kwargs["endpoint_url"] = endpoint_url
            resource = boto3.resource("dynamodb", **kwargs)
            candidate_table = resource.Table(table_name)
            candidate_table.load()
            log.info(f"Conectado à tabela DynamoDB: {table_name}")
            return candidate_table
        except Exception as e:
            last_error = e
            log.warning(f"Tentativa {attempt}/{max_attempts} de conexão com o DynamoDB falhou: {e}")
            if attempt == max_attempts:
                break
            time.sleep(backoff)
            backoff = min(backoff * 2, DB_CONNECT_MAX_BACKOFF_SECONDS)

    log.critical(f"Falha ao conectar no DynamoDB após {max_attempts} tentativas: {last_error}")
    sys.exit(1)


table = connect_dynamodb_with_retry(DYNAMODB_TABLE, AWS_REGION, DYNAMODB_ENDPOINT_URL, DB_CONNECT_MAX_ATTEMPTS)


@app.route('/health')
def health():
    return jsonify({"status": "ok", "service": "volunteer-service"})


@app.route('/ready')
def ready():
    try:
        table.load()
        return jsonify({"status": "ready", "service": "volunteer-service"}), 200
    except Exception as e:
        log.error(f"Readiness check falhou: {e}")
        return jsonify({"status": "not ready", "service": "volunteer-service"}), 503


@app.route('/volunteers', methods=['POST'])
def register_volunteer():
    data = request.get_json()
    if not data or not all(k in data for k in ('name', 'email', 'ngo_id')):
        return jsonify({"error": "Campos obrigatórios ausentes"}), 400

    volunteer_id = str(uuid.uuid4())
    item = {
        'volunteer_id': volunteer_id,
        'name': data['name'],
        'email': data['email'],
        'ngo_id': int(data['ngo_id']),
        'registered_at': str(int(time.time()))
    }

    try:
        table.put_item(Item=item)
        return jsonify(item), 201
    except Exception as e:
        log.error(f"Erro ao salvar voluntário no DynamoDB: {e}")
        return jsonify({"error": "Erro interno ao processar dados"}), 500


@app.route('/volunteers/<int:ngo_id>', methods=['GET'])
def get_volunteers_by_ngo(ngo_id):
    try:
        # Nota para avaliação dos alunos: Operação Scan simplificada para fins de desenvolvimento.
        # Em cenários complexos de produção, índices globais secundários (GSI) seriam exigidos.
        response = table.scan(
            FilterExpression=Attr('ngo_id').eq(ngo_id)
        )
        return jsonify(response.get('Items', [])), 200
    except Exception as e:
        log.error(f"Erro ao buscar dados no DynamoDB: {e}")
        return jsonify({"error": "Erro interno"}), 500


if __name__ == '__main__':
    port = int(os.getenv("PORT", 8083))
    app.run(host='0.0.0.0', port=port)

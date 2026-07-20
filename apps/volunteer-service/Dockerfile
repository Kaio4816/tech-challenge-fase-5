# syntax=docker/dockerfile:1
FROM python:3.12-slim AS build
WORKDIR /install
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install/deps -r requirements.txt

FROM python:3.12-slim
RUN useradd --create-home --uid 1000 appuser
WORKDIR /app
COPY --from=build /install/deps /usr/local
COPY app.py .
USER appuser
# Casa com o exporter instalado (opentelemetry-exporter-otlp-proto-http);
# sem isso a auto-instrumentação tenta o exporter gRPC por padrão, que não
# está no requirements.txt, e falha ao subir. Métricas/logs via OTel ficam
# desligados aqui: métricas já saem pelo prometheus-flask-exporter (/metrics).
ENV OTEL_TRACES_EXPORTER=otlp \
    OTEL_METRICS_EXPORTER=none \
    OTEL_LOGS_EXPORTER=none \
    OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
EXPOSE 8083
CMD ["opentelemetry-instrument", "gunicorn", "--bind", "0.0.0.0:8083", "--workers", "2", "app:app"]

package main

import (
	"context"
	"fmt"
	"os"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"
)

// initTracing configura o SDK de OpenTelemetry para exportar traces via
// OTLP/HTTP (ex.: New Relic) quando OTEL_EXPORTER_OTLP_ENDPOINT estiver
// definida. Sem essa variável, o tracer global permanece no-op (nenhum span
// é exportado) e o retorno é um shutdown vazio — assim o serviço roda
// normalmente em ambientes sem observabilidade configurada (ex.: dev local).
func initTracing(ctx context.Context) (func(context.Context) error, error) {
	noop := func(context.Context) error { return nil }

	if os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT") == "" {
		return noop, nil
	}

	serviceName := os.Getenv("OTEL_SERVICE_NAME")
	if serviceName == "" {
		serviceName = "donation-service"
	}

	exporter, err := otlptracehttp.New(ctx)
	if err != nil {
		return noop, fmt.Errorf("falha ao criar exporter OTLP: %w", err)
	}

	res, err := resource.New(ctx,
		resource.WithAttributes(semconv.ServiceName(serviceName)),
	)
	if err != nil {
		return noop, fmt.Errorf("falha ao criar resource OTel: %w", err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)

	return tp.Shutdown, nil
}

# syntax=docker/dockerfile:1
FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/donation-service .

# DEMONSTRACAO — NAO MERGEAR.
# Base propositalmente vulneravel (CVE-2021-36159, CRITICAL, com correcao
# disponivel) para provar em video que o job "Trivy (imagem)" bloqueia o
# pipeline. A base real e a distroless da branch main:
#     FROM gcr.io/distroless/static-debian12:nonroot
FROM alpine:3.10
WORKDIR /app
COPY --from=build /out/donation-service /app/donation-service
EXPOSE 8082
ENTRYPOINT ["/app/donation-service"]

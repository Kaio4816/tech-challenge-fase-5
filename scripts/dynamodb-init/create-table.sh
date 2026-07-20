#!/bin/sh
# Cria a tabela SolidaryTechVolunteers no DynamoDB Local usado pelo
# docker-compose (substitui a tabela real da AWS só para testes locais,
# custo zero). Idempotente: ignora o erro se a tabela já existir.
set -eu

aws dynamodb create-table \
  --endpoint-url "$AWS_DYNAMODB_ENDPOINT_URL" \
  --region "$AWS_REGION" \
  --table-name "$AWS_DYNAMODB_TABLE" \
  --attribute-definitions AttributeName=volunteer_id,AttributeType=S \
  --key-schema AttributeName=volunteer_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  || echo "Tabela $AWS_DYNAMODB_TABLE já existe, seguindo em frente."

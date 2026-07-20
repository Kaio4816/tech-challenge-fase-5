#!/bin/bash
# Roda automaticamente no primeiro start do container postgres
# (docker-entrypoint-initdb.d). Cria os dois bancos usados pelos
# microsserviços e aplica o schema de cada um a partir dos mesmos
# db/init.sql versionados em apps/<serviço>/db/, sem duplicar SQL.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE ngo_db;
    CREATE DATABASE donation_db;
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname ngo_db -f /sql/ngo_init.sql
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname donation_db -f /sql/donation_init.sql

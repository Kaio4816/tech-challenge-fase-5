# Credenciais NUNCA em arquivo versionado: o provider lê
# NEW_RELIC_ACCOUNT_ID, NEW_RELIC_API_KEY (User key, prefixo NRAK-) e
# NEW_RELIC_REGION do ambiente. Ver docs/itsm-incident-flow.md para o
# passo a passo de onde obter cada valor.
provider "newrelic" {}

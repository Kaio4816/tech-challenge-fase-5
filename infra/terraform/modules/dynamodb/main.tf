# Tabela do volunteer-service, pay-per-request (custo ~zero no volume do
# hackathon). Quando var.replica_regions não é vazio, vira uma Global Table
# v2 — a réplica em us-east-2 dá RPO ~0 para os dados de voluntários sem
# precisar de nenhum passo manual de DR (diferente do Postgres, que depende
# de cópia de snapshot).

resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "volunteer_id"

  attribute {
    name = "volunteer_id"
    type = "S"
  }

  stream_enabled   = length(var.replica_regions) > 0
  stream_view_type = length(var.replica_regions) > 0 ? "NEW_AND_OLD_IMAGES" : null

  dynamic "replica" {
    for_each = var.replica_regions
    content {
      region_name = replica.value
    }
  }

  tags = var.tags
}

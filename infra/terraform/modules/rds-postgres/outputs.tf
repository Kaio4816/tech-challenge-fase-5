output "address" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "endpoint" {
  value = aws_db_instance.this.endpoint
}

output "master_username" {
  value = aws_db_instance.this.username
}

output "master_password" {
  value     = random_password.master.result
  sensitive = true
}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "db_instance_id" {
  # aws_db_instance.id é o DbiResourceId (formato "db-XXXX...", usado em ARNs
  # de eventos), não o identifier legível — para comandos como
  # `aws rds create-db-snapshot --db-instance-identifier`, precisa do
  # .identifier (o mesmo valor de "identifier" no resource, ex.:
  # "solidarytech-primary-postgres"). Achado rodando o ensaio de DR real.
  value = aws_db_instance.this.identifier
}

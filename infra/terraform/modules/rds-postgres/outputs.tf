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
  value     = var.snapshot_identifier == null ? random_password.master[0].result : null
  sensitive = true
}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "db_instance_id" {
  value = aws_db_instance.this.id
}

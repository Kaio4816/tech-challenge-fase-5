# RDS Postgres custo-mínimo: 1 instância db.t4g.micro single-AZ. Reusado tanto
# no primary (nasce vazia) quanto no dr (nasce restaurada de um snapshot via
# var.snapshot_identifier) — é essa reutilização que materializa o warm
# standby (ver docs/dr-plan.md).

resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-db-subnets"
  subnet_ids = var.subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "this" {
  name_prefix = "${var.name_prefix}-rds-"
  description = "Postgres do ngo-service e donation-service"
  vpc_id      = var.vpc_id

  # Descricoes sem acentuacao: a AWS restringe ingress.description ao regex
  # ^[0-9A-Za-z_ .:/()#,@\[\]+=&;{}!$*-]*$ (sem caracteres acentuados).
  ingress {
    description     = "Postgres from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
  }

  dynamic "ingress" {
    for_each = var.admin_cidr_blocks
    content {
      description = "Admin access (Terraform database bootstrap)"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "random_password" "master" {
  length  = 20
  special = false
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name_prefix}-postgres"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"

  # Restaura de snapshot (DR) quando fornecido — username/databases já vêm do
  # snapshot (por isso username fica null nesse caso: mudar o master username
  # não é suportado num restore). A senha, porém, é sempre gerada pelo
  # Terraform e resetada pela AWS logo após o restore (ModifyDBInstance) —
  # assim o envs/dr nunca depende de conhecer a senha original do primary
  # (que pode estar inacessível justamente num cenário de desastre real).
  snapshot_identifier = var.snapshot_identifier
  username            = var.snapshot_identifier == null ? var.master_username : null
  password            = random_password.master.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]

  multi_az            = false
  publicly_accessible = var.publicly_accessible

  backup_retention_period = var.backup_retention_period
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  tags = var.tags
}

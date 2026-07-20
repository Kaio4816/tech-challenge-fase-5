# Fila de eventos de doação (publicada pelo donation-service após cada
# doação aprovada) + dead-letter queue.

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name_prefix}-donation-events-dlq"
  message_retention_seconds = 1209600 # 14 dias

  tags = var.tags
}

resource "aws_sqs_queue" "this" {
  name                       = "${var.name_prefix}-donation-events"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600 # 4 dias

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })

  tags = var.tags
}

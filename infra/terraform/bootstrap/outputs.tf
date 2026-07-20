output "bucket_name" {
  description = "Nome do bucket S3 de state — usar em envs/*/backend.hcl."
  value       = aws_s3_bucket.tfstate.id
}

output "bucket_arn" {
  value = aws_s3_bucket.tfstate.arn
}

output "region" {
  value = var.region
}

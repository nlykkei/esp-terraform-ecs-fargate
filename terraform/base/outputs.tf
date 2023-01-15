output "aws_region" {
  value       = var.aws_region
  description = "AWS region"
}

output "s3_bucket" {
  value = aws_s3_bucket.terraform_state.bucket
  description = "S3 bucket for Terraform state"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.repository.repository_url
  description = "ECS repository URL"
}

output "ecr_repository_name" {
  value = aws_ecr_repository.repository.name
  description = "ECS repository name"
}

output "publisher_user" {
  value = aws_iam_user.user.arn
  description = "AWS user to publish tasks"
}

output "publisher_access_key" {
  value = aws_iam_access_key.access_key.id
  description = "AWS_ACCESS_KEY to publish tasks"
}

output "publisher_secret_key" {
  value = nonsensitive(aws_iam_access_key.access_key.secret)
  description = "AWS_SECRET_ACCESS_KEY to publish tasks"
}
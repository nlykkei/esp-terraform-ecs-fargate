output "aws_region" {
  value       = var.aws_region
  description = "AWS region"
}

output "app_url" {
  value       = aws_lb.main.dns_name
  description = "Application URL"
}

output "ecs_cluster" {
  value       = aws_ecs_cluster.main.name
  description = "ECS cluster"
}

output "ecs_app_service" {
  value       = aws_ecs_service.app.name
  description = "ECS app service"
}

output "ecs_app_task" {
  value       = aws_ecs_service.app.task_definition
  description = "ECS app task"
}

output "ecs_app_container" {
  value       = local.app.container.name
  description = "ECS app container"
}

output "ecs_app_image" {
  value       = local.app.container.image
  description = "ECS app image"
}

output "ecs_api_service" {
  value       = aws_ecs_service.api.name
  description = "ECS api service"
}

output "ecs_api_task" {
  value       = aws_ecs_service.api.task_definition
  description = "ECS api task"
}

output "ecs_api_container" {
  value       = local.api.container.name
  description = "ECS api container"
}

output "ecs_api_image" {
  value       = local.api.container.image
  description = "ECS api image"
}

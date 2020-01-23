# ------------------------------------------------------------------------------
# Output
# ------------------------------------------------------------------------------
output "service_arn" {
  description = "The Amazon Resource Name (ARN) that identifies the service."
  value       = aws_ecs_service.service.id
}

output "target_groups" {
  description = "All Target Groups."
  value       = zipmap(values(aws_lb_target_group.task)[*]["port"], values(aws_lb_target_group.task)[*]["arn"])
}

output "task_role_arn" {
  description = "The Amazon Resource Name (ARN) specifying the service role."
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "The name of the service role."
  value       = aws_iam_role.task.name
}

output "service_sg_id" {
  description = "The Amazon Resource Name (ARN) that identifies the service security group."
  value       = aws_security_group.ecs_service.id
}

output "service_name" {
  description = "The name of the service."
  value       = aws_ecs_service.service.name
}

output "log_group_name" {
  description = "The name of the Cloudwatch log group for the task."
  value       = aws_cloudwatch_log_group.main.name
}


# ------------------------------------------------------------------------------
# Output
# ------------------------------------------------------------------------------
output "service_arn" {
  description = "The Amazon Resource Name (ARN) that identifies the service."
  value       = aws_ecs_service.service.id
}

output "target_group_arn" {
  description = "The ARN of the Target Group."
  value       = var.lb_arn == "" ? null : aws_lb_target_group.task[0].arn
}

output "target_group_name" {
  description = "The Name of the Target Group."
  value       = var.lb_arn == "" ? null : aws_lb_target_group.task[0].name
}

output "task_role_arn" {
  description = "The Amazon Resource Name (ARN) specifying the service role."
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "The name of the service role."
  value       = aws_iam_role.task.name
}

output "task_execution_role_arn" {
  description = "The Amazon Resource Name (ARN) specifying the execution service role."
  value       = aws_iam_role.execution.arn
}

output "task_execution_role_name" {
  description = "The name of the execution service role."
  value       = aws_iam_role.execution.name
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
  value       = var.log_group_name != "" ? var.log_group_name : aws_cloudwatch_log_group.main.0.name
}

output "desired_count" {
  description = "Desired count"
  value       = var.desired_count
}


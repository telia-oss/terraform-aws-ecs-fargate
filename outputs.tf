# ------------------------------------------------------------------------------
# Output
# ------------------------------------------------------------------------------
output "service_arn" {
  description = "The Amazon Resource Name (ARN) that identifies the service."
  value       = "${aws_ecs_service.service.id}"
}

output "target_group_arn" {
  description = "The ARN of the Target Group."
  value       = "${aws_lb_target_group.task.arn}"
}

output "target_group_name" {
  description = "The Name of the Target Group."
  value       = "${aws_lb_target_group.task.name}"
}

output "task_role_arn" {
  description = "The Amazon Resource Name (ARN) specifying the service role."
  value       = "${aws_iam_role.task.arn}"
}

output "task_role_name" {
  description = "The name of the service role."
  value       = "${aws_iam_role.task.name}"
}

output "service_sg_id" {
  description = "The Amazon Resource Name (ARN) that identifies the service security group."
  value       = "${aws_security_group.ecs_service.id}"
}

output "task_definition_arn" {
  description = "The ARN of the task definition."
  value       = "${aws_ecs_task_definition.task.arn}"
}

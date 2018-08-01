# ------------------------------------------------------------------------------
# Output
# ------------------------------------------------------------------------------
output "service_arn" {
  value = "${aws_ecs_service.service.id}"
}

output "target_group_arn" {
  value = "${aws_lb_target_group.task.arn}"
}

output "task_role_arn" {
  value = "${aws_iam_role.task.arn}"
}

output "task_role_name" {
  value = "${aws_iam_role.task.name}"
}

output "service_sg_id" {
  value = "${aws_security_group.ecs_service.id}"
}

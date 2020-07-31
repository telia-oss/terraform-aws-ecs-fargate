output "cluster_arn" {
  value = aws_ecs_cluster.cluster.arn
}

output "service_arn" {
  value = module.fargate.service_arn
}

output "endpoint" {
  value = module.fargate_alb.dns_name
}

# ------------------------------------------------------------------------------
# AWS
# ------------------------------------------------------------------------------
data "aws_region" "current" {}

# ------------------------------------------------------------------------------
# Cloudwatch
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "main" {
  name              = var.name_prefix
  retention_in_days = var.log_retention_in_days
  tags              = var.tags
}

# ------------------------------------------------------------------------------
# IAM - Task execution role, needed to pull ECR images etc.
# ------------------------------------------------------------------------------
resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy" "task_execution" {
  name   = "${var.name_prefix}-task-execution"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.task_execution_permissions.json
}

resource "aws_iam_role_policy" "read_repository_credentials" {
  count  = length(var.repository_credentials) != 0 ? 1 : 0
  name   = "${var.name_prefix}-read-repository-credentials"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.read_repository_credentials.json
}

# ------------------------------------------------------------------------------
# IAM - Task role, basic. Users of the module will append policies to this role
# when they use the module. S3, Dynamo permissions etc etc.
# ------------------------------------------------------------------------------
resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-task-role"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy" "log_agent" {
  name   = "${var.name_prefix}-log-permissions"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_permissions.json
}

# ------------------------------------------------------------------------------
# Security groups
# ------------------------------------------------------------------------------
resource "aws_security_group" "ecs_service" {
  vpc_id      = var.vpc_id
  name        = "${var.name_prefix}-ecs-service-sg"
  description = "Fargate service security group"
  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-sg"
    },
  )
}

resource "aws_security_group_rule" "egress_service" {
  security_group_id = aws_security_group.ecs_service.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

# ------------------------------------------------------------------------------
# LB Target group
# ------------------------------------------------------------------------------
resource "aws_lb_target_group" "task" {

  for_each = var.task_container_port_protocol

  vpc_id      = var.vpc_id
  protocol    = each.value.protocol
  port        = each.value.containerPort
  target_type = "ip"

  # Note: The Health Check parameters you can set vary by the protocol of the Target Group
  health_check {
    healthy_threshold   = each.value.healthy_threshold
    unhealthy_threshold = each.value.unhealthy_threshold
    interval            = each.value.interval
    timeout             = each.value.health_check_timeout
    path                = each.value.health_check_path
    port                = each.value.containerPort
    protocol            = each.value.protocol
    matcher             = each.value.health_check_matcher
  }

  # NOTE: TF is unable to destroy a target group while a listener is attached,
  # therefor we have to create a new one before destroying the old. This also means
  # we have to let it have a random name, and then tag it with the desired name.
  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-target-${each.value.containerPort}"
    },
  )
}

# ------------------------------------------------------------------------------
# ECS Task/Service
# ------------------------------------------------------------------------------
locals {
  task_environment = [
    for k, v in var.task_container_environment : {
      name  = k
      value = v
    }
  ]
}

locals {
  container_port_protocol_mapping = [
    for o in var.task_container_port_protocol : {
      containerPort = o.containerPort
      hostPort      = o.hostPort
      protocol      = "tcp"
    }
  ]
}

resource "aws_ecs_task_definition" "task" {
  family                   = var.name_prefix
  execution_role_arn       = aws_iam_role.execution.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_definition_cpu
  memory                   = var.task_definition_memory
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = <<EOF
[{
    "name": "${var.container_name != "" ? var.container_name : var.name_prefix}",
    "image": "${var.task_container_image}",
    %{if var.repository_credentials != ""~}
    "repositoryCredentials": {
        "credentialsParameter": "${var.repository_credentials}"
    },
    %{~endif}
    "essential": true,
    "portMappings": ${jsonencode(local.container_port_protocol_mapping)},
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
            "awslogs-group": "${aws_cloudwatch_log_group.main.name}",
            "awslogs-region": "${data.aws_region.current.name}",
            "awslogs-stream-prefix": "container"
        }
    },
    "stopTimeout": ${var.stop_timeout},
    "command": ${jsonencode(var.task_container_command)},
    "environment": ${jsonencode(local.task_environment)}
}]
EOF
}

resource "aws_ecs_service" "service" {
  depends_on                         = [null_resource.lb_exists]
  name                               = var.name_prefix
  cluster                            = var.cluster_id
  task_definition                    = aws_ecs_task_definition.task.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  health_check_grace_period_seconds  = var.lb_arn == "" ? null : var.health_check_grace_period_seconds

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_service.id]
    assign_public_ip = var.task_container_assign_public_ip
  }

  # Assoicate target groups to ECS service in order to used by load balancer
  dynamic "load_balancer" {
    for_each = var.lb_arn == "" ? {} : aws_lb_target_group.task

    content {
      container_name   = var.container_name != "" ? var.container_name : var.name_prefix
      container_port   = load_balancer.value.port
      target_group_arn = load_balancer.value.arn
    }
  }

  deployment_controller {
    # The deployment controller type to use. Valid values: CODE_DEPLOY, ECS.
    type = var.deployment_controller_type
  }

  dynamic "service_registries" {
    for_each = var.service_registry_arn == "" ? {} : aws_lb_target_group.task
    content {
      registry_arn   = var.service_registry_arn
      container_port = service_registries.value.port
      container_name = var.container_name != "" ? var.container_name : var.name_prefix
    }
  }
}

# HACK: The workaround used in ecs/service does not work for some reason in this module, this fixes the following error:
# "The target group with targetGroupArn arn:aws:elasticloadbalancing:... does not have an associated load balancer."
# see https://github.com/hashicorp/terraform/issues/12634.
#     https://github.com/terraform-providers/terraform-provider-aws/issues/3495
# Service depends on this resources which prevents it from being created until the LB is ready
resource "null_resource" "lb_exists" {
  triggers = var.lb_arn == "" ? {} : { alb_name = var.lb_arn }
}

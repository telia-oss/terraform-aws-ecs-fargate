# ------------------------------------------------------------------------------
# AWS
# ------------------------------------------------------------------------------
data "aws_region" "current" {
}

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
  vpc_id      = var.vpc_id
  protocol    = var.task_container_protocol
  port        = var.task_container_port
  target_type = "ip"
  dynamic "health_check" {
    for_each = [var.health_check]
    content {
      enabled             = lookup(health_check.value, "enabled", null)
      healthy_threshold   = lookup(health_check.value, "healthy_threshold", null)
      interval            = lookup(health_check.value, "interval", null)
      matcher             = lookup(health_check.value, "matcher", null)
      path                = lookup(health_check.value, "path", null)
      port                = lookup(health_check.value, "port", null)
      protocol            = lookup(health_check.value, "protocol", null)
      timeout             = lookup(health_check.value, "timeout", null)
      unhealthy_threshold = lookup(health_check.value, "unhealthy_threshold", null)
    }
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
      Name = "${var.name_prefix}-target-${var.task_container_port}"
    },
  )
}

# ------------------------------------------------------------------------------
# ECS Task/Service
# ------------------------------------------------------------------------------
data "null_data_source" "task_environment" {
  count = var.task_container_environment_count

  inputs = {
    name  = element(keys(var.task_container_environment), count.index)
    value = element(values(var.task_container_environment), count.index)
  }
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
    ${local.repository_credentials_rendered}
    "essential": true,
    "portMappings": [
        {
            "containerPort": ${var.task_container_port},
            "hostPort": ${var.task_container_port},
            "protocol":"tcp"
        }
    ],
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
            "awslogs-group": "${aws_cloudwatch_log_group.main.name}",
            "awslogs-region": "${data.aws_region.current.name}",
            "awslogs-stream-prefix": "container"
        }
    },
    "command": ${jsonencode(var.task_container_command)},
    "environment": ${jsonencode(data.null_data_source.task_environment.*.outputs)}
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
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_service.id]
    assign_public_ip = var.task_container_assign_public_ip
  }

  load_balancer {
    container_name   = var.container_name != "" ? var.container_name : var.name_prefix
    container_port   = var.task_container_port
    target_group_arn = aws_lb_target_group.task.arn
  }

  deployment_controller {
    # The deployment controller type to use. Valid values: CODE_DEPLOY, ECS.
    type = var.deployment_controller_type
  }
}

# HACK: The workaround used in ecs/service does not work for some reason in this module, this fixes the following error:
# "The target group with targetGroupArn arn:aws:elasticloadbalancing:... does not have an associated load balancer."
# see https://github.com/hashicorp/terraform/issues/12634.
# Service depends on this resources which prevents it from being created until the LB is ready
resource "null_resource" "lb_exists" {
  triggers = {
    alb_name = var.lb_arn
  }
}


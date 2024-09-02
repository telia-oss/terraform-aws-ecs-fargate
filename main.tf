# ------------------------------------------------------------------------------
# AWS
# ------------------------------------------------------------------------------
data "aws_region" "current" {}

# ------------------------------------------------------------------------------
# Cloudwatch
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "main" {
  count             = var.log_group_name != "" ? 0 : 1
  name              = var.name_prefix
  retention_in_days = var.log_retention_in_days
  tags              = var.tags
}

# ------------------------------------------------------------------------------
# IAM - Task execution role, needed to pull ECR images etc.
# ------------------------------------------------------------------------------
resource "aws_iam_role" "execution" {
  name                 = "${var.name_prefix}${var.aws_iam_role_execution_suffix}"
  assume_role_policy   = data.aws_iam_policy_document.task_assume.json
  permissions_boundary = var.task_role_permissions_boundary_arn
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

resource "aws_iam_role_policy" "read_task_container_secrets" {
  name   = "${var.name_prefix}-read-task-container-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.task_container_secrets.json
}

# ------------------------------------------------------------------------------
# IAM - Task role, basic. Users of the module will append policies to this role
# when they use the module. S3, Dynamo permissions etc etc.
# ------------------------------------------------------------------------------
resource "aws_iam_role" "task" {
  name                 = "${var.name_prefix}${var.aws_iam_role_task_suffix}"
  assume_role_policy   = data.aws_iam_policy_document.task_assume.json
  permissions_boundary = var.task_role_permissions_boundary_arn
}

resource "aws_iam_role_policy" "log_agent" {
  count  = var.log_group_name != "" ? 0 : 1
  name   = "${var.name_prefix}-log-permissions"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_permissions.json
}

resource "aws_iam_role_policy" "ssm_agent" {
  count  = var.enable_execute_command ? 1 : 0
  name   = "${var.name_prefix}-ssm-permissions"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.ssm_task_permissions.json
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
  name        = "${var.name_prefix}-${var.task_container_port}"
  count       = var.lb_arn == "" ? 0 : 1
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
  protocol_version = var.protocol_version

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
locals {
  log_multiline_pattern        = var.log_multiline_pattern != "" ? { "awslogs-multiline-pattern" = var.log_multiline_pattern } : null
  task_container_secrets       = length(var.task_container_secrets) > 0 ? { "secrets" = var.task_container_secrets } : null
  repository_credentials       = length(var.repository_credentials) > 0 ? { "repositoryCredentials" = { "credentialsParameter" = var.repository_credentials } } : null
  task_container_health_check  = length(var.task_container_health_check) > 0 ? { "healthCheck" = var.task_container_health_check } : null
  task_container_port_mappings = var.task_container_port == 0 ? var.task_container_port_mappings : concat(var.task_container_port_mappings, [{ containerPort = var.task_container_port, hostPort = var.task_container_port, protocol = "tcp" }])
  task_container_environment   = [for k, v in var.task_container_environment : { name = k, value = v }]
  task_container_mount_points  = concat([for v in var.efs_volumes : { containerPath = v.mount_point, readOnly = v.readOnly, sourceVolume = v.name }], var.mount_points)

  log_configuration_options = merge({
    "awslogs-group"         = var.log_group_name != "" ? var.log_group_name : aws_cloudwatch_log_group.main.0.name,
    "awslogs-region"        = data.aws_region.current.name
    "awslogs-stream-prefix" = "container"
  }, local.log_multiline_pattern)

  container_definition = merge({
    "name"             = var.container_name != "" ? var.container_name : var.name_prefix
    "image"            = var.task_container_image,
    "essential"        = true
    "portMappings"     = local.task_container_port_mappings
    "stopTimeout"      = var.stop_timeout
    "command"          = var.task_container_command
    "environment"      = local.task_container_environment
    "environmentFiles" = var.task_container_environment_file
    "MountPoints"      = local.task_container_mount_points
    "logConfiguration" = {
      "logDriver" = "awslogs"
      "options"   = local.log_configuration_options
    }
    "privileged" : var.privileged
    "readonlyRootFilesystem" : var.readonlyRootFilesystem
  }, local.task_container_secrets, local.repository_credentials, local.task_container_health_check)
}

resource "aws_ecs_task_definition" "task" {
  family                   = var.name_prefix
  execution_role_arn       = aws_iam_role.execution.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_definition_cpu
  memory                   = var.task_definition_memory
  task_role_arn            = aws_iam_role.task.arn
  dynamic "volume" {
    for_each = var.efs_volumes
    content {
      name = volume.value["name"]
      efs_volume_configuration {
        file_system_id     = volume.value["file_system_id"]
        root_directory     = volume.value["root_directory"]
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = volume.value["access_point_id"]
          iam             = "ENABLED"
        }
      }
    }
  }
  dynamic "volume" {
    for_each = var.volumes
    content {
      name = volume.value["name"]
    }
  }

  ephemeral_storage {
    size_in_gib = var.task_ephemeral_storage
  }

  container_definitions = jsonencode(concat([local.container_definition], var.sidecar_containers))
  runtime_platform {
    operating_system_family = var.task_definition_os_family
    cpu_architecture        = var.task_definition_cpu_arch
  }
}

resource "aws_ecs_service" "service" {
  depends_on = [
    null_resource.lb_exists,
    aws_iam_role_policy.task_execution,
    aws_iam_role_policy.log_agent,
    aws_iam_role_policy.read_repository_credentials,
    aws_iam_role_policy.read_task_container_secrets,
  ]
  name                               = var.name_prefix
  cluster                            = var.cluster_id
  task_definition                    = var.task_definition != "" ? var.task_definition : aws_ecs_task_definition.task.arn
  desired_count                      = var.desired_count
  launch_type                        = length(var.capacity_provider_strategy) == 0 ? "FARGATE" : null
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  health_check_grace_period_seconds  = var.lb_arn == "" ? null : var.health_check_grace_period_seconds
  wait_for_steady_state              = var.wait_for_steady_state
  enable_execute_command             = var.enable_execute_command
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = concat([aws_security_group.ecs_service.id], var.service_sg_ids)
    assign_public_ip = var.task_container_assign_public_ip
  }

  dynamic "load_balancer" {
    for_each = var.lb_arn == "" ? [] : [1]
    content {
      container_name   = var.container_name != "" ? var.container_name : var.name_prefix
      container_port   = var.task_container_port
      target_group_arn = aws_lb_target_group.task[0].arn
    }
  }

  dynamic "load_balancer" {
    for_each = length(var.extra_target_groups) == 0 ? [] : var.extra_target_groups
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

  deployment_circuit_breaker {
    enable   = var.deployment_circuit_breaker.enable
    rollback = var.deployment_circuit_breaker.rollback
  }

  dynamic "service_registries" {
    for_each = var.service_registry_arn == "" ? [] : [1]
    content {
      registry_arn   = var.service_registry_arn
      container_port = var.with_service_discovery_srv_record ? var.task_container_port : null
      container_name = var.container_name != "" ? var.container_name : var.name_prefix
    }
  }
  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy
    content {
      base              = lookup(capacity_provider_strategy.value, "base", null)
      capacity_provider = lookup(capacity_provider_strategy.value, "capacity_provider", null)
      weight            = lookup(capacity_provider_strategy.value, "weight", null)
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

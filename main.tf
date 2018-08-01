# ------------------------------------------------------------------------------
# AWS
# ------------------------------------------------------------------------------
data "aws_region" "current" {}

# ------------------------------------------------------------------------------
# Cloudwatch
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "main" {
  name              = "${var.name_prefix}"
  retention_in_days = "${var.log_retention_in_days}"
  tags              = "${var.tags}"
}

# ------------------------------------------------------------------------------
# IAM - Task execution role, needed to pull ECR images etc.
# ------------------------------------------------------------------------------
resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-task-execution-role"
  assume_role_policy = "${data.aws_iam_policy_document.task_assume.json}"
}

resource "aws_iam_role_policy" "task_execution" {
  name   = "${var.name_prefix}-task-execution"
  role   = "${aws_iam_role.execution.id}"
  policy = "${data.aws_iam_policy_document.task_execution_permissions.json}"
}

# ------------------------------------------------------------------------------
# IAM - Task role, basic. Users of the module will append policies to this role
# when they use the module. S3, Dynamo permissions etc etc.
# ------------------------------------------------------------------------------
resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-task-role"
  assume_role_policy = "${data.aws_iam_policy_document.task_assume.json}"
}

resource "aws_iam_role_policy" "log_agent" {
  name   = "${var.name_prefix}-log-permissions"
  role   = "${aws_iam_role.task.id}"
  policy = "${data.aws_iam_policy_document.task_permissions.json}"
}

# ------------------------------------------------------------------------------
# Security groups
# ------------------------------------------------------------------------------
resource "aws_security_group" "ecs_service" {
  vpc_id      = "${var.vpc_id}"
  name        = "${var.name_prefix}-ecs-service-sg"
  description = "Fargate service security group"
  tags        = "${var.tags}"
}

resource "aws_security_group_rule" "ingress_service" {
  security_group_id = "${aws_security_group.ecs_service.id}"
  type              = "ingress"
  protocol          = "icmp"
  from_port         = "8"
  to_port           = "0"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "egress_service" {
  security_group_id = "${aws_security_group.ecs_service.id}"
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}

# ------------------------------------------------------------------------------
# LB Target group
# ------------------------------------------------------------------------------
resource "aws_lb_target_group" "task" {
  vpc_id       = "${var.vpc_id}"
  protocol     = "${var.task_container_protocol}"
  port         = "${var.task_container_port}"
  target_type  = "ip"
  health_check = ["${var.health_check}"]

  # NOTE: TF is unable to destroy a target group while a listener is attached,
  # therefor we have to create a new one before destroying the old. This also means
  # we have to let it have a random name, and then tag it with the desired name.
  lifecycle {
    create_before_destroy = true
  }

  tags = "${merge(var.tags, map("Name", "${var.name_prefix}-target-${var.task_container_port}"))}"
}

# ------------------------------------------------------------------------------
# ECS Task/Service
# ------------------------------------------------------------------------------
data "null_data_source" "task_environment" {
  count = "${var.task_definition_environment_count}"

  inputs = {
    name  = "${element(keys(var.task_definition_environment), count.index)}"
    value = "${element(values(var.task_definition_environment), count.index)}"
  }
}

resource "aws_ecs_task_definition" "task" {
  family                   = "${var.name_prefix}"
  execution_role_arn       = "${aws_iam_role.execution.arn}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "${var.task_definition_cpu}"
  memory                   = "${var.task_definition_memory}"
  task_role_arn            = "${aws_iam_role.task.arn}"

  container_definitions = <<EOF
[{
    "cpu":0,
    "name": "${var.name_prefix}",
    "image": "${var.task_definition_image}",
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
    "environment": ${jsonencode(data.null_data_source.task_environment.*.outputs)}
}]
EOF
}

resource "aws_ecs_service" "service" {
  depends_on                         = ["null_resource.lb_exists"]
  name                               = "${var.name_prefix}"
  cluster                            = "${var.cluster_id}"
  task_definition                    = "${aws_ecs_task_definition.task.arn}"
  desired_count                      = "${var.task_container_desired_count}"
  launch_type                        = "FARGATE"
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = ["${var.private_subnet_ids}"]
    security_groups  = ["${aws_security_group.ecs_service.id}"]
    assign_public_ip = "${var.task_container_assign_public_ip}"
  }

  load_balancer {
    container_name   = "${var.name_prefix}"
    container_port   = "${var.task_container_port}"
    target_group_arn = "${aws_lb_target_group.task.arn}"
  }
}

# HACK: The workaround used in ecs/service does not work for some reason in this module, this fixes the following error:
# "The target group with targetGroupArn arn:aws:elasticloadbalancing:... does not have an associated load balancer."
# see https://github.com/hashicorp/terraform/issues/12634.
# Service depends on this resources which prevents it from being created until the LB is ready
resource "null_resource" "lb_exists" {
  triggers {
    alb_name = "${var.lb_arn}"
  }
}

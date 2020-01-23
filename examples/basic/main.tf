# ----------------------------------------
# Create a ecs service using fargate
# ----------------------------------------
terraform {
  required_version = ">= 0.12"
}

provider "aws" {
  version = ">= 2.17"
  region  = var.region
}

data "aws_vpc" "main" {
  default = true
}

data "aws_subnet_ids" "main" {
  vpc_id = data.aws_vpc.main.id
}


module "fargate_alb" {
  source  = "telia-oss/loadbalancer/aws"
  version = "3.0.0"

  name_prefix = var.name_prefix
  type        = "application"
  internal    = false
  vpc_id      = data.aws_vpc.main.id
  subnet_ids  = data.aws_subnet_ids.main.ids

  tags = {
    environment = "dev"
    terraform   = "True"
  }
}

resource "aws_lb_listener" "alb" {
  load_balancer_arn = module.fargate_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = lookup(module.fargate.target_groups, 8000, "") # reference target group created by Fargate module
    type             = "forward"
  }
}

resource "aws_security_group_rule" "alb_ingress_80" {
  security_group_id = module.fargate_alb.security_group_id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

resource "aws_security_group_rule" "task_ingress_8000" {
  security_group_id        = module.fargate.service_sg_id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 8000
  to_port                  = 8000
  source_security_group_id = module.fargate_alb.security_group_id
}

resource "aws_ecs_cluster" "cluster" {
  name = "${var.name_prefix}-cluster"
}

module "fargate" {
  source = "../../"

  name_prefix          = var.name_prefix
  vpc_id               = data.aws_vpc.main.id
  private_subnet_ids   = data.aws_subnet_ids.main.ids
  lb_arn               = module.fargate_alb.arn
  cluster_id           = aws_ecs_cluster.cluster.id
  task_container_image = "crccheck/hello-world:latest"

  // public ip is needed for default vpc, default is false
  task_container_assign_public_ip = true

  # Specify configration map for port, protocol used by targe group and container with health check on it
  task_container_port_protocol = {
    "8000" = {
      containerPort        = 8000
      hostPort             = 8000
      protocol             = "HTTP"
      health_check_path    = "/"
      health_check_matcher = "200"
      health_check_timeout = 4
      healthy_threshold    = 2
      unhealthy_threshold  = 2
      interval             = 5
    },
  }

  task_container_environment = {
    TEST_VARIABLE = "TEST_VALUE"
  }

  tags = {
    environment = "dev"
    terraform   = "True"
  }
}


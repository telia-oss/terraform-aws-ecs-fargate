# ----------------------------------------
# Create a ecs service using fargate
# ----------------------------------------
terraform {
  required_version = ">= 0.12"
}

provider "aws" {

  region = var.region
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
    target_group_arn = module.fargate.target_group_arn
    type             = "forward"
  }
}

resource "aws_security_group_rule" "task_ingress_8000" {
  security_group_id        = module.fargate.service_sg_id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 8000
  to_port                  = 8000
  source_security_group_id = module.fargate_alb.security_group_id
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

resource "aws_ecs_cluster" "cluster" {
  name = "${var.name_prefix}-cluster"
}

resource "aws_secretsmanager_secret" "task_container_secrets" {
  name       = var.name_prefix
  kms_key_id = var.task_container_secrets_kms_key
}

resource "aws_secretsmanager_secret_version" "task_container_secrets" {
  secret_id     = aws_secretsmanager_secret.task_container_secrets.id
  secret_string = "Super secret and important string"
}

data "aws_secretsmanager_secret" "task_container_secrets" {
  arn = aws_secretsmanager_secret.task_container_secrets.arn
}

data "aws_kms_key" "task_container_secrets" {
  key_id = data.aws_secretsmanager_secret.task_container_secrets.kms_key_id
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

  // port, default protocol is HTTP
  task_container_port = 8000

  task_container_environment = {
    TEST_VARIABLE = "TEST_VALUE"
  }

  task_container_secrets_kms_key = data.aws_kms_key.task_container_secrets.key_id

  task_container_secrets = [
    {
      name      = "TASK_SECRET"
      valueFrom = aws_secretsmanager_secret_version.task_container_secrets.arn
    }
  ]

  health_check = {
    port = "traffic-port"
    path = "/"
  }

  tags = {
    environment = "dev"
    terraform   = "True"
  }
}

# ----------------------------------------
# Create a service fargate
# ----------------------------------------

provider "aws" {
  region = "eu-west-1"
}

resource "aws_ecs_cluster" "fargate_cluster" {
  name = "example-ecs-fargate-cluster"
}

data "aws_vpc" "main" {
  default = true
}

data "aws_subnet_ids" "main" {
  vpc_id = "${data.aws_vpc.main.id}"
}

module "fargate_alb" {
  source  = "telia-oss/loadbalancer/aws"
  version = "0.1.0"

  name_prefix = "example-ecs-fargate-cluster"
  type        = "application"
  internal    = "false"
  vpc_id      = "${data.aws_vpc.main.id}"
  subnet_ids  = ["${data.aws_subnet_ids.main.ids}"]

  tags {
    environment = "test"
    terraform   = "true"
  }
}

resource "aws_lb_listener" "fargate" {
  load_balancer_arn = "${module.fargate_alb.arn}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${module.fargate.target_group_arn}"
    type             = "forward"
  }
}

resource "aws_security_group_rule" "fargate_task_ingress_8000" {
  security_group_id        = "${module.fargate.service_sg_id}"
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = "8000"
  to_port                  = "8000"
  source_security_group_id = "${module.fargate_alb.security_group_id}"
}

resource "aws_security_group_rule" "fargate_alb_ingress_80" {
  security_group_id = "${module.fargate_alb.security_group_id}"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = "80"
  to_port           = "80"
  cidr_blocks       = ["0.0.0.0/0"]
}

module "fargate" {
  source = "../../"

  name_prefix           = "example-fargate-app"
  vpc_id                = "${data.aws_vpc.main.id}"
  private_subnet_ids    = "${data.aws_subnet_ids.main.ids}"
  cluster_id            = "${aws_ecs_cluster.fargate_cluster.id}"
  task_definition_image = "crccheck/hello-world:latest"

  // public ip is needed for default vpc, default is false
  task_container_assign_public_ip = "true"

  // port, default protocol is HTTP
  task_container_port = "8000"

  health_check {
    port = "traffic-port"
    path = "/"
  }

  tags {
    environment = "test"
    terraform   = "true"
  }

  lb_arn = "${module.fargate_alb.arn}"
}

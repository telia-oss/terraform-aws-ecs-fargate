// In case of extra target groups (extra_target_groups)

resource "aws_lb_target_group" "extra" {
  name        = "${var.name_prefix}-3000"
  port        = 3000 // extra port the Fargate service expose
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.main.id
  tags = {
    environment = "dev"
    terraform   = "True"
  }
}


resource "aws_lb_listener" "extra_listener" {
  load_balancer_arn = module.fargate_alb.arn
  port              = 9000 // The port alb listen to and, bind to the service port (3000)
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.extra.arn
    type             = "forward"
  }
}

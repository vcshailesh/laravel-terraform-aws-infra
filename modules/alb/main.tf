resource "aws_lb" "this" {
  name               = "laravel-alb"
  load_balancer_type = "application"
  subnets            = var.public_subnets
  security_groups    = [var.security_group_id]
}

resource "aws_lb_target_group" "this" {
  name        = "laravel-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/up"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }
}

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
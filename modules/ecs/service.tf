resource "aws_ecs_service" "laravel" {
  name            = "laravel-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.laravel.arn
  launch_type     = "FARGATE"
  desired_count   = 2

  network_configuration {
    subnets          = var.private_subnets
    assign_public_ip = false
    security_groups  = [var.security_group_id]
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "laravel-app"
    container_port   = 80
  }

  depends_on = [var.listener]
}
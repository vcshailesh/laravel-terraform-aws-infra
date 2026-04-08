resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/laravel"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "laravel" {
  family                   = "laravel-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = var.execution_role_arn
  task_role_arn      = var.task_role_arn

  container_definitions = jsonencode([
    {
      name  = "laravel-app"
      image = var.image_url

      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "APP_ENV"
          value = "local"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/laravel"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  depends_on = [aws_cloudwatch_log_group.ecs]
}
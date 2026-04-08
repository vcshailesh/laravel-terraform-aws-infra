variable "db_username" {}

variable "db_password" {
  sensitive = true
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "laravel/rds-credentials"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
  })
}
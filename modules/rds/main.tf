resource "aws_db_subnet_group" "this" {
  subnet_ids = var.private_subnets
}

resource "aws_db_instance" "this" {
  engine               = "mysql"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  username             = aws_secretsmanager_secret_version.db.secret_string.username
  password             = aws_secretsmanager_secret_version.db.secret_string.password
  db_subnet_group_name = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_sg]
  skip_final_snapshot  = true
}
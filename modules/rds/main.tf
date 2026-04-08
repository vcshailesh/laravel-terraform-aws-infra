resource "aws_db_subnet_group" "this" {
  name       = "laravel-db-subnet-group"
  subnet_ids = var.subnet_ids
}

resource "aws_db_instance" "this" {
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = var.db_name
  username               = var.username
  password               = var.password
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group]
  skip_final_snapshot    = true
}
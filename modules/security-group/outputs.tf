output "alb_sg" {
  value = aws_security_group.alb.id
}

output "app_sg" {
  value = aws_security_group.app.id
}

output "db_sg" {
  value = aws_security_group.db.id
}
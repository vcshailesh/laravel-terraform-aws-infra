output "alb_sg" {
  description = "Security group ID for the ALB"
  value       = aws_security_group.alb.id
}

output "app_sg" {
  description = "Security group ID for application containers"
  value       = aws_security_group.app.id
}

output "rds_sg" {
  description = "Security group ID for the RDS database"
  value       = aws_security_group.db.id
}

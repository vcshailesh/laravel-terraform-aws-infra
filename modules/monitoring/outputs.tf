output "ecs_cpu_alarm_arn" {
  description = "ARN of the ECS CPU high alarm"
  value       = aws_cloudwatch_metric_alarm.ecs_cpu_high.arn
}

output "ecs_memory_alarm_arn" {
  description = "ARN of the ECS memory high alarm"
  value       = aws_cloudwatch_metric_alarm.ecs_memory_high.arn
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  threshold           = 80
  period              = 60
  namespace           = "AWS/EC2"
  statistic           = "Average"
}
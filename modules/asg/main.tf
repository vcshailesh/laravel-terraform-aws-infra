resource "aws_launch_template" "this" {
  image_id      = "ami-0f5ee92e2d63afc18"
  instance_type = "t2.micro"

  user_data = base64encode(<<EOF
#!/bin/bash
yum install -y httpd
systemctl start httpd
echo "Hello from ASG" > /var/www/html/index.html
EOF
  )
}

resource "aws_autoscaling_group" "this" {
  desired_capacity = 2
  max_size         = 3
  min_size         = 1

  vpc_zone_identifier = var.private_subnets

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  target_group_arns = [var.target_group_arn]
}
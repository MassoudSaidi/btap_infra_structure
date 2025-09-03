# Configure the AWS Provider
provider "aws" {
  region = "ca-central-1"
}

# 1. VPC and Networking using a standard module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.0"

  name = local.names.vpc_name
  cidr = "10.0.0.0/16"

  azs             = ["ca-central-1a", "ca-central-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets  = ["10.0.101.0/24", "10.0.102.0/24"] # Add private subnets for ElastiCache

  enable_nat_gateway   = true # Enable NAT for outbound traffic from private subnets
  single_nat_gateway   = false # Use (true) a single NAT for cost-effectiveness in dev environments  

  enable_dns_hostnames = true
}

# 2. Security Groups

# 2.1 Security Group for the Application Load Balancer (ALB)
# Allows public web traffic (port 80) FROM THE INTERNET.
resource "aws_security_group" "alb_sg" {
  name        = local.names.alb_sg_name
  description = "Allow HTTP inbound traffic for ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    protocol    = "tcp"
    from_port   = 1
    to_port     = 65535
    cidr_blocks = ["0.0.0.0/0"] # CORRECT: Source is the internet
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 2.2 Security Group for the ECS instances
# Allows traffic ONLY from the Load Balancer's Security Group.
resource "aws_security_group" "ecs_sg" {
  name        = local.names.ecs_sg_name
  description = "Allow traffic from the ALB to the ECS instances"
  vpc_id      = module.vpc.vpc_id

  # Ingress from the ALB Security Group to any port
  ingress {
    from_port       = 1
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id] # CORRECT: Source is the other SG
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 2.3 Security Group for Redis (ElastiCache)
# Allows traffic ONLY from the ECS Security Group on the Redis port.
resource "aws_security_group" "redis_sg" {
  name        = "redis-sg"
  description = "Allow inbound traffic from ECS instances to Redis"
  vpc_id      = module.vpc.vpc_id # IMPORTANT: Use your module's VPC

  # Ingress from the ECS Security Group to the Redis port
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    # This is the key to secure communication!
    security_groups = [aws_security_group.ecs_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "redis-sg"
  }
}

# 3. ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = local.names.cluster_name
}

# 4. ECS Instance IAM Role
resource "aws_iam_role" "ecs_instance_role" {
  name = local.names.iam_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_role_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# This policy allows SSM to manage the instance
resource "aws_iam_role_policy_attachment" "ecs_ssm_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = local.names.iam_profile_name
  role = aws_iam_role.ecs_instance_role.name
}

# 5. ECS Optimized AMI (Using the stable Amazon Linux 2 SSM Parameter)
# We are temporarily switching to the AL2 path because the latest AL2023 AMI appears to be broken.
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

# 6. Launch Template and Auto Scaling Group
resource "aws_launch_template" "ecs_launch_template" {
  name_prefix   = local.names.launch_template_prefix
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  # image_id      = "ami-0030b5eb4495d8adc"
  instance_type = var.instance_type # Using the variable here

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ecs_sg.id]
  }
  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo ECS_CLUSTER=${aws_ecs_cluster.main.name} >> /etc/ecs/ecs.config
              EOF
  )
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "ecs_asg" {
  name_prefix         = local.names.asg_name_prefix
  desired_capacity    = 1
  max_size            = 2
  min_size            = 1
  vpc_zone_identifier = module.vpc.public_subnets

  launch_template {
    id      = aws_launch_template.ecs_launch_template.id
    version = "$Latest"
  }
  health_check_type         = "EC2"
  health_check_grace_period = 300

  # Prevents deployment deadlocks
  lifecycle {
    create_before_destroy = true
  }
}

# 7. ECS Capacity Provider
resource "aws_ecs_capacity_provider" "ecs_capacity_provider" {
  name = local.names.capacity_provider_name
  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.arn
    managed_scaling {
      status          = "ENABLED"
      target_capacity = 100
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "cluster_association" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = [aws_ecs_capacity_provider.ecs_capacity_provider.name]
  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.name
  }
}

# 8. Load Balancer, Target Group, and Listener
resource "aws_lb" "main" {
  name               = local.names.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = module.vpc.public_subnets
  idle_timeout = 300
}

resource "aws_lb_target_group" "app" {
  name        = local.names.target_group_name
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"    

  health_check {
    path = "/health" # Correct health check path
    protocol            = "HTTP"
    port                = "traffic-port" # Use the port the traffic is sent to
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30    
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# 8. --- ELASTICACHE RESOURCES ---

# A. ElastiCache Subnet Group
# This tells ElastiCache which private subnets it can live in.
resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "redis-subnet-group"
  # IMPORTANT: Use the private subnets from your VPC module
  subnet_ids = module.vpc.private_subnets
}

# B. ElastiCache Parameter Group (can be copied as-is)
resource "aws_elasticache_parameter_group" "redis7" {
  name   = "redis7-param-group"
  family = "redis7"
}

# C. The ElastiCache Redis Cluster Itself
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "redis-prod-cluster"
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  # Reference the resources created above
  parameter_group_name = aws_elasticache_parameter_group.redis7.name
  subnet_group_name    = aws_elasticache_subnet_group.redis_subnet_group.name
  security_group_ids   = [aws_security_group.redis_sg.id]
}

# 9. CLOUDWATCH LOG GROUP
# Creates a centralized log group for our ECS service's containers.
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/ecs/${local.names.service_name}"
  retention_in_days = 30 # Keep logs for 30 days. Adjust as needed.

  tags = {
    Name = "${local.names.service_name}-logs"
  }
}

# 10. ECS Task Definition
resource "aws_ecs_task_definition" "app" {
  family                   = local.names.task_family
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = tostring(var.task_cpu)   # Use the variable and convert to string
  memory                   = tostring(var.task_memory) 

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "docker.io/massoudsaidi/massoud_btap_1:v3.0.1" # Specific, correct image
      # image     = "docker.io/massoudsaidi/surrogate_model_1:v3.0.3"
      essential = true
      portMappings = [{
        containerPort = 8000
        hostPort      = 8000
        protocol      = "tcp"
      }]
      # --- CLOUDWATCH LOG GROUP ---
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = var.aws_region # Assumes you have an aws_region variable
          "awslogs-stream-prefix" = "ecs"
        }
      }
      # --- END ADD ---

      # --- ADD THIS ENVIRONMENT VARIABLE BLOCK ---
      environment = [
        {
          name  = "REDIS_ENDPOINT"
          value = aws_elasticache_cluster.redis.cache_nodes[0].address
        },
        {
          name = "REDIS_PORT"
          value = "6379"
        }
      ]
      # --- END ADD ---      
    }
  ])
  
  # This tells Terraform: "Do not try to change the container_definitions
  # even if the live version in AWS is different from the code."
  # Ignores definition revision made by CI/CD pipeline.
  # --- TEMPORARILY COMMENT THIS OUT TO APPLY THE ANY IMPORTANT CHNAGES LIKE MEMORY CHANGE --- important when: terraform taint aws_ecs_task_definition.app
  lifecycle {
    ignore_changes = [
      container_definitions,
    ]
  }  
}

# 11. ECS Service
resource "aws_ecs_service" "app_service" {
  name            = local.names.service_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1

  # This tells the service to use the capacity provider
  # that is managed by  ASG.
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.name
    base              = 1
    weight            = 100
  }  

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = 8000
  }

  # Prevents deployment deadlocks
  depends_on = [
    aws_ecs_task_definition.app,
    aws_lb_listener.http,
    aws_ecs_cluster_capacity_providers.cluster_association,
    # --- ADDED THIS DEPENDENCY to prevent race conditions where the ECS service tries to start before the cache is ready ---
    aws_elasticache_cluster.redis    
  ]

  # Ignores definition revision made by CI/CD pipeline.
  lifecycle {
    ignore_changes = [
      task_definition,
      #   create_before_destroy = true # Prevents deployment deadlocks  
    ]
  }  
}

# 12. CLOUDWATCH ALARMS

# Alarm for high CPU utilization on the ECS Service
resource "aws_cloudwatch_metric_alarm" "ecs_high_cpu" {
  alarm_name          = "${local.names.service_name}-high-cpu"
  alarm_description   = "This alarm triggers if the ECS service CPU utilization is above 80% for 5 minutes."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300" # 5 minutes
  statistic           = "Average"
  threshold           = "80"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app_service.name
  }

  # In a real setup, you would add alarm_actions to an SNS topic ARN
  # replace 123456789012 with your actual AWS account ID
  # alarm_actions = ["arn:aws:sns:ca-central-1:123456789012:MyAlertsTopic"]
}

# 13. Alarm for a high number of 5xx errors from the ALB
resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  alarm_name          = "${local.names.alb_name}-5xx-errors"
  alarm_description   = "This alarm triggers if there are more than 10 5xx errors in a 5 minute period."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }
}

# 14. Alarm for high memory utilization on the ECS Service
resource "aws_cloudwatch_metric_alarm" "ecs_high_memory" {
  alarm_name          = "${local.names.service_name}-high-memory"
  alarm_description   = "This alarm triggers if the ECS service memory utilization is above 85% for 5 minutes."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "MemoryUtilization" # The key change is here
  namespace           = "AWS/ECS"
  period              = "300" # 5 minutes
  statistic           = "Average"
  threshold           = "85" # A good starting threshold for memory

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app_service.name
  }

  # In a real setup, you would add alarm_actions to an SNS topic ARN
  # alarm_actions = ["arn:aws:sns:ca-central-1:123456789012:MyAlertsTopic"]
}

# 15. CLOUDWATCH DASHBOARD
resource "aws_cloudwatch_dashboard" "main_dashboard" {
  dashboard_name = "${local.base_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # Widget 1: ECS CPU & Memory
      {
        type   = "metric",
        x      = 0,
        y      = 0,
        width  = 12,
        height = 6,
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.app_service.name],
            [".", "MemoryUtilization", ".", ".", ".", "."]
          ],
          period = 300,
          stat   = "Average",
          region = var.aws_region,
          title  = "ECS Service CPU & Memory Utilization"
        }
      },
      # Widget 2: ALB Requests & 5xx Errors
      {
        type   = "metric",
        x      = 12,
        y      = 0,
        width  = 12,
        height = 6,
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix],
            [".", "HTTPCode_Target_5XX_Count", ".", ".", { "stat": "Sum" }]
          ],
          period = 300,
          stat   = "Sum",
          region = var.aws_region,
          title  = "ALB Requests & 5xx Errors"
        }
      },
      # Widget 3: Container Logs
      {
        type   = "log",
        x      = 0,
        y      = 7,
        width  = 24,
        height = 6,
        properties = {
          region = var.aws_region,
          title  = "ECS Container Logs",
          #query  = "SOURCE '${aws_cloudwatch_log_group.app_logs.name}' | fields @timestamp, @message | sort @timestamp desc | limit 20"
          query = "SOURCE '${aws_cloudwatch_log_group.app_logs.name}' | fields @timestamp, @message | filter @message not like /GET \\/health/ and @message not like /ELB-HealthChecker/ | sort @timestamp desc | limit 200"
        }
      }
    ]
  })
}


# Add this new policy resource
resource "aws_iam_policy" "ecs_cloudwatch_logs_policy" {
  name        = "${local.base_name}-ecs-logs-policy"
  description = "Allows ECS instances to write to CloudWatch Logs"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*" # You can restrict this to the log group ARN for more security
      }
    ]
  })
}

# Now, attach this policy to your existing instance role
resource "aws_iam_role_policy_attachment" "ecs_logs_policy_attachment" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = aws_iam_policy.ecs_cloudwatch_logs_policy.arn
}

# Outputs
# This will print the public URL of your application after 'terraform apply' completes.
output "application_url" {
  description = "The URL of the deployed application"
  value       = "http://${aws_lb.main.dns_name}"
}

# Output for the ECS Cluster Name
output "ecs_cluster_name" {
  description = "The name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

# Output for the ECS Service Name
output "ecs_service_name" {
  description = "The name of the ECS service"
  value       = aws_ecs_service.app_service.name
}

# Output for the ECS Task Definition Family
output "ecs_task_definition_family" {
  description = "The family of the ECS task definition"
  value       = aws_ecs_task_definition.app.family
}
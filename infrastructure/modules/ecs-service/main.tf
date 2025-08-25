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

# 5. ECS Optimized AMI
data "aws_ami" "ecs_ami" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

# 6. Launch Template and Auto Scaling Group
resource "aws_launch_template" "ecs_launch_template" {
  name_prefix   = local.names.launch_template_prefix
  image_id      = data.aws_ami.ecs_ami.id
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

# 10. ECS Task Definition
resource "aws_ecs_task_definition" "app" {
  family                   = local.names.task_family
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = "256"
  memory                   = "2048"

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



# 12. Outputs
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
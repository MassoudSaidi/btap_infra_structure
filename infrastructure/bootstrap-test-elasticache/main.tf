# # Save jump host private key locally
# resource "local_file" "jump_key_file" {
#   content  = tls_private_key.jump_key.private_key_pem
#   filename = "${path.module}/jump-key.pem"
#   file_permission = "0400"
# }

# # TLS key for EC2 jump host
# resource "tls_private_key" "jump_key" {
#   algorithm = "RSA"
#   rsa_bits  = 4096
# }

# AWS key pair for EC2
resource "aws_key_pair" "jump_key" {
  key_name   = "jump-key"
  # public_key = tls_private_key.jump_key.public_key_openssh
  public_key = file("${path.module}/jump-key.pub") # Reads the .pub file
}

# Jump Host EC2 Instance
resource "aws_instance" "jump_host" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t3.micro"
  subnet_id              = aws_default_subnet.default_subnet.id
  vpc_security_group_ids = [aws_security_group.jump_sg.id]
  key_name               = aws_key_pair.jump_key.key_name
  associate_public_ip_address = true
  tags = {
    Name = "jump-host"
  }
}

# Default subnet (no hardcoded subnet resource needed)
resource "aws_default_subnet" "default_subnet" {
  availability_zone = data.aws_availability_zones.available.names[0]
}

# Security group for jump host
resource "aws_security_group" "jump_sg" {
  name        = "jump-sg"
  description = "Allow SSH"
  vpc_id      = aws_default_vpc.default_vpc.id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    # cidr_blocks = ["${chomp(data.http.my_ip.response_body)}/32"] check your public IP address by visiting a site like https://checkip.amazonaws.com/ in your web browser.
    # cidr_blocks = ["138.68.87.10/32"]  
    cidr_blocks = ["0.0.0.0/0"]  
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Default VPC
resource "aws_default_vpc" "default_vpc" {}

# Get my public IP
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com/"
}

# Get available AZs
data "aws_availability_zones" "available" {}

# Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}


# Get the default VPC
data "aws_vpc" "default" {
  default = true
}

# Security Group for Redis
resource "aws_security_group" "redis_sg" {
  name        = "redis-sg"
  description = "Allow access to Redis from the jump host"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.jump_sg.id] # allow jump host SG
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




resource "aws_elasticache_parameter_group" "redis7" {
  name   = "redis7-param-group"
  family = "redis7"
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "redis-dev-cluster"
  engine               = "redis"
  engine_version       = "7.0" # Ensure this matches a supported version
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = aws_elasticache_parameter_group.redis7.name
  subnet_group_name    = aws_elasticache_subnet_group.redis_subnet_group.name
  security_group_ids   = [aws_security_group.redis_sg.id]
}

# ElastiCache subnet group
resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "redis-subnet-group"
  subnet_ids = [aws_default_subnet.default_subnet.id]
}

# Outputs

# output "ssh_tunnel_command_unix" {
#   value = "ssh -i ${local_file.jump_key_file.filename} -L 6379:${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379 ec2-user@${aws_instance.jump_host.public_ip}"
#   depends_on = [aws_elasticache_cluster.redis]
# }

# output "ssh_tunnel_command_win" {
#   value = "ssh.exe -i ${local_file.jump_key_file.filename} -L 6379:${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379 ec2-user@${aws_instance.jump_host.public_ip}"
#   depends_on = [aws_elasticache_cluster.redis]
# }

output "ssh_tunnel_command_unix" {
  # Note: The private key is now named "jump-key" not "jump-key.pem"
  value = "ssh -i ${path.module}/jump-key -L 6379:${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379 ec2-user@${aws_instance.jump_host.public_ip}"
  depends_on = [aws_elasticache_cluster.redis]
}

output "ssh_tunnel_command_win" {
  # Note: The private key is now named "jump-key" not "jump-key.pem"
  value = "ssh.exe -i ${path.module}/jump-key -L 6379:${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379 ec2-user@${aws_instance.jump_host.public_ip}"
  depends_on = [aws_elasticache_cluster.redis]
}


# Output the public IP of the jump host
output "jump_host_public_ip" {
  value = aws_instance.jump_host.public_ip
}

# Output the SSH key name used for the jump host
output "jump_host_key_name" {
  value = aws_instance.jump_host.key_name
}

# Output the Security Group ID
output "jump_host_security_group_id" {
  value = aws_security_group.jump_sg.id
}

# Output Security Group inbound rules for SSH
data "aws_security_group" "jump_sg_details" {
  id = aws_security_group.jump_sg.id
}







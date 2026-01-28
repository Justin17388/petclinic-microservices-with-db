terraform {
  required_version = ">= 1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

############################
# Variables
############################
variable "env" {
  description = "Environment name (dev/qa/prod)"
  type        = string
  default     = "dev"
}

variable "build_id" {
  description = "Unique build identifier (ex: Jenkins BUILD_NUMBER)"
  type        = string
  default     = "0"
}

variable "key_name" {
  description = "Existing EC2 key pair name to use for instances"
  type        = string
}

variable "sec_gr_base_name" {
  description = "Base name for the k8s security group"
  type        = string
  default     = "petclinic-k8s-sec-group"
}

############################
# Data
############################
data "aws_vpc" "default" {
  default = true
}

############################
# Security Group (unique per build)
############################
locals {
  sec_gr_name = "${var.sec_gr_base_name}-${var.env}-b${var.build_id}"
}

resource "aws_security_group" "k8s_sec_gr" {
  name        = local.sec_gr_name
  description = "Kubernetes SG for Petclinic QA automation"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name        = local.sec_gr_name
    Environment = var.env
    Build       = var.build_id
    Project     = "petclinic"
  }

  # Allow all within SG
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kubernetes API server
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NodePort range
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

############################
# IAM Role + Instance Profile
############################
resource "aws_iam_role" "petclinic_master_server_role" {
  name = "petclinic-master-server-role-${var.env}-b${var.build_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "petclinic_s3_policy" {
  role       = aws_iam_role.petclinic_master_server_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "petclinic_master_profile" {
  name = "petclinic-master-server-profile-${var.env}-b${var.build_id}"
  role = aws_iam_role.petclinic_master_server_role.name
}

############################
# EC2 Instances
############################
resource "aws_instance" "kube_master" {
  ami                    = "ami-005fc0f236362e99f"
  instance_type          = "t3a.medium"
  iam_instance_profile   = aws_iam_instance_profile.petclinic_master_profile.name
  vpc_security_group_ids = [aws_security_group.k8s_sec_gr.id]
  key_name               = var.key_name

  subnet_id         = "subnet-0eeff02a3066f919f" # us-east-1a
  availability_zone = "us-east-1a"

  tags = {
    Name        = "kube-master-${var.env}-b${var.build_id}"
    Project     = "tera-kube-ans"
    Role        = "master"
    Environment = var.env
    Build       = var.build_id
  }
}

resource "aws_instance" "worker_1" {
  ami                    = "ami-005fc0f236362e99f"
  instance_type          = "t3a.medium"
  vpc_security_group_ids = [aws_security_group.k8s_sec_gr.id]
  key_name               = var.key_name

  subnet_id         = "subnet-0c763511f23d056d7" # us-east-1b
  availability_zone = "us-east-1b"

  tags = {
    Name        = "worker-1-${var.env}-b${var.build_id}"
    Project     = "tera-kube-ans"
    Role        = "worker"
    Environment = var.env
    Build       = var.build_id
  }
}

resource "aws_instance" "worker_2" {
  ami                    = "ami-005fc0f236362e99f"
  instance_type          = "t3a.medium"
  vpc_security_group_ids = [aws_security_group.k8s_sec_gr.id]
  key_name               = var.key_name

  subnet_id         = "subnet-07a6ef077ac2bf1d5" # us-east-1c
  availability_zone = "us-east-1c"

  tags = {
    Name        = "worker-2-${var.env}-b${var.build_id}"
    Project     = "tera-kube-ans"
    Role        = "worker"
    Environment = var.env
    Build       = var.build_id
  }
}

############################
# Outputs
############################
output "kube_master_ip" {
  value       = aws_instance.kube_master.public_ip
  description = "Public IP of the kube-master"
}

output "worker_1_ip" {
  value       = aws_instance.worker_1.public_ip
  description = "Public IP of worker-1"
}

output "worker_2_ip" {
  value       = aws_instance.worker_2.public_ip
  description = "Public IP of worker-2"
}

#############################################
# main.tf — rewritten (Jenkins-friendly)
#############################################

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # Optional (recommended): add an S3 backend later so Jenkins runs share state.
  # backend "s3" {
  #   bucket         = "YOUR-TF-STATE-BUCKET"
  #   key            = "petclinic/${var.env}/k8s/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "YOUR-TF-LOCK-TABLE"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = "us-east-1"
}

#############################################
# Variables
#############################################

variable "env" {
  type        = string
  description = "Environment name (dev/qa/prod)."
  default     = "dev"
}

variable "build_id" {
  type        = string
  description = "Unique build identifier (use Jenkins BUILD_NUMBER or a timestamp)."
  default     = "manual"
}

variable "sec_gr_k8s" {
  type        = string
  description = "Base name for the Kubernetes security group."
  default     = "petclinic-k8s-sec-group"
}

variable "key_name" {
  type        = string
  description = "Existing EC2 key pair name to use for instances."
  default     = "clarus"
}

variable "master_subnet_id" {
  type        = string
  description = "Subnet ID for kube-master."
  default     = "subnet-0eeff02a3066f919f"
}

variable "worker1_subnet_id" {
  type        = string
  description = "Subnet ID for worker-1."
  default     = "subnet-0c763511f23d056d7"
}

variable "worker2_subnet_id" {
  type        = string
  description = "Subnet ID for worker-2."
  default     = "subnet-07a6ef077ac2bf1d5"
}

variable "master_az" {
  type        = string
  description = "Availability Zone for kube-master."
  default     = "us-east-1a"
}

variable "worker1_az" {
  type        = string
  description = "Availability Zone for worker-1."
  default     = "us-east-1b"
}

variable "worker2_az" {
  type        = string
  description = "Availability Zone for worker-2."
  default     = "us-east-1c"
}

variable "ami_id" {
  type        = string
  description = "AMI to use for all nodes."
  default     = "ami-005fc0f236362e99f"
}

variable "instance_type" {
  type        = string
  description = "Instance type for all nodes."
  default     = "t3a.medium"
}

#############################################
# Data sources
#############################################

data "aws_vpc" "default" {
  default = true
}

#############################################
# Security Group (unique per build)
#############################################

resource "aws_security_group" "k8s_sec_gr" {
  name        = "${var.sec_gr_k8s}-${var.env}-${var.build_id}"
  description = "Kubernetes nodes SG for ${var.env} build ${var.build_id}"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name        = "${var.sec_gr_k8s}-${var.env}-${var.build_id}"
    Environment = var.env
    BuildId     = var.build_id
    Project     = "petclinic"
  }

  # node-to-node communication
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # SSH (open to world for lab; tighten to your IP when ready)
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

  # outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#############################################
# IAM Role + Instance Profile for kube-master
#############################################

resource "aws_iam_role" "petclinic_master_server_role" {
  name = "petclinic-master-server-role-${var.env}-${var.build_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.env
    BuildId     = var.build_id
    Project     = "petclinic"
  }
}

resource "aws_iam_role_policy_attachment" "petclinic_s3_readonly" {
  role       = aws_iam_role.petclinic_master_server_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "petclinic_master_profile" {
  name = "petclinic-master-server-profile-${var.env}-${var.build_id}"
  role = aws_iam_role.petclinic_master_server_role.name

  tags = {
    Environment = var.env
    BuildId     = var.build_id
    Project     = "petclinic"
  }
}

#############################################
# EC2 Instances
#############################################

resource "aws_instance" "kube_master" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.petclinic_master_profile.name
  vpc_security_group_ids = [aws_security_group.k8s_sec_gr.id]
  key_name               = var.key_name

  subnet_id         = var.master_subnet_id
  availability_zone = var.master_az

  tags = {
    Name        = "kube-master-${var.env}-${var.build_id}"
    Project     = "tera-kube-ans"
    Role        = "master"
    Id          = "1"
    Environment = var.env
    BuildId     = var.build_id
  }
}

resource "aws_instance" "worker_1" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.k8s_sec_gr.id]
  key_name               = var.key_name

  subnet_id         = var.worker1_subnet_id
  availability_zone = var.worker1_az

  tags = {
    Name        = "worker-1-${var.env}-${var.build_id}"
    Project     = "tera-kube-ans"
    Role        = "worker"
    Id          = "1"
    Environment = var.env
    BuildId     = var.build_id
  }
}

resource "aws_instance" "worker_2" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.k8s_sec_gr.id]
  key_name               = var.key_name

  subnet_id         = var.worker2_subnet_id
  availability_zone = var.worker2_az

  tags = {
    Name        = "worker-2-${var.env}-${var.build_id}"
    Project     = "tera-kube-ans"
    Role        = "worker"
    Id          = "2"
    Environment = var.env
    BuildId     = var.build_id
  }
}

#############################################
# Outputs
#############################################

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

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Get the script runner's public IP for SSH access
data "http" "runner_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  runner_cidr = "${trimspace(data.http.runner_ip.response_body)}/32"
}

# Use default VPC and subnets
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Ubuntu 24.04 LTS AMI (x86_64 for c8i - Intel)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Generate SSH key pair for the instance
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "ssh_private_key_pem" {
  content         = tls_private_key.ec2_key.private_key_pem
  filename        = "ec2-benchmark-key.pem"
  file_permission = "0600"
}

resource "aws_key_pair" "ec2_key" {
  key_name   = "ec2-benchmark-key"
  public_key = tls_private_key.ec2_key.public_key_openssh
}

# ---------------------------------------------------------------------------
# S3 bucket: http-input-benchmark-<random suffix>, versioning disabled
# ---------------------------------------------------------------------------

resource "random_id" "bucket_suffix" {
  byte_length = 8
}

resource "aws_s3_bucket" "benchmark" {
  bucket = "http-input-benchmark-${random_id.bucket_suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "benchmark" {
  bucket = aws_s3_bucket.benchmark.id

  versioning_configuration {
    status = "Suspended"
  }
}

# ---------------------------------------------------------------------------
# EC2 IAM role: full access to the benchmark bucket, assigned to instance
# ---------------------------------------------------------------------------

resource "aws_iam_role" "ec2_benchmark" {
  name = "ec2-benchmark-role"

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
}

resource "aws_iam_role_policy" "ec2_benchmark_s3" {
  name   = "benchmark-bucket-full-access"
  role   = aws_iam_role.ec2_benchmark.id
  policy = data.aws_iam_policy_document.ec2_benchmark_s3.json
}

data "aws_iam_policy_document" "ec2_benchmark_s3" {
  statement {
    sid    = "FullAccessToBenchmarkBucket"
    effect = "Allow"
    actions = [
      "s3:*"
    ]
    resources = [
      aws_s3_bucket.benchmark.arn,
      "${aws_s3_bucket.benchmark.arn}/*"
    ]
  }
}

resource "aws_iam_instance_profile" "ec2_benchmark" {
  name = "ec2-benchmark-instance-profile"
  role = aws_iam_role.ec2_benchmark.name
}

# ---------------------------------------------------------------------------
# IAM user with access key: full access to the benchmark bucket
# ---------------------------------------------------------------------------

resource "aws_iam_user" "benchmark_s3" {
  name = "benchmark-s3-user"
}

resource "aws_iam_user_policy" "benchmark_s3" {
  name   = "benchmark-bucket-full-access"
  user   = aws_iam_user.benchmark_s3.name
  policy = data.aws_iam_policy_document.benchmark_s3_user.json
}

data "aws_iam_policy_document" "benchmark_s3_user" {
  statement {
    sid    = "FullAccessToBenchmarkBucket"
    effect = "Allow"
    actions = [
      "s3:*"
    ]
    resources = [
      aws_s3_bucket.benchmark.arn,
      "${aws_s3_bucket.benchmark.arn}/*"
    ]
  }
}

resource "aws_iam_access_key" "benchmark_s3" {
  user = aws_iam_user.benchmark_s3.name
}


resource "local_file" "benchmark_s3_user_credentials" {
  content         = jsonencode({
    id = aws_iam_access_key.benchmark_s3.id
    secret = aws_iam_access_key.benchmark_s3.secret
  })
  filename        = "benchmark_s3_user_credentials.txt"
  file_permission = "0600"
}

# ---------------------------------------------------------------------------
# Security group: SSH only from script runner IP
# ---------------------------------------------------------------------------

resource "aws_security_group" "ec2_sg" {
  name        = "ec2-benchmark-sg"
  description = "Allow SSH from script runner only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from script runner"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.runner_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 instance: c8i.2xlarge, 50 GB gp3, IAM role for S3 access
resource "aws_instance" "benchmark" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "c8i.2xlarge"
  key_name               = aws_key_pair.ec2_key.key_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id              = tolist(data.aws_subnets.default.ids)[0]
  associate_public_ip_address = true
  iam_instance_profile   = aws_iam_instance_profile.ec2_benchmark.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "benchmark-ec2"
  }

  connection {
    type = "ssh"
    host = self.public_ip
    user = "ubuntu"
    private_key = tls_private_key.ec2_key.private_key_pem
  }

  provisioner "remote-exec" {
    script = "../scripts/install_loadgen.sh"
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.benchmark.id
}

output "public_ip" {
  description = "Public IP for SSH"
  value       = aws_instance.benchmark.public_ip
}

output "s3_bucket_name" {
  description = "S3 bucket name (http-input-benchmark-<suffix>)"
  value       = aws_s3_bucket.benchmark.id
}

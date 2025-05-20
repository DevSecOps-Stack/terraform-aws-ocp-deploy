terraform {
  required_version = ">= 1.12.0, < 2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.44" # any recent 5.x
    }
  }
}

provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key # or leave blank & rely on env vars / profiles
  secret_key = var.aws_secret_key
}

################################################################################
# Key pair (one SSH key → EC2 *and* OpenShift)
################################################################################
resource "aws_key_pair" "installer_key" {
  key_name   = "ocp-installer-key"
  public_key = file(var.public_key_path)
}

################################################################################
# IAM role so the installer can create the cluster’s AWS resources
################################################################################
resource "aws_iam_role" "installer_role" {
  name = "ocp-installer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach_admin" {
  role       = aws_iam_role.installer_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "installer_profile" {
  name = "ocp-installer-profile"
  role = aws_iam_role.installer_role.name
}

################################################################################
# Security group – SSH only (adjust as you like)
################################################################################
resource "aws_security_group" "installer_sg" {
  name        = "ocp-installer-sg"
  description = "Allow SSH from anywhere"

  ingress {
    from_port   = 22
    to_port     = 22
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

################################################################################
# EC2 instance that runs the entire OpenShift installation
################################################################################
data "aws_ami" "amazon_linux" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"] # Amazon Linux 2023
  }
}

resource "aws_instance" "ocp_installer" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "m7i.large" # 8 vCPU / 32 GiB — installer likes RAM
  key_name                    = aws_key_pair.installer_key.key_name
  iam_instance_profile        = aws_iam_instance_profile.installer_profile.name
  vpc_security_group_ids      = [aws_security_group.installer_sg.id]
  associate_public_ip_address = true


  ### NEW: make root volume 40 GiB (or whatever you like)
  root_block_device {
    volume_size = var.root_volume_size   # <— use variable for flexibility
    volume_type = "gp3"
  }

  # cloud-init = run everything on first boot
  user_data = base64encode(
    templatefile("${path.module}/bootstrap.sh.tpl", {
      # ── placeholders used in the first five lines ────────────────
      region       = var.aws_region
      base_domain  = var.base_domain
      cluster_name = var.cluster_name
      ssh_pub_key  = file(var.public_key_path)
      pull_secret  = local.pull_secret


      # ── AWS creds for the installer ────────────────────
      aws_access_key = var.aws_access_key
      aws_secret_key = var.aws_secret_key

      # (Include these only if you did **not** escape $${…} inside the here-doc)
      REGION       = var.aws_region
      BASE_DOMAIN  = var.base_domain
      CLUSTER_NAME = var.cluster_name
      SSH_KEY      = file(var.public_key_path)
      PULL_SECRET  = local.pull_secret
    })
  )


  tags = { Name = "${var.cluster_name}-installer" }
}

output "ssh_to_instance" {
  value = "ssh ec2-user@${aws_instance.ocp_installer.public_ip} -i <your_private_key>"
}

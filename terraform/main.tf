terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "aipostex-lab"
      Environment = "lab"
      ManagedBy   = "terraform"
    }
  }
}

# ── Data Sources ────────────────────────────────────────────
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  # Ubuntu 24.04 (noble) to match the Proxmox lab OS — the provision scripts use
  # `pip install --break-system-packages` (PEP 668), which only exists on 24.04's
  # newer pip. On 22.04 (jammy) that flag errors and set -e kills the deploy.
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── SSH Key ─────────────────────────────────────────────────
resource "aws_key_pair" "lab" {
  key_name   = "${var.name_prefix}-key"
  public_key = file(var.ssh_public_key_path)
}

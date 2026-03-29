# ================================================================================
# FILE: main.tf
# ================================================================================
#
# Purpose:
#   Configure the AWS provider and resolve shared networking resources
#   created by 01-core via data sources.
#
# ================================================================================

provider "aws" {
  region = "us-east-1"
}


# ================================================================================
# SECTION: Data Sources
# ================================================================================

data "aws_vpc" "main" {
  tags = { Name = var.vpc_name }
}

data "aws_subnet" "vm1" {
  tags = { Name = var.subnet_name }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

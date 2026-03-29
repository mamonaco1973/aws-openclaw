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

provider "random" {}


# ================================================================================
# SECTION: Data Sources
# ================================================================================

data "aws_vpc" "main" {
  tags = { Name = var.vpc_name }
}

data "aws_subnet" "vm1" {
  tags = { Name = var.subnet_name }
}

data "aws_ami" "openclaw_mate" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["openclaw_mate_ami*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

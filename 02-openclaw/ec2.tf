# ================================================================================
# FILE: ec2.tf
# ================================================================================
#
# Purpose:
#   Security group and EC2 instance for the OpenClaw host.
#
# Design:
#   - No inbound rules — SSM Session Manager requires no open ports.
#   - All outbound allowed for package installs, Docker pulls, and Bedrock API calls.
#   - IMDSv2 hop limit set to 2 so Docker containers can reach instance credentials.
#
# ================================================================================


# ================================================================================
# SECTION: Security Group
# ================================================================================

resource "aws_security_group" "openclaw" {
  name        = "openclaw-sg"
  description = "OpenClaw host - no inbound, all outbound"
  vpc_id      = data.aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "openclaw-sg" }
}


# ================================================================================
# SECTION: EC2 Instance
# ================================================================================

resource "aws_instance" "openclaw" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnet.vm1.id
  iam_instance_profile   = aws_iam_instance_profile.openclaw.name
  vpc_security_group_ids = [aws_security_group.openclaw.id]

  user_data = templatefile("${path.module}/scripts/userdata.sh", {
    bedrock_model_id = var.bedrock_model_id
  })

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  # Hop limit of 2 allows Docker containers to reach IMDSv2 for Bedrock credentials.
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    http_endpoint               = "enabled"
  }

  tags = { Name = "openclaw-host" }
}

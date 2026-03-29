# ================================================================================
# FILE: ec2.tf
# ================================================================================
#
# Purpose:
#   Security group and EC2 instance for the OpenClaw host.
#
# Design:
#   - No inbound rules — access via SSM Session Manager and RDP (no open ports).
#   - All outbound allowed for Bedrock API calls and package updates.
#   - AMI resolved from self-owned "openclaw_mate_ami" (built by 02-packer).
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
  ami                    = data.aws_ami.openclaw_mate.id
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

  metadata_options {
    http_tokens   = "optional"
    http_endpoint = "enabled"
  }

  tags = { Name = "openclaw-host" }
}

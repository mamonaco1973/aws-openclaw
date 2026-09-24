# ================================================================================
# FILE: ec2.tf
# ================================================================================
#
# Purpose:
#   Security group and EC2 instance for the OpenClaw host.
#
# Design:
#   - Port 3389 open for direct RDP access during testing.
#   - All outbound allowed for Bedrock API calls and package updates.
#   - AMI resolved from self-owned "openclaw_ami" (built by 02-packer).
#
# ================================================================================


# ================================================================================
# SECTION: Security Group
# ================================================================================

resource "aws_security_group" "openclaw" {
  name        = "openclaw-sg"
  description = "OpenClaw host - RDP inbound, all outbound"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description = "RDP"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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
  ami                         = data.aws_ami.openclaw.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnet.vm1.id
  iam_instance_profile        = aws_iam_instance_profile.openclaw.name
  vpc_security_group_ids      = [aws_security_group.openclaw.id]
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/scripts/userdata.sh", {
    # The raw list drives the LiteLLM model_list via a %{ for } loop in the
    # template. models_b64 is the same data pre-encoded for the OpenClaw CLI:
    # base64 so it drops into the shell script as one opaque token. Raw JSON
    # interpolated into bash breaks the moment a display name contains an
    # apostrophe; base64 is alphanumeric plus +/= so no quoting case exists.
    models = var.models
    models_b64 = base64encode(jsonencode([
      for m in var.models : { id = m.alias, name = m.display }
    ]))

    primary_alias  = var.primary_alias
    bedrock_region = var.bedrock_region
  })

  root_block_device {
    volume_size = 128
    volume_type = "gp3"
  }

  metadata_options {
    http_tokens   = "optional"
    http_endpoint = "enabled"
  }

  tags = { Name = "openclaw-host" }
}

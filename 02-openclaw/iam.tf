# ================================================================================
# FILE: iam.tf
# ================================================================================
#
# Purpose:
#   IAM role and instance profile granting the OpenClaw EC2 instance
#   access to SSM Session Manager (no SSH keys required).
#
# ================================================================================

resource "aws_iam_role" "openclaw" {
  name = "openclaw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.openclaw.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "openclaw" {
  name = "openclaw-profile"
  role = aws_iam_role.openclaw.name
}

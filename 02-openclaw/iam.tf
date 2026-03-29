# ================================================================================
# FILE: iam.tf
# ================================================================================
#
# Purpose:
#   IAM role and instance profile granting the OpenClaw EC2 instance
#   access to SSM Session Manager (no SSH keys required) and Bedrock
#   model invocation for LiteLLM proxy.
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

resource "aws_iam_role_policy" "bedrock" {
  name = "openclaw-bedrock"
  role = aws_iam_role.openclaw.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ]
      Resource = "arn:aws:bedrock:*::foundation-model/*"
    }]
  })
}

resource "aws_iam_instance_profile" "openclaw" {
  name = "openclaw-profile"
  role = aws_iam_role.openclaw.name
}

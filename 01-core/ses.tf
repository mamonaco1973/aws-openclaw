# ================================================================================
# FILE: ses.tf
# ================================================================================
#
# Purpose:
#   Creates SES email identity and SMTP credentials for outbound email.
#
# Post-deploy step:
#   AWS will send a verification email to var.ses_email. Click the link to
#   activate sending. Until verified, SES will reject outbound messages.
#
# Optional:
#   Everything here is skipped when var.ses_email is blank. The instance
#   treats a missing openclaw_ses_smtp secret as "no email" and boots
#   without msmtp (see 03-openclaw/scripts/userdata.sh).
#
# ================================================================================


locals {
  ses_enabled = var.ses_email != ""
}

# These resources were unconditional before ses_email became optional. The
# moved blocks carry existing state over to index [0] so an upgrade does not
# destroy and recreate the identity (which would re-send verification) or
# rotate the SMTP credentials.
moved {
  from = aws_ses_email_identity.sender
  to   = aws_ses_email_identity.sender[0]
}

moved {
  from = aws_iam_user.ses_smtp
  to   = aws_iam_user.ses_smtp[0]
}

moved {
  from = aws_iam_user_policy.ses_smtp
  to   = aws_iam_user_policy.ses_smtp[0]
}

moved {
  from = aws_iam_access_key.ses_smtp
  to   = aws_iam_access_key.ses_smtp[0]
}

moved {
  from = aws_secretsmanager_secret.ses_smtp
  to   = aws_secretsmanager_secret.ses_smtp[0]
}

moved {
  from = aws_secretsmanager_secret_version.ses_smtp
  to   = aws_secretsmanager_secret_version.ses_smtp[0]
}


# ================================================================================
# SECTION: Email Identity
# ================================================================================

resource "aws_ses_email_identity" "sender" {
  count = local.ses_enabled ? 1 : 0
  email = var.ses_email
}


# ================================================================================
# SECTION: SMTP Credentials
# ================================================================================

resource "aws_iam_user" "ses_smtp" {
  count = local.ses_enabled ? 1 : 0
  name  = "openclaw-ses-smtp"
  tags  = { Name = "openclaw-ses-smtp" }
}

resource "aws_iam_user_policy" "ses_smtp" {
  count = local.ses_enabled ? 1 : 0
  name  = "openclaw-ses-send"
  user  = aws_iam_user.ses_smtp[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ses:SendRawEmail"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_access_key" "ses_smtp" {
  count = local.ses_enabled ? 1 : 0
  user  = aws_iam_user.ses_smtp[0].name
}


# ================================================================================
# SECTION: SMTP Secret
# ================================================================================

resource "aws_secretsmanager_secret" "ses_smtp" {
  count                   = local.ses_enabled ? 1 : 0
  name                    = "openclaw_ses_smtp"
  description             = "SES SMTP credentials for OpenClaw outbound email sending"
  recovery_window_in_days = 0
  tags                    = { Name = "openclaw-ses-smtp" }
}

resource "aws_secretsmanager_secret_version" "ses_smtp" {
  count     = local.ses_enabled ? 1 : 0
  secret_id = aws_secretsmanager_secret.ses_smtp[0].id
  secret_string = jsonencode({
    smtp_host     = "email-smtp.us-east-1.amazonaws.com"
    smtp_port     = "587"
    smtp_username = aws_iam_access_key.ses_smtp[0].id
    smtp_password = aws_iam_access_key.ses_smtp[0].ses_smtp_password_v4
    from_email    = var.ses_email
  })
}

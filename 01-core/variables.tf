# ================================================================================
# SECTION: VPC Naming
# ================================================================================

# Name assigned to the VPC resource created for this environment.
variable "vpc_name" {
  description = "Name for the VPC resource"
  type        = string
  default     = "clawd-vpc"
}

# --------------------------------------------------------------------------------
# SES outbound email (optional)
# --------------------------------------------------------------------------------
# Blank (the default) skips SES entirely: no email identity, no SMTP user, no
# openclaw_ses_smtp secret, and the agent has no outbound email.
#
# To enable email, put the sender address in the default below and redeploy:
#
#     default     = "you@example.com"
#
# AWS sends a verification email to that address. Click the link in it --
# until you do, SES rejects every send. In a new AWS account SES is also in
# sandbox mode, where recipients must be verified too.
#
# To turn email off again, set the default back to "" and re-run apply.sh;
# Terraform removes the SES resources.
variable "ses_email" {
  description = "Email address to verify in SES for outbound sending (blank = no SES, no outbound email)"
  type        = string
  default     = ""

  validation {
    condition     = var.ses_email == "" || can(regex("^[^@\\s]+@[^@\\s]+$", var.ses_email))
    error_message = "ses_email must be blank or a single email address."
  }
}

# ================================================================================
# SECTION: VPC Naming
# ================================================================================

# Name assigned to the VPC resource created for this environment.
variable "vpc_name" {
  description = "Name for the VPC resource"
  type        = string
  default     = "clawd-vpc"
}

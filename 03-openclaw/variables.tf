# ================================================================================
# SECTION: Networking
# ================================================================================

variable "vpc_name" {
  description = "Name tag of the VPC created by 01-core"
  type        = string
  default     = "clawd-vpc"
}

variable "subnet_name" {
  description = "Name tag of the subnet to place the OpenClaw host in"
  type        = string
  default     = "pub-subnet-1"
}


# ================================================================================
# SECTION: Instance
# ================================================================================

variable "instance_type" {
  description = "EC2 instance type for the OpenClaw host"
  type        = string
  default     = "t3.xlarge"
}

variable "bedrock_model_id" {
  description = "Bedrock foundation model ID passed to the LiteLLM proxy"
  type        = string
  default     = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
}

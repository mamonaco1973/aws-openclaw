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


# ================================================================================
# SECTION: AI Models (Bedrock)
# ================================================================================

# Populated from bedrock-config.sh via TF_VAR_models. The defaults here are a
# fallback for a bare `terraform apply` and are kept in step with that file --
# apply.sh always exports over them.
variable "models" {
  description = "Bedrock models LiteLLM serves to OpenClaw (from bedrock-config.sh)"

  type = list(object({
    # What LiteLLM routes on and what OpenClaw stores as the model id. Stable
    # across Bedrock id changes, which is the point of having an alias.
    alias = string

    # The Bedrock model id, normally a "us." inference profile.
    model = string

    # Shown in the OpenClaw model picker.
    display = string
  }))

  default = [
    {
      alias   = "claude-sonnet"
      model   = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
      display = "Claude Sonnet (Bedrock)"
    },
    {
      alias   = "claude-haiku"
      model   = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
      display = "Claude Haiku (Bedrock)"
    },
  ]

  validation {
    condition     = length(var.models) > 0
    error_message = "At least one model must be defined in bedrock-config.sh."
  }

  validation {
    condition     = length(distinct([for m in var.models : m.alias])) == length(var.models)
    error_message = "Model aliases must be unique - LiteLLM routes on the alias."
  }
}

variable "primary_alias" {
  description = "Alias from var.models that agents default to"
  type        = string
  default     = "claude-sonnet"

  # Cross-variable validation (Terraform >= 1.9). A primary that is not in the
  # list produces an OpenClaw that starts fine and cannot run an agent, which
  # is a far worse failure than a plan-time error.
  validation {
    condition     = contains([for m in var.models : m.alias], var.primary_alias)
    error_message = "primary_alias must be one of the aliases in var.models."
  }
}

variable "bedrock_region" {
  description = "Region LiteLLM calls Bedrock in (must match what check_env.sh probed)"
  type        = string
  default     = "us-east-1"
}

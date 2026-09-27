# ================================================================================
# FILE: networking.tf
# ================================================================================
#
# Purpose:
#   Baseline networking for the OpenClaw environment:
#     - VPC with DNS support and hostnames enabled
#     - One public subnet holding the Packer builder and the OpenClaw host
#     - Internet Gateway, one route table, one association
#
# Notes:
#   - One subnet is the whole requirement. This project runs a single EC2
#     instance that must be reachable inbound on 3389, so it belongs in a
#     public subnet with an IGW default route. Private subnets and a NAT
#     gateway would add cost and deploy time for nothing to sit in.
#   - Inbound RDP needs the IGW route, not just a public IP: an instance whose
#     default route is a NAT gateway can reach out but cannot be reached, so
#     the reply leaves from the NAT address and the connection never forms.
#   - VPC CIDR: 10.0.0.0/23, region: us-east-1
#
# ================================================================================


# ================================================================================
# SECTION: VPC
# ================================================================================

# VPC with DNS support and hostnames enabled for EC2 instance name resolution.
resource "aws_vpc" "clawd-vpc" {
  cidr_block           = "10.0.0.0/23"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.vpc_name }
}


# ================================================================================
# SECTION: Internet Gateway
# ================================================================================

# Both directions run through here: the agent's outbound calls to Bedrock and
# SES, and the inbound RDP session.
resource "aws_internet_gateway" "clawd-igw" {
  vpc_id = aws_vpc.clawd-vpc.id
  tags   = { Name = "clawd-igw" }
}


# ================================================================================
# SECTION: Subnet
# ================================================================================

# The Packer builder needs inbound SSH during the build and the OpenClaw host
# needs inbound RDP after it, so both live here. A /24 inside the /23 leaves
# room to add a second subnet later without renumbering this one.
resource "aws_subnet" "pub-subnet" {
  vpc_id                  = aws_vpc.clawd-vpc.id
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true
  availability_zone_id    = "use1-az4"

  tags = { Name = "pub-subnet" }
}


# ================================================================================
# SECTION: Route Table and Association
# ================================================================================

# Default route to the Internet Gateway. Without this association the instance
# still receives a public IP and still cannot be reached on it.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.clawd-vpc.id
  tags   = { Name = "public-route-table" }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.clawd-igw.id
}

resource "aws_route_table_association" "pub_subnet" {
  subnet_id      = aws_subnet.pub-subnet.id
  route_table_id = aws_route_table.public.id
}

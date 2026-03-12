#
# main.tf
#

# Fetch the latest Amazon Linux 2 AMI ID

data "aws_ami" "latest_amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Prompts BEGIN

variable "ami" {
  description = "Amazon Machine Image ID for EC2 instance. us-west-2: ami-0786adace1541ca80 | eu-west-3: ami-0446057e5961dfab6"
  type        = string
  
  # For west MUST use t2.micro ami-0786adace1541ca80.  West cannot have t3.micro  
  default     = "ami-0786adace1541ca80"               # AWS Linux 2 Free Tier Eligible - us-west-2
} 

variable "owner" {
  description = "tag resource with owner"
  type        = string
  default     = "ericm"
} 

# Target Region
variable "region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "us-west-2"
}

# Prompts END


variable "ssh_pubkey" {
  description = "SSH public key for creating tunnel"
  type        = string

  # Eric MAC:
  #default      = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEfQoBYa+YTFJ5ijh3iBTKjD/zg2/M13QQbYpEV0SV2A"

  # GPU-JumpBox:
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOKjqORmfRZYOVUnp6K/SdCbryfYkJgb2+1dn6urAUUP" 
} 

#
# This helps ensure the key pair exists in the correct region before instance creation
#

data "aws_key_pair" "existing_key" {
  key_name = "aws-keypair-1" # Replace with your actual key pair name
}

resource "aws_instance" "ec2_instance" {
  ami           = "${var.ami}"
  instance_type = "t2.micro"
  subnet_id     = "${data.aws_subnets.default_public_subnet.ids[0]}"
  vpc_security_group_ids = [aws_security_group.nkp_tunnel.id]

  # Old
  #key_name      = aws_key_pair.ssh_key.key_name

  # Associate the existing key pair by name
  key_name      = data.aws_key_pair.existing_key.key_name
  
  user_data     = file("cloud-init-config.yaml")

  tags = {
    Name = "ubu-nkp-tunnel-em1"
    owner = "${var.owner}"
    createdBy = "${var.owner}"
  }
}

# Security Group 
resource "aws_security_group" "nkp_tunnel" {
  name        = "nkp_tunnel_sg"
  description = "Allow communication between HPOC and tunnel"
  vpc_id      = "${data.aws_vpc.default_vpc.id}"

  tags = {
    owner = "${var.owner}"
    createdBy = "${var.owner}"
  }
}

# AWS Networking Stuff (VPC, Ingress, etc)

resource "aws_vpc_security_group_ingress_rule" "nkp_tunnel_ssh" {

  security_group_id = aws_security_group.nkp_tunnel.id

  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"

  prefix_list_id    = "${aws_ec2_managed_prefix_list.nutanix_networks.id}"






  # not allowed here..
  #cidr_blocks       = var.allowed_subnet_cidrs # Using the list here  
  # wants string for this only..
  #cidr_ipv4          = var.allowed_subnet_cidrs
  #cidr_ipv4         = "10.38.48.0/24,10.55.41.0/24,10.42.164.0/24,192.146.155.0/24"
  #cidr_ipv4          = "0.0.0.0/0"

}

resource "aws_vpc_security_group_ingress_rule" "nkp_tunnel_https" {

  security_group_id = aws_security_group.nkp_tunnel.id

  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "nkp_tunnel_egress_all" {
  
  security_group_id = aws_security_group.nkp_tunnel.id

  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

data "aws_vpc" "default_vpc" {
  default = true
}

data "aws_subnets" "default_public_subnet" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default_vpc.id]
  }
}

/*
resource "aws_key_pair" "ssh_key" {
  key_name   = "terraform-key"
  public_key = "${var.ssh_pubkey}"
}
*/

resource "aws_ec2_managed_prefix_list" "nutanix_networks" {
  name           = "Nutanix"
  address_family = "IPv4"
  max_entries    = 6

  entry {
    cidr        = "18.237.140.160/29"
    description = "aws-us-west-2-connect"
  }

  entry {
    cidr        = "192.146.154.0/24"
    description = "hpoc-x"
  }

  entry {
    cidr        = "10.42.164.0/24"
    description = "ntx-vpn"
  }

  entry {
    cidr        = "192.146.155.0/24"
    description = "isp-starlink"
  }

  tags = {
    owner = "${var.owner}"
    createdBy = "${var.owner}"
  }
}

output tunnel_public_ip {
  value = aws_instance.ec2_instance.public_ip
}



#
# main.tf
#

# Target Region
variable "region" {
  description = "AWS region to deploy resources in"
  type        = string
  # default   = "us-west"
}

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

# Prompts

variable "ami" {
  description = "Amazon Machine Image ID for EC2 instance. us-west-2: ami-027951e78de46a00e | eu-west-3: ami-0446057e5961dfab6"
  type        = string
  # default   = "ami-027951e78de46a00e"  # AWS Linux 2 Free Tier Eligible - us-west-2
} 

variable "owner" {
  description = "tag resource with owner"
  type        = string
} 


variable "ssh_pubkey" {
  description = "SSH public key for creating tunnel"
  type        = string

  # Eric MAC:
  #default      = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEfQoBYa+YTFJ5ijh3iBTKjD/zg2/M13QQbYpEV0SV2A"

  # GPU-JumpBox:
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOKjqORmfRZYOVUnp6K/SdCbryfYkJgb2+1dn6urAUUP" 
} 


resource "aws_instance" "ec2_instance" {
  ami           = "${var.ami}"
  instance_type = "t2.micro"
  subnet_id     = "${data.aws_subnets.default_public_subnet.ids[0]}"
  vpc_security_group_ids = [aws_security_group.nkp_tunnel.id]

  key_name      = aws_key_pair.ssh_key.key_name

  user_data = <<-__EOF__
              #!/bin/bash
              echo "GatewayPorts yes" >> /etc/ssh/sshd_config
              systemctl restart sshd
              yum install -y socat

              # Create systemd service for socat
              cat <<EOT > /etc/systemd/system/socat.service
              [Unit]
              Description=Socat Port Forwarding 443 -> 8443
              After=network.target

              [Service]
              ExecStart=/usr/bin/socat TCP-LISTEN:443,reuseaddr,fork TCP:127.0.0.1:8443
              Restart=always
              User=root

              [Install]
              WantedBy=multi-user.target
              EOT
              
              # Reload systemd, enable and start socat service
              systemctl daemon-reload
              systemctl enable socat.service
              systemctl start socat.service
              curl -Lo /usr/local/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
              chmod +x /usr/local/bin/kubectl
              __EOF__
  
  tags = {
    Name = "centos-nkp-tunnel"
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

  from_port       = 22
  to_port         = 22
  ip_protocol     = "tcp"
  prefix_list_id  = "${aws_ec2_managed_prefix_list.nutanix_networks.id}"
}

resource "aws_vpc_security_group_ingress_rule" "nkp_tunnel_https" {
  security_group_id = aws_security_group.nkp_tunnel.id

  from_port       = 443
  to_port         = 443
  ip_protocol     = "tcp"
  cidr_ipv4 = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "nkp_tunnel_egress_all" {
  security_group_id = aws_security_group.nkp_tunnel.id

  ip_protocol    = "-1"
  cidr_ipv4 = "0.0.0.0/0"
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

resource "aws_key_pair" "ssh_key" {
  key_name   = "terraform-key"
  public_key = "${var.ssh_pubkey}"
}

resource "aws_ec2_managed_prefix_list" "nutanix_networks" {
  name           = "Nutanix"
  address_family = "IPv4"
  max_entries    = 3

  entry {
    cidr        = "10.38.48.0/24"
    description = "hpoc"
  }

  /*
  entry {
    cidr        = "192.146.155.0/24"
    description = "hpoc"
  }
  */

  tags = {
    owner = "${var.owner}"
    createdBy = "${var.owner}"
  }
}

output tunnel_public_ip {
  value = aws_instance.ec2_instance.public_ip
}



#
# Base provider.tf   us-west-2
#

provider "aws" {
  region = "us-west-2" # Replace with your desired AWS region
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}



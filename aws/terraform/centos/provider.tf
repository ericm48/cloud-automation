#
# provider.tf
#

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider with your desired region
provider "aws" {
  region = "us-west"
}
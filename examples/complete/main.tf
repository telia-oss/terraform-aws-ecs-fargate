terraform {
  required_version = ">= 0.12"
}

provider "aws" {
  version = ">= 2.27"
  region  = var.region
}

module "template" {
  source      = "../../"
  name_prefix = var.name_prefix

  tags = {
    environment = "dev"
    terraform   = "True"
  }
}

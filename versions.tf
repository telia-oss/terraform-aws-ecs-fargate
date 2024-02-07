terraform {
  required_version = "~> 1.0"

  required_providers {
    aws = {
      version = ">= 3.69.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.1.0"
    }
  }
}

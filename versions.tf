terraform {
  required_version = ">= 0.14"

  required_providers {
    aws = {
      version = ">= 3.35.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.1.0"
    }
  }
}

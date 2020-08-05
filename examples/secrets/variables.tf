variable "name_prefix" {
  type    = string
  default = "fargate-task-secrets-example"
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "task_container_secrets_kms_key" {
  type        = string
  description = ""
  default     = "alias/aws/secretsmanager"
}

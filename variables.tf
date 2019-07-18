# ------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------
variable "name_prefix" {
  description = "A prefix used for naming resources."
}

variable "container_name" {
  description = "Optional name for the container to be used instead of name_prefix. Useful when when constructing an imagedefinitons.json file for continuous deployment using Codepipeline."
  default     = ""
}

variable "vpc_id" {
  description = "The VPC ID."
}

variable "private_subnet_ids" {
  description = "A list of private subnets inside the VPC"
  type        = "list"
}

variable "cluster_id" {
  description = "The Amazon Resource Name (ARN) that identifies the cluster."
}

variable "task_container_image" {
  description = "The image used to start a container."
}

variable "lb_arn" {
  description = "Arn for the LB for which the service should be attach to."
}

variable "desired_count" {
  description = "The number of instances of the task definitions to place and keep running."
  default     = "1"
}

variable "service_ignore_changes" {
  description = "Allow external changes to parameters without Terraform plan difference. i.e. desired_count updated by autoscaler."
  type        = "list"
  default     = []
}

variable "task_container_assign_public_ip" {
  description = "Assigned public IP to the container."
  default     = "false"
}

variable "task_container_port" {
  description = "Port that the container exposes."
}

variable "task_container_protocol" {
  description = "Protocol that the container exposes."
  default     = "HTTP"
}

variable "task_definition_cpu" {
  description = "Amount of CPU to reserve for the task."
  default     = "256"
}

variable "task_definition_memory" {
  description = "The soft limit (in MiB) of memory to reserve for the container."
  default     = "512"
}

variable "task_container_command" {
  description = "The command that is passed to the container."
  default     = []
}

variable "task_container_environment" {
  description = "The environment variables to pass to a container."
  default     = {}
}

variable "task_container_environment_count" {
  description = "NOTE: This exists purely to calculate count in Terraform. Should equal the length of your environment map."
  default     = "0"
}

variable "log_retention_in_days" {
  description = "Number of days the logs will be retained in CloudWatch."
  default     = "30"
}

variable "health_check" {
  description = "A health block containing health check settings for the target group. Overrides the defaults."
  type        = "map"
}

variable "health_check_grace_period_seconds" {
  default     = "300"
  description = "Seconds to ignore failing load balancer health checks on newly instantiated tasks to prevent premature shutdown, up to 7200. Only valid for services configured to use load balancers."
}

variable "tags" {
  description = "A map of tags (key-value pairs) passed to resources."
  type        = "map"
  default     = {}
}

variable "deployment_minimum_healthy_percent" {
  default     = "50"
  description = "The lower limit of the number of running tasks that must remain running and healthy in a service during a deployment"
}

variable "deployment_maximum_percent" {
  default     = "200"
  description = "The upper limit of the number of running tasks that can be running in a service during a deployment"
}

variable "deployment_controller_type" {
  default     = "ECS"
  type        = "string"
  description = "Type of deployment controller. Valid values: CODE_DEPLOY, ECS."
}

# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/private-auth.html
variable "repository_credentials" {
  default     = ""
  description = "name or ARN of a secrets manager secret (arn:aws:secretsmanager:region:aws_account_id:secret:secret_name)"
}

variable "repository_credentials_kms_key" {
  default     = "alias/aws/secretsmanager"
  description = "key id, key ARN, alias name or alias ARN of the key that encrypted the repository credentials"
}

locals {
  # if the variable is set, create the fragment based on the variable value
  # if not, just return a empty string to not mess up the json
  repository_credentials_fragment = <<EOF
        "repositoryCredentials": {
            "credentialsParameter": "${var.repository_credentials}"
        },
EOF

  repository_credentials_rendered = "${var.repository_credentials == "" ? "" : local.repository_credentials_fragment}"
}

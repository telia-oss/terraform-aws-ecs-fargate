# ------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------
variable "name_prefix" {
  description = "A prefix used for naming resources."
  type        = string
}

variable "container_name" {
  description = "Optional name for the container to be used instead of name_prefix. Useful when when constructing an imagedefinitons.json file for continuous deployment using Codepipeline."
  default     = ""
  type        = string
}

variable "task_container_secrets" {
  description = "See https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-ecs-taskdefinition-secret.html . Beware: Only Secrets Manager secrets supported. The necessary permissions will be added automatically."
  type        = list(object({ name = string, valueFrom = string }))
  default     = []
}

variable "task_container_secrets_kms_key" {
  type        = string
  description = ""
  default     = "alias/aws/secretsmanager"
}

variable "vpc_id" {
  description = "The VPC ID."
  type        = string
}

variable "private_subnet_ids" {
  description = "A list of private subnets inside the VPC"
  type        = list(string)
}

variable "cluster_id" {
  description = "The Amazon Resource Name (ARN) that identifies the cluster."
  type        = string
}

variable "task_container_image" {
  description = "The image used to start a container."
  type        = string
}

variable "lb_arn" {
  default     = ""
  description = "Arn for the LB for which the service should be attach to."
  type        = string
}

variable "desired_count" {
  description = "The number of instances of the task definitions to place and keep running."
  default     = 1
  type        = number
}

variable "task_container_assign_public_ip" {
  description = "Assigned public IP to the container."
  default     = false
  type        = bool
}

variable "task_container_port" {
  description = "Port that the container exposes."
  type        = number
}

variable "task_container_protocol" {
  description = "Protocol that the container exposes."
  default     = "HTTP"
  type        = string
}

variable "task_definition_cpu" {
  description = "Amount of CPU to reserve for the task."
  default     = 256
  type        = number
}

variable "task_definition_memory" {
  description = "The soft limit (in MiB) of memory to reserve for the container."
  default     = 512
  type        = number
}

variable "task_container_command" {
  description = "The command that is passed to the container."
  default     = []
  type        = list(string)
}

variable "task_container_environment" {
  description = "The environment variables to pass to a container."
  default     = {}
  type        = map(string)
}

variable "log_retention_in_days" {
  description = "Number of days the logs will be retained in CloudWatch."
  default     = 30
  type        = number
}

variable "health_check" {
  description = "A health block containing health check settings for the target group. Overrides the defaults."
  type        = map(string)
}

variable "health_check_grace_period_seconds" {
  default     = 300
  description = "Seconds to ignore failing load balancer health checks on newly instantiated tasks to prevent premature shutdown, up to 7200. Only valid for services configured to use load balancers."
  type        = number
}

variable "tags" {
  description = "A map of tags (key-value pairs) passed to resources."
  type        = map(string)
  default     = {}
}

variable "deployment_minimum_healthy_percent" {
  default     = 50
  description = "The lower limit of the number of running tasks that must remain running and healthy in a service during a deployment"
  type        = number
}

variable "deployment_maximum_percent" {
  default     = 200
  description = "The upper limit of the number of running tasks that can be running in a service during a deployment"
  type        = number
}

variable "deployment_controller_type" {
  default     = "ECS"
  type        = string
  description = "Type of deployment controller. Valid values: CODE_DEPLOY, ECS."
}

# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/private-auth.html
variable "repository_credentials" {
  default     = ""
  description = "name or ARN of a secrets manager secret (arn:aws:secretsmanager:region:aws_account_id:secret:secret_name)"
  type        = string
}

variable "repository_credentials_kms_key" {
  default     = "alias/aws/secretsmanager"
  description = "key id, key ARN, alias name or alias ARN of the key that encrypted the repository credentials"
  type        = string
}

variable "service_registry_arn" {
  default     = ""
  description = "ARN of aws_service_discovery_service resource"
  type        = string
}

variable "with_service_discovery_srv_record" {
  default     = true
  type        = bool
  description = "Set to false if you specify a SRV DNS record in aws_service_discovery_service. If only A record, set this to false."
}

variable "stop_timeout" {
  description = "Time duration (in seconds) to wait before the container is forcefully killed if it doesn't exit normally on its own. On Fargate the maximum value is 120 seconds."
  default     = 30
}

variable "task_role_permissions_boundary_arn" {
  description = "ARN of the policy that is used to set the permissions boundary for the task (and task execution) role."
  default     = ""
  type        = string
}

variable "protocol_version" {
  description = "The protocol (HTTP) version."
  default     = "HTTP1"
  type        = string
}

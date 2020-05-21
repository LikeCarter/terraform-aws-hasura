# -----------------------------------------------------------------------------
# ENVIRONMENT VARIABLES
# Define these secrets as environment variables
# -----------------------------------------------------------------------------

# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY

# -----------------------------------------------------------------------------
# PARAMETERS
# -----------------------------------------------------------------------------

variable "region" {
  description = "Region to deploy"
  default     = "us-east-1" # Asia Pacific Tokyo
}

variable "domain" {
  description = "Domain name. Service will be deployed using the okatee_subdomain"
}

variable "okatee_subdomain" {
  description = "The Subdomain for your okatee graphql service."
  default     = "okatee"
}

variable "app_subdomain" {
  description = "The Subdomain for your application that will make CORS requests to the okatee_subdomain"
  default     = "app"
}
variable "docker_image" {
  description = "The docker image and version tag to deploy on ECS"
}

variable "cidr_block" {
  description = "The Subdomain for your application that will make CORS requests to the okatee_subdomain"
  default     = "172.18.0.0/16"
}

variable "container_memory" {
  description = "Task memory"
  default     = "1024"
}

variable "container_cpu" {
  description = "Task CPU"
  default     = "512"
}




variable "container_port" {
  description = "Container mapped port"
  default     = 8000
}

variable "host_port" {
  description = "Host mapped port"
  default     = 8000
}



variable "az_count" {
  description = "How many AZ's to create in the VPC"
  default     = 2
}

variable "multi_az" {
  description = "Whether to deploy RDS and ECS in multi AZ mode or not"
  default     = true
}

variable "vpc_enable_dns_hostnames" {
  description = "A boolean flag to enable/disable DNS hostnames in the VPC. Defaults false."
  default     = false
}

variable "environment" {
  description = "Environment variables for ECS task: [ { name = \"foo\", value = \"bar\" }, ..]"
  default     = []
}

variable "additional_db_security_groups" {
  description = "List of Security Group IDs to have access to the RDS instance"
  default     = []
}

variable "create_iam_service_linked_role" {
  description = "Whether to create IAM service linked role for AWS ElasticSearch service. Can be only one per AWS account."
  default     = true
}

variable "ecs_cluster_name" {
  description = "The name to assign to the ECS cluster"
  default     = "okatee-cluster"
}

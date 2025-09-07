# --- Required Variables (from shared dev.tfvars) ---
variable "gcp_project_id" {
  description = "The Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "The Google Cloud region"
  type        = string
}

variable "zone" {
  description = "The Google Cloud zone for the VM"
  type        = string
}

variable "username" {
  description = "Username for resource naming"
  type        = string
}

variable "resource_prefix" {
  description = "Resource prefix for consistent naming"
  type        = string
}

# --- Network Variables (from shared dev.tfvars) ---
variable "vpc_name" {
  description = "Name of the VPC network (from step 01)"
  type        = string
}

variable "subnet_name" {
  description = "Name of the subnet (from step 01)"
  type        = string
}

variable "psc_subnet_cidr" {
  description = "CIDR range for the dedicated PSC subnet (from dev.tfvars)"
  type        = string
}

# --- Health Check Variables ---
variable "health_check_path" {
  description = "Path for HTTPS health check"
  type        = string
  default     = "/"
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 10
}

# --- Backend Service Variables ---
variable "backend_timeout" {
  description = "Backend service timeout in seconds"
  type        = number
  default     = 30
}

# --- PSC Service Attachment Variables ---
variable "connection_preference" {
  description = "PSC connection preference (ACCEPT_AUTOMATIC or ACCEPT_MANUAL)"
  type        = string
  default     = "ACCEPT_AUTOMATIC"
}

variable "accepted_projects" {
  description = "List of accepted project IDs/numbers for manual acceptance (optional)"
  type        = list(string)
  default     = null
}

variable "connection_limit" {
  description = "Maximum number of PSC connections allowed per accepted project"
  type        = number
  default     = 10
}
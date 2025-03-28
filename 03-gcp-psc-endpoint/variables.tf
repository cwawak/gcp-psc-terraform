# variables.tf - Defines input variables for the 03-gcp-psc-endpoint configuration.

variable "gcp_project_id" {
  description = "GCP Project ID where the PSC endpoint resources will be created."
  type        = string
}

variable "region" {
  description = "GCP region for the PSC endpoint and related IP address reservation."
  type        = string
}

variable "resource_prefix" {
  description = "A short string used as part of the resource naming convention (e.g., 'gcppsctest')."
  type        = string
}

variable "username" {
  description = "A short identifier (e.g., your username) used in resource naming conventions."
  type        = string
}

# --- Variables populated by outputs from previous steps (Manual Workflow) ---
# In a refactored setup using remote state, these would likely be replaced
# by 'terraform_remote_state' data source lookups.

variable "vpc_name" {
  description = "The name of the VPC Network (output from Step 01) where the endpoint will reside. Used by data source lookup."
  type        = string
}

variable "subnet_name" {
  description = "The name of the Subnet (output from Step 01) where the endpoint will reside. Used by data source lookup."
  type        = string
}

variable "gcp_service_attachment_uri" {
  description = "The Service Attachment URI provided by Confluent Cloud (output from Step 02). This is the target for the PSC endpoint."
  type        = string
}
# --- End of Manual Workflow Variables ---
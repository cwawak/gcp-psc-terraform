# variables.tf - Defines input variables for the 04-confluent-cluster configuration.

variable "resource_prefix" {
  description = "A short string used as part of the resource naming convention (e.g., 'gcppsctest')."
  type        = string
}

variable "username" {
  description = "A short identifier (e.g., your username) used in resource naming conventions."
  type        = string
}

variable "confluent_network_cloud" {
  description = "The cloud provider identifier where the cluster runs (e.g., 'GCP')."
  type        = string
  # Default removed - specify in .tfvars file.
}

variable "region" {
  description = "The cloud provider region where the cluster runs (e.g., 'us-central1')."
  type        = string
}

variable "confluent_environment_id" {
  description = "The ID of the Confluent Cloud Environment where the cluster will be created."
  type        = string
}

variable "cluster_cku" {
  description = "The number of Confluent Kafka Units (CKUs) for the Dedicated cluster. Determines capacity and cost."
  type        = number
  # Default removed - specify in .tfvars file.
}


# --- Variables populated by outputs from previous steps (Manual Workflow) ---
# In a refactored setup using remote state, these would likely be replaced
# by 'terraform_remote_state' data source lookups.

variable "confluent_network_id" {
  description = "The Confluent Cloud Network ID (output from Step 02) where the cluster will be created."
  type        = string
}

variable "confluent_network_dns_domain" {
  description = "The private DNS domain associated with the Confluent Network (output from Step 02). Used here for an informational output."
  type        = string
}
# --- End of Manual Workflow Variables ---

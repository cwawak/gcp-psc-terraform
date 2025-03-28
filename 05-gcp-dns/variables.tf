# variables.tf - Defines input variables for the 05-gcp-dns configuration.

variable "gcp_project_id" {
  description = "GCP Project ID where the DNS zone and records will be created."
  type        = string
}

variable "region" {
  description = "GCP region (used for provider context, though DNS can be complex)."
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

variable "dns_ttl" {
  description = "TTL (Time-To-Live) in seconds for the DNS records created (e.g., 60)."
  type        = number
  default     = 60
}


# --- Variables populated by outputs from previous steps (Manual Workflow) ---
# In a refactored setup using remote state, these would likely be replaced
# by 'terraform_remote_state' data source lookups.

variable "vpc_name" {
  description = "The name of the VPC Network (output from Step 01) to associate the private DNS zone with. Used by data source lookup."
  type        = string
}

variable "psc_forwarding_rule_ip" {
  description = "The internal IP address of the PSC endpoint (output from Step 03). This is the target IP for the DNS 'A' record."
  type        = string
}

variable "confluent_network_dns_domain" {
  description = "The private DNS domain provided by Confluent Cloud (output from Step 02). This defines the zone's DNS name."
  type        = string
}
# --- End of Manual Workflow Variables ---
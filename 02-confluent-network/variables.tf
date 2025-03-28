# variables.tf - Defines input variables for the 02-confluent-network configuration.

variable "gcp_project_id" {
  description = "The GCP Project ID that will be authorized to connect to the Confluent Network via Private Link Access."
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

variable "region" {
  description = "The primary GCP region where associated GCP resources exist (used for consistency, Confluent network region is set separately)."
  type        = string
}

variable "confluent_environment_id" {
  description = "The ID of the Confluent Cloud Environment where the network will be created (e.g., 'env-xxxxxx')."
  type        = string
  # Default removed - specify in .tfvars file.
}

variable "confluent_network_region" {
  description = "The cloud region where the Confluent Network will be created (e.g., 'us-central1'). Should match the GCP 'region'."
  type        = string
  # Default removed - specify in .tfvars file.
}

variable "confluent_network_cloud" {
  description = "The cloud provider for the Confluent Network. Must be set to 'GCP' for this setup."
  type        = string
  # Default removed - specify in .tfvars file.
}

variable "network_zones" {
  description = "A list of exactly three availability zones within the 'confluent_network_region' required for GCP PSC networks (e.g., ['us-central1-a', 'us-central1-b', 'us-central1-c'])."
  type        = list(string)
  # Validation could be added here to ensure list length is 3.
}
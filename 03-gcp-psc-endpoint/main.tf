# --- Terraform and Provider Configuration ---
# Standard provider setup for Google Cloud.

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0" # Align with version used in Step 1
    }
  }
  # Note: No backend is configured; using local state.
}

# Configure the Google Cloud provider.
provider "google" {
  project = var.gcp_project_id
  region  = var.region
}

# --- Locals for Consistent Naming ---
# Defines local variables for resource naming.
locals {
  psc_endpoint_full_name = "${var.username}-${var.resource_prefix}-psc-endpoint" # e.g., cwawak-gcppsctest-psc-endpoint
  psc_ip_full_name       = "${var.username}-${var.resource_prefix}-psc-ip"       # e.g., cwawak-gcppsctest-psc-ip
}

# --- Data Sources to find Network/Subnet IDs ---
# Use data sources to look up the VPC and Subnet created in Step 01 by their names.
# This avoids hardcoding IDs and retrieves current resource information.

data "google_compute_network" "vpc" {
  # Name is provided via 'var.vpc_name' (output from Step 01).
  name    = var.vpc_name
  project = var.gcp_project_id
}

data "google_compute_subnetwork" "subnet" {
  # Name is provided via 'var.subnet_name' (output from Step 01).
  name    = var.subnet_name
  region  = var.region
  project = var.gcp_project_id
}

# --- Resource Definitions ---

# 1. Reserve a Static Internal IP Address for the PSC Endpoint.
# Reserving the IP ensures that the entry point address for the private connection remains stable
# even if the forwarding rule is recreated. This is crucial for DNS configuration.
resource "google_compute_address" "psc_ip" {
  name         = local.psc_ip_full_name        # Name for the reserved IP address resource itself.
  project      = var.gcp_project_id
  region       = var.region
  # Associates the IP address reservation with our specific subnet.
  subnetwork   = data.google_compute_subnetwork.subnet.id
  # Specifies that this is an internal IP address within the VPC.
  address_type = "INTERNAL"
}

# 2. Create the PSC Forwarding Rule (Endpoint).
# This is the core GCP resource representing the Private Service Connect endpoint.
# It acts as the private entry point within your VPC that targets the Confluent Cloud service.
resource "google_compute_forwarding_rule" "psc_endpoint" {
  name    = local.psc_endpoint_full_name # Name for the forwarding rule resource.
  project = var.gcp_project_id
  region  = var.region

  # Specifies the target service attachment to connect to.
  # This URI is obtained from the Confluent Network output in Step 02.
  target = var.gcp_service_attachment_uri

  # Specifies the network and subnetwork where this PSC endpoint will reside.
  network    = data.google_compute_network.vpc.id
  subnetwork = data.google_compute_subnetwork.subnet.id

  # Assigns the static internal IP address reserved in the previous step to this endpoint.
  # Referencing the 'self_link' ensures dependency and uses the reserved IP.
  ip_address = google_compute_address.psc_ip.self_link

  # When the 'target' is a service attachment (for PSC), 'load_balancing_scheme' must be explicitly empty.
  load_balancing_scheme = ""

  # Ensures the static IP address resource is created before this forwarding rule attempts to use it.
  depends_on = [google_compute_address.psc_ip]
}

# --- Outputs ---
# Exposes information about the created PSC endpoint resources.

output "psc_forwarding_rule_name" {
  description = "The name of the created PSC Forwarding Rule."
  value       = google_compute_forwarding_rule.psc_endpoint.name
}

output "psc_forwarding_rule_ip" {
  description = "The static internal IP address allocated to the PSC endpoint. Needed for DNS configuration in Step 05."
  # Retrieve the actual IP address string from the 'google_compute_address' resource.
  value       = google_compute_address.psc_ip.address # e.g., 10.10.0.3
}

output "gcp_service_attachment_targeted" {
  description = "The Confluent Cloud Service Attachment URI targeted by this PSC endpoint."
  value       = google_compute_forwarding_rule.psc_endpoint.target
}
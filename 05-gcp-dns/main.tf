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
  # Region is required by the provider, though DNS zones can be global,
  # private zones are associated with networks which are regional/global.
  region  = var.region
}

# --- Locals for Consistent Naming ---
# Defines local variables for resource naming.
locals {
  dns_zone_name = "${var.username}-${var.resource_prefix}-private-zone" # e.g., cwawak-gcppsctest-private-zone
}

# --- Data Sources ---
# Look up the VPC Network created in Step 01 by its name.
# Needed to associate the private DNS zone with this VPC.
data "google_compute_network" "vpc" {
  # Name is provided via 'var.vpc_name' (output from Step 01).
  name    = var.vpc_name
  project = var.gcp_project_id
}

# --- Resource Definitions ---

# 1. Create Private Managed DNS Zone: Creates a DNS zone within GCP Cloud DNS
# that is only resolvable from within authorized VPC networks.
resource "google_dns_managed_zone" "private_zone" {
  name        = local.dns_zone_name # Name for the managed zone resource itself.
  project     = var.gcp_project_id
  # The DNS name for the zone. This MUST match the private domain provided by Confluent Cloud
  # (from Step 02 output) and requires a trailing dot.
  dns_name    = "${var.confluent_network_dns_domain}." # e.g., domdponq74g.us-central1.gcp.confluent.cloud.
  description = "Private DNS zone for resolving Confluent Cloud private endpoints via PSC"
  # Crucial: Makes the zone private and only visible to specified networks.
  visibility  = "private"

  # Configuration block specific to private zones.
  private_visibility_config {
    # List of networks that can resolve records in this zone.
    networks {
      # The URL of the VPC network that should have access to this private zone.
      network_url = data.google_compute_network.vpc.id # Associates with the VPC looked up earlier.
    }
  }
}

# 2. Create Wildcard A Record Set: Creates a DNS Address (A) record within the private zone.
# This record maps hostnames to an IP address.
resource "google_dns_record_set" "wildcard_a" {
  # The hostname for the record. Using "*.domain." creates a wildcard record.
  # This ensures that ANY hostname within the Confluent private domain (e.g., the bootstrap server
  # lkc-xxxxx.domdponq74g..., broker endpoints, etc.) will resolve using this record.
  name = "*.${google_dns_managed_zone.private_zone.dns_name}" # e.g., *.domdponq74g.us-central1.gcp.confluent.cloud.

  project      = var.gcp_project_id
  # Specifies the record type as 'A' (Address record).
  type         = "A"
  # Time-To-Live (TTL) in seconds: How long DNS resolvers should cache this record.
  ttl          = var.dns_ttl # e.g., 60 seconds for quick updates if needed.
  # The name of the managed zone this record belongs to.
  managed_zone = google_dns_managed_zone.private_zone.name

  # The list of IP addresses this record resolves to.
  # **Crucial:** This points the wildcard record directly to the static internal IP address
  # of the PSC endpoint created in Step 03. All internal DNS lookups for Confluent hostnames
  # will now resolve to this single private entry point IP.
  rrdatas = [var.psc_forwarding_rule_ip] # e.g., ["10.10.0.3"]
}

# --- Outputs ---
# Exposes information about the created DNS resources.

output "private_dns_zone_name" {
  description = "The name of the created GCP Private DNS Managed Zone."
  value       = google_dns_managed_zone.private_zone.name
}

output "private_dns_zone_dns_name" {
  description = "The DNS name (domain) managed by the created private zone."
  value       = google_dns_managed_zone.private_zone.dns_name
}

output "wildcard_a_record_fqdn" {
  description = "The Fully Qualified Domain Name (FQDN) of the wildcard A record created."
  value       = google_dns_record_set.wildcard_a.name
}

output "wildcard_a_record_targets" {
  description = "The IP address(es) the wildcard A record points to (should be the PSC endpoint IP)."
  value       = google_dns_record_set.wildcard_a.rrdatas
}
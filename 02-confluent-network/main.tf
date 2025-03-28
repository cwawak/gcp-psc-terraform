# --- Terraform and Provider Configuration ---
# Defines required Terraform providers and configures the Confluent Cloud provider.

terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.22" # Use a recent stable version of the Confluent provider
    }
  }
  # Note: No backend is configured; using local state.
}

# Configure the Confluent Cloud provider.
# Authentication is handled via environment variables:
# - CONFLUENT_CLOUD_API_KEY
# - CONFLUENT_CLOUD_API_SECRET
provider "confluent" {}

# --- Locals for Consistent Naming ---
# Defines local variables to construct resource names based on a standard convention.
locals {
  network_display_name = "${var.username}-${var.resource_prefix}-ccloud-network"     # e.g., cwawak-gcppsctest-ccloud-network
  plink_display_name   = "${var.username}-${var.resource_prefix}-ccloud-plinkaccess" # e.g., cwawak-gcppsctest-ccloud-plinkaccess
}

# --- Resource Definitions ---

# 1. Confluent Cloud Network: Creates a dedicated network space within your Confluent Cloud environment.
# This network will be configured for private connectivity (PSC) to your GCP project.
resource "confluent_network" "main" {
  display_name = local.network_display_name    # User-friendly name for the network in Confluent Cloud UI.
  cloud        = var.confluent_network_cloud  # Specifies the target cloud provider ("GCP").
  region       = var.confluent_network_region # Specifies the cloud provider region (e.g., "us-central1").

  # Associates this network with a specific Confluent Cloud environment.
  environment {
    id = var.confluent_environment_id
  }

  # Specifies the type of network connection. "PRIVATELINK" enables PSC for GCP.
  connection_types = ["PRIVATELINK"]

  # For GCP PSC, Confluent requires the network to span exactly three availability zones within the region.
  zones            = var.network_zones # e.g., ["us-central1-a", "us-central1-b", "us-central1-c"]

  # Configures DNS within Confluent Cloud for this network.
  # "PRIVATE" ensures internal hostnames resolve to private endpoints.
  dns_config {
    resolution = "PRIVATE"
  }
  # Note: The 'gcp {}' block is intentionally omitted here as it's not used for PRIVATELINK type per provider docs.
}

# 2. Confluent Cloud Private Link Access: Creates an access control entry that explicitly allows
# a specific GCP project to establish a Private Service Connect connection to the Confluent Network created above.
resource "confluent_private_link_access" "main" {
  display_name = local.plink_display_name # User-friendly name for the access rule.

  # Specifies the GCP project that is authorized to connect.
  gcp {
    project = var.gcp_project_id # Your GCP project ID (e.g., "cops-testing").
  }

  # Associates this access rule with the specific Confluent Cloud environment.
  environment {
    id = var.confluent_environment_id
  }

  # Links this access rule to the specific Confluent Network created above.
  network {
    id = confluent_network.main.id
  }

  # Ensures the Confluent Network exists before attempting to create the access rule for it.
  depends_on = [confluent_network.main]
}


# --- Outputs ---
# Exposes important information about the created Confluent resources.

output "confluent_network_id" {
  description = "The unique ID of the created Confluent Cloud Network (e.g., 'n-xxxxxxxx')."
  value       = confluent_network.main.id
}

output "gcp_service_attachment_uri" {
  description = "The GCP Service Attachment URI exposed by Confluent Cloud for the specified zone. This is needed as the 'target' for the GCP PSC Endpoint in Step 03."
  # This value may take several minutes to become available after 'terraform apply'.
  # It's retrieved from the network resource's 'gcp' attribute map, keyed by availability zone.
  # We use the first zone from the input variable list as the key here.
  value = confluent_network.main.gcp[0].private_service_connect_service_attachments[var.network_zones[0]]
}

output "confluent_network_dns_domain" {
  description = "The private DNS domain associated with the Confluent Network (e.g., 'pxxxxxx.us-central1.gcp.confluent.cloud'). Needed for GCP DNS configuration in Step 05."
  value       = confluent_network.main.dns_domain
}
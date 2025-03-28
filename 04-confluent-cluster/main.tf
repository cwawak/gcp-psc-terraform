# --- Terraform and Provider Configuration ---
# Standard provider setup for Confluent Cloud.

terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.22" # Align with version used in Step 2
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
# Defines local variables for resource naming within Confluent Cloud.
locals {
  cluster_display_name = "${var.username}-${var.resource_prefix}-kafka-cluster" # e.g., cwawak-gcppsctest-kafka-cluster
  sa_display_name      = "${var.username}-${var.resource_prefix}-app-sa"        # e.g., cwawak-gcppsctest-app-sa
  api_key_display_name = "${local.sa_display_name}-key"                         # e.g., cwawak-gcppsctest-app-sa-key
}

# --- Resource Definitions ---

# 1. Dedicated Kafka Cluster: Provisions the actual Apache Kafka cluster within Confluent Cloud.
resource "confluent_kafka_cluster" "dedicated" {
  display_name = local.cluster_display_name # User-friendly name in Confluent Cloud UI.
  # Availability: "SINGLE_ZONE" selected for cost savings in this non-production setup.
  # For production High Availability (HA), "MULTI_ZONE" is recommended.
  availability = "SINGLE_ZONE"
  cloud        = var.confluent_network_cloud  # Specifies the cloud provider ("GCP").
  region       = var.region # Specifies the cloud region (e.g., "us-central1").

  # Configuration specific to Dedicated clusters.
  dedicated {
    # CKUs (Confluent Kafka Units) determine the cluster's capacity, throughput, and cost.
    cku = var.cluster_cku
  }

  # Associates the cluster with the correct Confluent Cloud Environment.
  environment {
    id = var.confluent_environment_id
  }

  # Associates the cluster with the PRIVATELINK network created in Step 02.
  # This ensures the cluster is only accessible via the private endpoint.
  network {
    id = var.confluent_network_id # Network ID obtained from Step 02 output.
  }
}

# 2. Service Account: Creates a non-human identity within Confluent Cloud.
# Used by applications or Terraform itself to authenticate and interact with Kafka resources.
resource "confluent_service_account" "app_sa" {
  display_name = local.sa_display_name
  description  = "Service account for application access to the ${local.cluster_display_name} cluster."
}

# 3. Role Binding: Grants permissions (roles) to a principal (the Service Account) on specific resources (the Kafka cluster).
# This controls what the Service Account is authorized to do.
resource "confluent_role_binding" "app_sa_cluster_admin" {
  # The identity being granted permissions (format: "User:<service_account_id>").
  principal   = "User:${confluent_service_account.app_sa.id}"
  # The predefined role granting permissions. 'CloudClusterAdmin' provides broad control over the cluster.
  # **Note for Production:** Use more granular roles (e.g., DeveloperRead, DeveloperWrite, SecurityAdmin)
  # following the principle of least privilege.
  role_name   = "CloudClusterAdmin"
  # Specifies the resource the role applies to, using the cluster's RBAC CRN (Confluent Resource Name).
  crn_pattern = confluent_kafka_cluster.dedicated.rbac_crn

  # Ensure the Service Account and Kafka Cluster exist before attempting to create the binding.
  depends_on = [confluent_service_account.app_sa, confluent_kafka_cluster.dedicated]
}

# 4. API Key: Creates a specific Key/Secret credential pair associated with the Service Account.
# These credentials are used by Kafka clients to authenticate.
resource "confluent_api_key" "app_sa_key" {
  display_name = local.api_key_display_name
  description  = "Kafka API Key for Service Account ${local.sa_display_name}"

  # **Workaround:** Disables Terraform's check for key readiness after creation.
  # This may be necessary if Terraform runs from a location (like the laptop) that cannot directly reach
  # the Kafka cluster's private endpoint to verify the key's status, preventing potential timeouts.
  disable_wait_for_ready = true

  # Specifies the owner of the API Key (the Service Account).
  owner {
    id          = confluent_service_account.app_sa.id
    api_version = confluent_service_account.app_sa.api_version
    kind        = confluent_service_account.app_sa.kind
  }

  # Specifies the primary resource context for this API Key (the Kafka cluster).
  managed_resource {
    id          = confluent_kafka_cluster.dedicated.id
    api_version = confluent_kafka_cluster.dedicated.api_version
    kind        = confluent_kafka_cluster.dedicated.kind
    # Also requires environment context for cluster-scoped keys.
    environment {
      id = var.confluent_environment_id
    }
  }

  # Ensures the Role Binding is created before the API Key, as the key might
  # immediately be used with the permissions granted by the binding.
  depends_on = [confluent_role_binding.app_sa_cluster_admin]
}

# --- Outputs ---
# Exposes information about the created Kafka cluster and credentials.

output "kafka_cluster_id" {
  description = "The unique ID of the created Kafka cluster (e.g., 'lkc-xxxxxx')."
  value       = confluent_kafka_cluster.dedicated.id
}

output "kafka_cluster_bootstrap_endpoint" {
  description = "The private bootstrap endpoint URL for the Kafka cluster. Clients connect to this address via the PSC connection."
  value       = confluent_kafka_cluster.dedicated.bootstrap_endpoint # e.g., lkc-xxxxxx.xxxxx.us-central1.gcp.confluent.cloud:9092
}

output "kafka_service_account_id" {
  description = "The unique ID of the created Confluent Cloud Service Account (e.g., 'sa-xxxxxx')."
  value       = confluent_service_account.app_sa.id
}

output "kafka_api_key" {
  description = "The API Key (username) for the service account. Treat as sensitive."
  value       = confluent_api_key.app_sa_key.id
  sensitive   = true # Marks the output as sensitive in Terraform logs.
}

output "kafka_api_secret" {
  description = "The API Secret (password) for the service account. Treat as sensitive."
  value       = confluent_api_key.app_sa_key.secret
  sensitive   = true # Marks the output as sensitive in Terraform logs.
}

output "network_private_dns_domain_from_input" {
  description = "Informational: The private DNS domain associated with the network (passed as input)."
  value       = var.confluent_network_dns_domain
}

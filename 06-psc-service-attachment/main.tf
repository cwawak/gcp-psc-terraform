# --- Terraform and Provider Configuration ---
# PSC Service Attachment for Confluent HTTP Sink to VM HTTPS Server

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.region
}

# --- Locals for Consistent Naming ---
locals {
  health_check_name       = "${var.username}-${var.resource_prefix}-https-health-check"
  instance_group_name     = "${var.username}-${var.resource_prefix}-https-vm-group"
  backend_service_name    = "${var.username}-${var.resource_prefix}-https-backend"
  service_attachment_name = "${var.username}-${var.resource_prefix}-confluent-service-attachment"
}

# --- Data Sources ---
# Reference existing resources from previous steps

data "google_compute_network" "vpc" {
  name    = var.vpc_name
  project = var.gcp_project_id
}

data "google_compute_subnetwork" "subnet" {
  name    = var.subnet_name
  region  = var.region
  project = var.gcp_project_id
}

# --- PSC Dedicated Subnet ---
resource "google_compute_subnetwork" "psc_subnet" {
  name          = "${var.username}-${var.resource_prefix}-psc-subnet"
  ip_cidr_range = var.psc_subnet_cidr
  region        = var.region
  network       = data.google_compute_network.vpc.id
  purpose       = "PRIVATE_SERVICE_CONNECT"
}

data "google_compute_instance" "existing_vm" {
  name = "${var.username}-${var.resource_prefix}-vm-client"
  zone = var.zone
}

# --- Firewall Rule for Google Cloud Health Checks ---
resource "google_compute_firewall" "allow_health_checks" {
  name    = "${var.username}-${var.resource_prefix}-allow-health-checks"
  network = data.google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  # Google Cloud health check IP ranges
  source_ranges = [
    "130.211.0.0/22",
    "35.191.0.0/16"
  ]

  target_tags = ["${var.username}-${var.resource_prefix}-vm-client"]
}

# --- Health Check for HTTPS ---
resource "google_compute_health_check" "https_health_check" {
  name = local.health_check_name

  tcp_health_check {
    port = 443
  }

  check_interval_sec  = var.health_check_interval
  timeout_sec         = var.health_check_timeout
  healthy_threshold   = 2
  unhealthy_threshold = 3
}

# --- Instance Group ---
resource "google_compute_instance_group" "https_vm_group" {
  name = local.instance_group_name
  zone = var.zone

  instances = [
    data.google_compute_instance.existing_vm.self_link
  ]

  named_port {
    name = "https"
    port = 443
  }
}

# --- Regional Backend Service ---
resource "google_compute_region_backend_service" "https_backend" {
  name        = local.backend_service_name
  region      = var.region
  protocol    = "TCP" # Use TCP for INTERNAL load balancing scheme
  timeout_sec = var.backend_timeout

  health_checks = [google_compute_health_check.https_health_check.self_link]

  backend {
    group = google_compute_instance_group.https_vm_group.self_link
  }

  # Required for PSC Service Attachment
  load_balancing_scheme = "INTERNAL"
}

# --- Internal Load Balancer Forwarding Rule ---
resource "google_compute_forwarding_rule" "https_forwarding_rule" {
  name                  = "${var.username}-${var.resource_prefix}-https-forwarding-rule"
  region                = var.region
  backend_service       = google_compute_region_backend_service.https_backend.self_link
  load_balancing_scheme = "INTERNAL"
  network               = data.google_compute_network.vpc.self_link
  subnetwork            = data.google_compute_subnetwork.subnet.self_link
  ports                 = ["443"]
  ip_protocol           = "TCP"
}

# --- PSC Service Attachment ---
resource "google_compute_service_attachment" "confluent_https_service" {
  name           = local.service_attachment_name
  region         = var.region
  target_service = google_compute_forwarding_rule.https_forwarding_rule.self_link

  connection_preference = var.connection_preference
  nat_subnets           = [google_compute_subnetwork.psc_subnet.self_link]
  enable_proxy_protocol = false

  # Optional: Set connection limit
  dynamic "consumer_accept_lists" {
    for_each = var.accepted_projects != null ? toset(var.accepted_projects) : []
    content {
      project_id_or_num = consumer_accept_lists.value
      connection_limit  = var.connection_limit
    }
  }
}

# Outputs moved to outputs.tf file
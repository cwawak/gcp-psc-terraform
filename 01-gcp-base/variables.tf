# variables.tf - Defines input variables for the 01-gcp-base configuration.
# These variables allow customization of the GCP base infrastructure deployment.

variable "gcp_project_id" {
  description = "Your Google Cloud Platform Project ID where resources will be created."
  type        = string
}

variable "region" {
  description = "The primary GCP region for deploying resources (e.g., 'us-central1')."
  type        = string
}

variable "zone" {
  description = "The specific GCP availability zone within the region for the VM instance (e.g., 'us-central1-a')."
  type        = string
}

variable "username" {
  description = "A short identifier (e.g., your username) used in resource naming conventions to ensure uniqueness."
  type        = string
}

variable "resource_prefix" {
  description = "A short string used as part of the resource naming convention (e.g., 'gcppsctest'). Helps group resources visually."
  type        = string
}

variable "subnet_ip_cidr" {
  description = "The private IP CIDR range for the VPC subnet (e.g., '10.10.0.0/20')."
  type        = string
}

variable "vm_machine_type" {
  description = "The machine type (CPU/memory) for the Compute Engine VM (e.g., 'e2-small')."
  type        = string
  # Default removed - value should be provided via .tfvars file.
}

variable "vm_image" {
  description = "The source OS image for the Compute Engine VM (e.g., 'debian-cloud/debian-11')."
  type        = string
  # Default removed - value should be provided via .tfvars file.
}

variable "ssh_public_key" {
  description = "The SSH public key material (content of your .pub file) to add to the VM instance metadata for SSH access."
  type        = string
  # Ensure this does not contain sensitive private key data.
}

variable "allowed_ssh_source_ip_cidr" {
  description = "Source IP CIDR allowed for SSH access (TCP/22) to the VM. Restrict to your IP for security."
  type        = string
}

variable "wireguard_listen_port" {
  description = "The UDP port number the WireGuard VPN server will listen on within the VM."
  type        = number
}

variable "allowed_wireguard_source_ip_cidr" {
  description = "Source IP CIDR allowed for WireGuard access (UDP) to the VM. Restrict to your IP for security."
  type        = string
}
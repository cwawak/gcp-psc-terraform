# --- Terraform and Provider Configuration ---
# Defines required Terraform providers and configures the Google Cloud provider.

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0" # Use a recent stable version of the Google provider
    }
  }
  # Note: No backend is configured; using local state (not recommended for collaboration/production).
}

# Configure the Google Cloud provider with project and region details from variables.
provider "google" {
  project = var.gcp_project_id
  region  = var.region
}

# --- Locals for Consistent Naming ---
# Defines local variables to construct resource names based on a standard convention.
locals {
  # Standardized naming convention: username-prefix-type
  vpc_full_name            = "${var.username}-${var.resource_prefix}-vpc"          # e.g., cwawak-gcppsctest-vpc
  subnet_full_name         = "${var.username}-${var.resource_prefix}-subnet"       # e.g., cwawak-gcppsctest-subnet
  router_full_name         = "${var.username}-${var.resource_prefix}-router"       # e.g., cwawak-gcppsctest-router
  nat_full_name            = "${var.username}-${var.resource_prefix}-nat"          # e.g., cwawak-gcppsctest-nat
  vm_full_name             = "${var.username}-${var.resource_prefix}-vm-client"    # e.g., cwawak-gcppsctest-vm-client
  firewall_ssh_full_name   = "${var.username}-${var.resource_prefix}-allow-ssh"   # e.g., cwawak-gcppsctest-allow-ssh
  firewall_wg_full_name    = "${local.vm_full_name}-allow-wg"                     # e.g., cwawak-gcppsctest-vm-client-allow-wg
}

# --- Resource Definitions ---

# 1. VPC Network: Creates an isolated Virtual Private Cloud network environment within GCP.
# This provides network boundaries for the deployed resources.
resource "google_compute_network" "vpc" {
  name                    = local.vpc_full_name
  # Use custom subnet mode for explicit control over subnets within the VPC.
  auto_create_subnetworks = false
  mtu                     = 1460  # Standard Maximum Transmission Unit size.
  project                 = var.gcp_project_id
}

# 2. Subnet: Defines a specific IP address range within the VPC.
# Resources like the VM and PSC endpoint will get their internal IPs from this range.
resource "google_compute_subnetwork" "subnet" {
  name                     = local.subnet_full_name
  ip_cidr_range            = var.subnet_ip_cidr       # The private IP range for this subnet (e.g., 10.10.0.0/20).
  region                   = var.region               # The GCP region where the subnet resides (e.g., us-central1).
  network                  = google_compute_network.vpc.id # Associates this subnet with the VPC created above.
  # Allows VMs in this subnet without external IPs to reach Google APIs privately.
  private_ip_google_access = true
  project                  = var.gcp_project_id
}

# 3. Cloud Router: A required prerequisite for Cloud NAT.
# Manages BGP sessions for dynamic routing (though not used for dynamic routing here).
resource "google_compute_router" "router" {
  name    = local.router_full_name
  region  = var.region
  network = google_compute_network.vpc.id # Associates the router with our VPC.
  project = var.gcp_project_id
}

# 4. Cloud NAT: Provides outbound internet connectivity for instances within the subnet
# that do not have their own external IP addresses (or for controlled outbound access).
# Allows the private VM to reach the internet for tasks like package updates.
resource "google_compute_router_nat" "nat" {
  name                               = local.nat_full_name
  router                             = google_compute_router.router.name # Links NAT to the Cloud Router.
  region                             = var.region
  project                            = var.gcp_project_id
  # Specifies that NAT configuration applies to specific subnetworks defined below.
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  # Define which subnet(s) will use this NAT gateway.
  subnetwork {
    name                    = google_compute_subnetwork.subnet.id # Use the subnet created above.
    # Specify which IP ranges within the subnet should use NAT. "ALL_IP_RANGES" covers the primary range.
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  # Automatically allocate ephemeral external IP addresses for NAT traffic.
  nat_ip_allocate_option            = "AUTO_ONLY"
  # Helps maintain consistent external IP and port mapping for outgoing connections.
  enable_endpoint_independent_mapping = true

  # Ensure the router exists before creating the NAT gateway attached to it.
  depends_on = [google_compute_router.router]
}

# 5. Compute Engine Instance: A virtual machine deployed within the subnet.
# This VM serves as a client host for testing and as the WireGuard VPN gateway.
resource "google_compute_instance" "vm" {
  name           = local.vm_full_name
  machine_type = var.vm_machine_type        # Specifies the VM size (e.g., e2-small).
  zone           = var.zone                 # The specific availability zone for the VM (e.g., us-central1-a).
  project        = var.gcp_project_id
  # **Crucial:** Allows this VM's network interface to handle packets not destined for its own IP.
  # Required for the VM to act as a router/gateway (for WireGuard).
  can_ip_forward = true

  # Tags are labels used for identification and targeting by firewall rules.
  tags = [local.vm_full_name, var.username, var.resource_prefix]

  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -e
    
    echo "=== Starting WireGuard VPN Server Setup ==="
    
    # Update package list and install WireGuard
    echo "Installing WireGuard..."
    apt-get update
    apt-get install -y wireguard curl
    
    # Enable IP forwarding in the kernel and make it persistent
    echo "Enabling IP forwarding..."
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p
    
    # Create WireGuard directory and generate keys
    echo "Setting up WireGuard configuration..."
    mkdir -p /etc/wireguard
    cd /etc/wireguard
    
    # Generate server and client key pairs
    echo "Generating WireGuard keys..."
    wg genkey | tee server_private.key | wg pubkey > server_public.key
    wg genkey | tee client_private.key | wg pubkey > client_public.key
    
    # Get the server's external IP for client config
    EXTERNAL_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || curl -s ipinfo.io/ip)
    
    # Create WireGuard server configuration
    echo "Creating server configuration..."
    cat > wg0.conf << EOF
# WireGuard Server Configuration
[Interface]
Address = 10.200.0.1/24
ListenPort = ${var.wireguard_listen_port}
PrivateKey = $(cat server_private.key)

# NAT and forwarding rules for ens4 (GCP default interface)
PostUp = iptables -t nat -A POSTROUTING -o ens4 -j MASQUERADE; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o ens4 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o ens4 -j MASQUERADE; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o ens4 -j ACCEPT

[Peer]
# Client peer configuration
PublicKey = $(cat client_public.key)
AllowedIPs = 10.200.0.2/32
EOF
    
    # Set proper permissions on server config
    chmod 600 wg0.conf
    
    # Create client configuration file in accessible location
    echo "Creating client configuration..."
    cat > /tmp/client.conf << EOF
# WireGuard Client Configuration
# Import this file into your WireGuard client application
[Interface]
PrivateKey = $(cat client_private.key)
Address = 10.200.0.2/32
DNS = 8.8.8.8

[Peer]
PublicKey = $(cat server_public.key)
Endpoint = $EXTERNAL_IP:${var.wireguard_listen_port}
AllowedIPs = ${var.subnet_ip_cidr}, 10.200.0.0/24
PersistentKeepalive = 25
EOF
    
    # Make client config readable by user
    chmod 644 /tmp/client.conf
    
    # Enable and start WireGuard service
    echo "Starting WireGuard service..."
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0
    
    # Verify service status
    echo "Verifying WireGuard service..."
    systemctl is-active wg-quick@wg0 || echo "Warning: WireGuard service may not be running properly"
    
    # Create success indicator file
    echo "WireGuard setup completed successfully at $(date)" > /tmp/wireguard-setup-complete
    
    echo "=== WireGuard VPN Server Setup Complete ==="
    echo "Client configuration file created at: /tmp/client.conf"
    echo "Use 'gcloud compute ssh' to retrieve the client config file"
  EOT

  # Defines the boot disk configuration for the VM.
  boot_disk {
    initialize_params {
      image = var.vm_image # Specifies the OS image (e.g., Debian 11).
      size  = 20         # Sets the boot disk size in GB.
    }
  }

  # Defines the network interface for the VM.
  network_interface {
    network    = google_compute_network.vpc.id    # Connects to our VPC.
    subnetwork = google_compute_subnetwork.subnet.id # Connects to our subnet, gets internal IP from its range.

    # Defines configuration for assigning an external IP address.
    # An empty block requests an ephemeral (temporary) public IP.
    # This IP is used for direct SSH access and as the WireGuard endpoint.
    access_config {
      // Ephemeral IP is assigned automatically by GCP upon creation.
    }
  }

  # Configures SSH access using metadata keys instead of OS Login.
  # This method embeds the public key directly into instance metadata.
  # Avoids needing specific OS Login IAM roles for standard SSH authentication.
  metadata = {
    # Format: LOGIN_USERNAME:PUBLIC_KEY_MATERIAL
    ssh-keys = "${var.username}:${var.ssh_public_key}"
  }

  # Allows Terraform to stop the instance to apply certain updates if necessary.
  allow_stopping_for_update = true
}

# 6. Firewall Rule: Allows incoming SSH traffic (TCP port 22).
# This rule permits connections to the VM's external IP on port 22.
resource "google_compute_firewall" "allow_ssh_from_user" {
  name    = local.firewall_ssh_full_name
  network = google_compute_network.vpc.name # Apply rule to our specific VPC.
  project = var.gcp_project_id
  direction = "INGRESS" # Rule applies to incoming traffic.
  priority  = 1000      # Standard default priority.

  # Defines the protocol and port allowed.
  allow {
    protocol = "tcp"
    ports    = ["22"] # Allow TCP traffic on port 22 (SSH).
  }

  # **Security:** Restricts the allowed source of traffic to a specific IP range (CIDR).
  # Should be set to the user's trusted public IP address.
  source_ranges = [var.allowed_ssh_source_ip_cidr]

  # Applies this rule only to instances within the VPC that have the specified tag.
  # Targets the VM created above, assuming it's tagged with the username.
  target_tags = [var.username]

  # Ensure the VPC exists before creating firewall rules for it.
  depends_on = [google_compute_network.vpc]
}

# 7. Firewall Rule: Allows incoming WireGuard VPN traffic (UDP).
# This rule permits connections to the VM's external IP on the specified WireGuard port.
resource "google_compute_firewall" "allow_wireguard_from_user" {
  name    = local.firewall_wg_full_name
  network = google_compute_network.vpc.name # Apply rule to our specific VPC.
  project = var.gcp_project_id
  direction = "INGRESS" # Rule applies to incoming traffic.
  priority  = 1000      # Standard default priority.

  # Defines the protocol and port allowed.
  allow {
    protocol = "udp"
    ports    = [var.wireguard_listen_port] # Allow UDP traffic on the WireGuard port (e.g., 51820).
  }

  # **Security:** Restricts the allowed source of traffic to a specific IP range (CIDR).
  # Should be set to the user's trusted public IP address.
  source_ranges = [var.allowed_wireguard_source_ip_cidr]

  # Applies this rule only to instances within the VPC that have the specified tag.
  # Targets the VM created above, assuming it's tagged with the username.
  target_tags = [var.username]

  # Ensure the VPC exists before creating firewall rules for it.
  depends_on = [google_compute_network.vpc]
}

# 8. Firewall Rule: Allows all internal traffic within the VPC subnet.
# This is a crucial rule for allowing resources within the same network to communicate freely.
# It was added to resolve intra-VPC connectivity issues discovered during debugging.
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.username}-${var.resource_prefix}-allow-internal"
  network = google_compute_network.vpc.name
  project = var.gcp_project_id

  # Allow all protocols (tcp, udp, icmp, etc.)
  allow {
    protocol = "all"
  }

  # This rule applies to any traffic originating from within the subnet.
  source_ranges = [var.subnet_ip_cidr]
}

# --- Outputs ---
# Exposes important information about the created resources for reference or use in subsequent steps.

output "vpc_id" {
  description = "The full ID of the created VPC Network."
  value       = google_compute_network.vpc.id
}

output "vpc_name" {
  description = "The name of the created VPC Network."
  value       = google_compute_network.vpc.name
}

output "subnet_id" {
  description = "The full ID of the created Subnet."
  value       = google_compute_subnetwork.subnet.id
}

output "subnet_name" {
  description = "The name of the created Subnet."
  value       = google_compute_subnetwork.subnet.name
}

output "subnet_region" {
  description = "The region of the created Subnet."
  value       = google_compute_subnetwork.subnet.region
}

output "vm_name" {
  description = "The name of the created Compute Engine instance."
  value       = google_compute_instance.vm.name
}

output "vm_zone" {
  description = "The zone of the created Compute Engine instance."
  value       = google_compute_instance.vm.zone
}

output "vm_internal_ip" {
  description = "The internal IP address assigned to the Compute Engine instance within the subnet."
  value       = google_compute_instance.vm.network_interface[0].network_ip
}

output "vm_external_ip" {
  description = "The ephemeral external IP address assigned to the Compute Engine instance."
  # Access the 'nat_ip' field within the first 'access_config' block of the first network interface.
  value       = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip
}

output "gcp_project_id_output" {
  description = "The GCP Project ID used for deployment."
  value       = var.gcp_project_id
}

output "vm_ssh_command_external_ip" {
  description = "Example command to SSH into the VM using its external IP (requires firewall rule access)."
  # Uses try() to provide a fallback value if the external IP isn't known during 'terraform plan'.
  value = try("ssh ${var.username}@${google_compute_instance.vm.network_interface[0].access_config[0].nat_ip}", "ssh ${var.username}@<EXTERNAL_IP_KNOWN_AFTER_APPLY>")
}

output "vm_ssh_command_iap" {
  description = "Example gcloud command to SSH into the VM using IAP tunneling (requires specific IAM permissions and no external IP)."
  # Note: This setup uses an external IP, making standard SSH more direct if firewall allows. IAP is an alternative.
  value       = "gcloud compute ssh ${local.vm_full_name} --zone ${var.zone} --project ${var.gcp_project_id} --tunnel-through-iap"
}

# --- WireGuard VPN Configuration Outputs ---
# These outputs provide clear instructions for obtaining the WireGuard client configuration.

output "wireguard_server_endpoint" {
  description = "The WireGuard server endpoint (IP:PORT) for client configuration."
  value       = try("${google_compute_instance.vm.network_interface[0].access_config[0].nat_ip}:${var.wireguard_listen_port}", "<EXTERNAL_IP_KNOWN_AFTER_APPLY>:${var.wireguard_listen_port}")
}

output "wireguard_setup_status_check" {
  description = "Command to check if WireGuard setup completed successfully on the VM."
  value       = "gcloud compute ssh ${local.vm_full_name} --zone ${var.zone} --project ${var.gcp_project_id} --command='cat /tmp/wireguard-setup-complete'"
}

output "wireguard_server_status_check" {
  description = "Command to verify WireGuard service is running on the VM."
  value       = "gcloud compute ssh ${local.vm_full_name} --zone ${var.zone} --project ${var.gcp_project_id} --command='sudo systemctl status wg-quick@wg0'"
}

output "WIREGUARD_CLIENT_CONFIG_INSTRUCTIONS" {
  description = "🔧 IMPORTANT: How to get your WireGuard client configuration file."
  value = <<-EOT

🔧 WIREGUARD CLIENT SETUP INSTRUCTIONS

1. Wait for VM startup to complete (2-3 minutes after terraform apply)

2. Get your client configuration file:
   gcloud compute ssh ${local.vm_full_name} \
     --zone ${var.zone} \
     --project ${var.gcp_project_id} \
     --command="cat /tmp/client.conf" > my-wireguard-client.conf

3. Import the downloaded file into your WireGuard client:
   • Mobile: Use QR code or import file
   • Desktop: Import tunnel from file
   • Command line: wg-quick up my-wireguard-client.conf

4. Connect to your VPN and test connectivity!

🔍 TROUBLESHOOTING:
• Check setup status: use 'wireguard_setup_status_check' output
• Check service status: use 'wireguard_server_status_check' output
• View server logs: gcloud compute ssh [...] --command='journalctl -u wg-quick@wg0'

EOT
}
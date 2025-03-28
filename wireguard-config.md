**WireGuard VPN Configuration Documentation**

**Note:** Specific resource names, IDs (like cluster/network IDs), the Confluent domain, and external IPs from the original deployment have been replaced with generic placeholders (e.g., `<your-vm-name>`, `<kafka-cluster-id>`, `<VM_EXTERNAL_IP>`, `<private-link-id>`). The internal VPC Subnet CIDR (`10.10.0.0/20`) is shown explicitly as it's standard private addressing. Replace placeholders with your actual values during setup or when interpreting this documentation for a specific environment.

**1. Overview**

WireGuard is used in this setup to establish a secure VPN tunnel from a user's laptop directly into the private GCP Virtual Private Cloud (VPC) network (e.g., `<your-vpc-name>`). This allows the user to securely access resources within the VPC, including the Private Service Connect (PSC) endpoint (e.g., `<PSC_ENDPOINT_IP>`), and subsequently the private Confluent Cloud Kafka cluster, without exposing those resources directly to the internet. The primary subnet within the GCP VPC uses the `10.10.0.0/20` address range.

* **Server:** The GCP Compute Engine VM (e.g., `<your-vm-name>`, Internal IP: `<VM_INTERNAL_IP>`, External IP: `<VM_EXTERNAL_IP>`) acts as the WireGuard server.
* **Client:** The user's laptop runs the WireGuard client software.
* **Network:** The WireGuard tunnel uses its own private IP subnet (e.g., `10.200.0.0/24`) separate from the main GCP subnet (`10.10.0.0/20`).

**2. Server Configuration (on `<your-vm-name>`)**

The WireGuard server configuration is defined in `/etc/wireguard/wg0.conf` on the VM.

```ini
# /etc/wireguard/wg0.conf (on Server VM: <your-vm-name>)

[Interface]
# Private IP address assigned to the WireGuard server's virtual interface (wg0).
Address = 10.200.0.1/24

# The UDP port the WireGuard server listens on for incoming client connections.
# This port must be allowed through the GCP Firewall (e.g., UDP:51820 from client's public IP).
ListenPort = 51820

# Path to the server's private key file. Keep this file secure!
# Replace <SERVER_PRIVATE_KEY> with the actual key content during setup.
PrivateKey = <SERVER_PRIVATE_KEY>

# --- IP Forwarding & NAT Rules ---
# These commands enable the server VM to act as a gateway/NAT for VPN clients.
# Note: 'ens4' is the primary network interface, this might vary (e.g., 'eth0') depending on the OS/GCP image.

# PostUp: Runs when wg0 comes UP. Enables NAT and forwarding.
PostUp = iptables -t nat -A POSTROUTING -o ens4 -j MASQUERADE; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o ens4 -j ACCEPT

# PostDown: Runs when wg0 goes DOWN. Reverses the PostUp rules.
PostDown = iptables -t nat -D POSTROUTING -o ens4 -j MASQUERADE; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o ens4 -j ACCEPT

# --- Client Peer Definition ---
[Peer]
# Public key of the connecting client (laptop).
PublicKey = <CLIENT_PUBLIC_KEY>

# The private IP address(es) assigned exclusively to this specific client within the WireGuard tunnel.
AllowedIPs = 10.200.0.2/32 # Example client IP
```

**Key Server-Side Prerequisites (Managed by Terraform or Manual Setup):**

* **WireGuard Installation:** `wireguard` package installed.
* **IP Forwarding:** Kernel IP forwarding enabled (`net.ipv4.ip_forward=1`). Terraform VM resource includes `can_ip_forward = true`.
* **Firewall Rule:** GCP firewall rule allows UDP ingress on port `51820` from the client's public IP to the VM.

**3. Client Configuration (on Laptop)**

Saved in a `.conf` file (e.g., `gcp_vpn.conf`) and imported into the WireGuard client.

```ini
# gcp_vpn.conf (Example for Laptop Client)

[Interface]
# The private IP address assigned to the client's virtual WireGuard interface.
Address = 10.200.0.2/32 # Example client IP

# Path to the client's private key file. Keep this file secure!
PrivateKey = <CLIENT_PRIVATE_KEY>

# Optional: Specify DNS servers to use when the tunnel is active.
# DNS = 169.254.169.254, 8.8.8.8

# --- Server Peer Definition ---
[Peer]
# Public key of the WireGuard server VM.
PublicKey = <SERVER_PUBLIC_KEY>

# The public IP address and listening port of the WireGuard server VM.
Endpoint = <VM_EXTERNAL_IP>:51820

# --- Routing Configuration ---
# Defines which destination IP address ranges should be routed *through* the WireGuard tunnel.
# - 10.10.0.0/20: The specific GCP VPC subnet range where the PSC endpoint resides.
# - 10.200.0.0/24: The WireGuard VPN internal subnet itself.
AllowedIPs = 10.10.0.0/20, 10.200.0.0/24

# Optional but recommended: Sends a keepalive packet every 25 seconds.
PersistentKeepalive = 25
```

**4. Traffic Flow**

1.  Laptop connects to Server `Endpoint` (`<VM_EXTERNAL_IP>:51820`).
2.  GCP Firewall allows UDP `51820` traffic.
3.  WireGuard tunnel established.
4.  When Laptop sends traffic to `10.10.0.0/20` (e.g., targeting Kafka via PSC IP `<PSC_ENDPOINT_IP>`), the client routes this into the tunnel.
5.  Traffic arrives at the Server VM's `wg0` interface (`10.200.0.1`).
6.  Server VM routes the packet towards `<PSC_ENDPOINT_IP>`.
7.  `iptables MASQUERADE` translates the source IP (from `10.200.0.2`) to the VM's primary internal IP (`<VM_INTERNAL_IP>`) as it leaves the primary NIC (e.g., `ens4`).
8.  Traffic reaches the PSC endpoint and flows to Confluent Cloud.
9.  Return traffic flows back via the VM and tunnel to the client.

**5. DNS Considerations**

* The GCP Cloud DNS Private Zone (e.g., `<your-gcp-dns-zone-name>`) resolves the Confluent private hostname (e.g., `lkc-<cluster-id>.<private-link-id>...`) to the PSC IP (`<PSC_ENDPOINT_IP>`) *within the GCP VPC*.
* **Requirement:** The laptop client needs a way to resolve the private Confluent hostname to `<PSC_ENDPOINT_IP>`. Options:
    * **Manual `/etc/hosts` Entry:** Add `<PSC_ENDPOINT_IP> lkc-<cluster-id>.<private-link-id>.<region>.<cloud>.confluent.cloud` to the laptop's hosts file.
    * **VPN DNS Setting:** Use the `DNS` parameter in the client config if a suitable resolver is available via the tunnel.

**6. Security & Key Management**

* Protect `PrivateKey` files for server and clients.
* Restrict the WireGuard firewall rule source IP to known client IPs.

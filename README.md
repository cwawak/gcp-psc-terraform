# README: GCP Private Service Connect (PSC) to Confluent Cloud Terraform Setup

**Last Updated:** Friday, March 28, 2025

## Objective

This document and the accompanying Terraform code provide a reference architecture and step-by-step guide for establishing secure, private network connectivity between a Google Cloud Platform (GCP) project and a Confluent Cloud Kafka cluster using GCP Private Service Connect (PSC).

This setup ensures that traffic between your applications running in GCP (or connected via VPN) and your Confluent Cloud Kafka cluster does **not** traverse the public internet, enhancing security and potentially improving performance.

## Architecture Overview

The core components deployed by this Terraform setup are:

1.  **GCP Infrastructure:**
    * **VPC Network & Subnet:** A dedicated, private network (`10.10.0.0/20` in this example) within your GCP project to host resources.
    * **PSC Endpoint:** A `google_compute_forwarding_rule` resource with a static internal IP address (e.g., `10.10.0.3`) within your subnet. This acts as the single, private entry point from your VPC to the connected Confluent Cloud services.
    * **Cloud DNS Private Zone:** A private DNS zone associated with your VPC that automatically resolves Confluent Cloud's private hostnames to the PSC endpoint's internal IP address.
    * **(Optional) Client VM & VPN Gateway:** A Compute Engine VM deployed within the subnet, configured with an external IP, firewall rules, and WireGuard VPN software. **See `wireguard-config.md` for detailed setup instructions.** This allows secure access into the private VPC from a developer's laptop for testing or administration.
    * **Cloud NAT:** Provides necessary outbound internet access for the private Client VM (e.g., for OS updates).

2.  **Confluent Cloud Infrastructure:**
    * **Confluent Network:** A dedicated network within your Confluent Cloud environment configured for `PRIVATELINK` (PSC) connection type in your chosen GCP region.
    * **Private Link Access:** An access rule explicitly authorizing your specific GCP Project ID (`YOUR_GCP_PROJECT_ID`) to connect to the Confluent Network via PSC.
    * **Kafka Cluster:** A Dedicated Confluent Cloud Kafka cluster deployed *within* the Confluent Network, making it accessible only via its private endpoint.
    * **Service Account & API Key:** Credentials for applications or clients to securely authenticate and interact with the Kafka cluster.

### Connectivity Flow

1.  **From within GCP VPC:** An application running within the VPC subnet looks up the Kafka bootstrap hostname (e.g., `KAFKA_BOOTSTRAP_HOSTNAME`).
2.  The GCP Cloud DNS Private Zone resolves this hostname to the internal IP address of the PSC Endpoint (e.g., `10.10.0.3`).
3.  The application sends traffic to the PSC Endpoint IP.
4.  GCP routes this traffic via the Private Service Connect infrastructure directly to the authorized Confluent Cloud service attachment associated with your Confluent Network.
5.  Traffic reaches the Kafka cluster privately.

6.  **From Laptop via VPN (Optional):**
    * The user connects their laptop to the WireGuard server running on the GCP Client VM (setup detailed in `wireguard-config.md`).
    * The WireGuard client routes traffic destined for the GCP VPC subnet (`10.10.0.0/20`) through the VPN tunnel.
    * The user's Kafka client attempts to connect to the private Kafka bootstrap hostname (`KAFKA_BOOTSTRAP_HOSTNAME`).
    * **Crucially**, the user must ensure this hostname resolves to the PSC Endpoint IP (`10.10.0.3`) on their laptop (e.g., via a manual `/etc/hosts` entry, as detailed in `wireguard-config.md`).
    * Traffic flows through the tunnel to the VM, which then routes it internally within the VPC to the PSC Endpoint, following the flow described above.

## Prerequisites

Before running the Terraform code, ensure you have the following:

1.  **Tools:**
    * **Terraform:** Latest stable version ([Install Terraform](https://developer.hashicorp.com/terraform/downloads)).
    * **Google Cloud SDK (`gcloud`):** Latest version ([Install gcloud](https://cloud.google.com/sdk/docs/install)). Used for authentication.
    * **(Optional) `jq`:** Command-line JSON processor, useful for extracting outputs ([Install jq](https://stedolan.github.io/jq/download/)).
    * **(Optional) WireGuard Client:** If you plan to use the VPN access method ([Install WireGuard](https://www.wireguard.com/install/)).
    * **Git:** To clone the repository containing this code.

2.  **Accounts & Permissions:**
    * **GCP Project:** An active GCP Project. You need:
        * Your **GCP Project ID**. Find this in the Google Cloud Console dashboard.
        * Sufficient IAM permissions (e.g., `Editor`, `Owner`, or granular roles like `Compute Network Admin`, `Compute Instance Admin`, `DNS Administrator`, etc.).
    * **Confluent Cloud Account:** An active Confluent Cloud account. You need:
        * Your **Confluent Cloud Environment ID** (e.g., `env-xxxxxx`). Find this in the Confluent Cloud UI -> Environment settings.
        * Permissions to manage Networks, Private Link, Clusters, Service Accounts, API Keys, RBAC (e.g., `OrganizationAdmin` or granular roles).

3.  **Credentials & Keys:**
    * **Confluent Cloud API Key & Secret:** Create and securely store a Confluent Cloud API Key+Secret with necessary permissions. **Do not commit them to Git.**
    * **SSH Key Pair:** An SSH public/private key pair. You will provide the public key material to Terraform. Generate via `ssh-keygen`.
    * **Your Public IP Address:** A stable public IP address for your location. Used for firewall rules. Find via web search for "what is my IP address".

## Directory Structure

This repository uses a step-by-step directory structure for Terraform deployment:

* **`dev.tfvars`**: The primary variable definition file used in this walkthrough to provide specific settings for your deployment. It should reside in the root directory.
* `01-gcp-base/`: Creates the foundational GCP network, optional Client VM, NAT, Router, and base Firewalls.
* `02-confluent-network/`: Creates the Confluent Cloud Network and Private Link Access rule.
* `03-gcp-psc-endpoint/`: Creates the GCP PSC Endpoint and reserves its static IP.
* `04-confluent-cluster/`: Creates the Confluent Cloud Kafka Cluster, Service Account, and API Key.
* `05-gcp-dns/`: Creates the GCP Cloud DNS Private Zone and wildcard record.
* `wireguard-config.md`: Detailed instructions for setting up the optional WireGuard VPN.
* `README.md`: This main documentation file.

## Configuration (`dev.tfvars`)

Before deploying, configure your specific settings in the **`dev.tfvars`** file located in the root directory. This file provides all necessary input variables for the Terraform deployment described in this guide. Create `dev.tfvars` if it doesn't exist, using the template below as a guide.

**`dev.tfvars` Template:**

```terraform
# dev.tfvars - Input values for your specific deployment

# Core GCP/Confluent Settings
gcp_project_id           = "YOUR_GCP_PROJECT_ID"         # Your GCP Project ID
region                   = "us-central1"                   # Desired GCP region
username                 = "YOUR_USERNAME_OR_ID"         # A short identifier for resource naming
resource_prefix          = "gcppsc-demo"                   # A short prefix for resource naming
confluent_environment_id = "YOUR_CONFLUENT_ENV_ID"       # Your Confluent Cloud Environment ID (e.g., env-xxxxxx)
confluent_network_cloud  = "GCP"                           # Keep as "GCP"

# GCP Network Config
subnet_ip_cidr = "10.10.0.0/20"                           # Private IP range for GCP subnet
network_zones  = ["us-central1-a", "us-central1-b", "us-central1-c"] # Adjust zones based on 'region'

# GCP VM Config (Optional Client/VPN VM)
vm_machine_type = "e2-small"
vm_image        = "debian-cloud/debian-11"
zone            = "us-central1-a" # Specific zone within 'region' for the VM
ssh_public_key  = "YOUR_SSH_PUBLIC_KEY_MATERIAL" # Paste content of your id_rsa.pub

# Firewall Config (For Optional Client/VPN VM)
allowed_ssh_source_ip_cidr       = "YOUR_PUBLIC_IP/32" # Your current public IP
wireguard_listen_port            = 51820
allowed_wireguard_source_ip_cidr = "YOUR_PUBLIC_IP/32" # Your current public IP

# Confluent Cluster Config
cluster_cku = 1
confluent_network_region = "us-central1" # Keep consistent with 'region'

# DNS Config
dns_ttl = 60

##################################################################################
# MANUAL OUTPUT PASSING (WORKAROUND - Values filled during walkthrough)
##################################################################################
# vpc_name                     = "" # Populated after Step 1
# subnet_name                  = "" # Populated after Step 1
# gcp_service_attachment_uri   = "" # Populated after Step 2
# confluent_network_dns_domain = "" # Populated after Step 2
# confluent_network_id         = "" # Populated after Step 2
# psc_forwarding_rule_ip       = "" # Populated after Step 3
```

## Deployment Walkthrough

Follow these steps sequentially. Run commands from the root directory of this repository unless specified otherwise. All `terraform apply` commands explicitly use `-var-file=../dev.tfvars`.

**Step 0: Initial Setup & Authentication**

1.  **Authenticate GCP:** `gcloud auth application-default login` (Follow browser prompts).
2.  **Set Confluent Credentials:**
    ```bash
    export CONFLUENT_CLOUD_API_KEY="Your Confluent Cloud Key"
    export CONFLUENT_CLOUD_API_SECRET="Your Confluent Cloud Secret"
    ```

**Step 1: Deploy GCP Base Infrastructure (`01-gcp-base`)**

1.  `cd 01-gcp-base`
2.  `terraform init`
3.  `terraform apply -var-file=../dev.tfvars` (Confirm `yes`)
4.  **Record Outputs & Update `dev.tfvars`:** Note `vpc_name`, `subnet_name`, `vm_external_ip`. Edit `../dev.tfvars` and update these values in the "MANUAL OUTPUT PASSING" section.

**Step 2: Deploy Confluent Network (`02-confluent-network`)**

1.  `cd ../02-confluent-network`
2.  `terraform init`
3.  `terraform apply -var-file=../dev.tfvars` (Confirm `yes`)
4.  **WAIT (5-15+ mins)** for Confluent provisioning.
5.  **Check Output:** Periodically run `terraform output -raw gcp_service_attachment_uri` until a valid URI appears.
6.  **Record Outputs & Update `dev.tfvars`:** Get all outputs (`terraform output`). Edit `../dev.tfvars` and update `gcp_service_attachment_uri`, `confluent_network_id`, `confluent_network_dns_domain`.

**Step 3: Deploy GCP PSC Endpoint (`03-gcp-psc-endpoint`)**

1.  `cd ../03-gcp-psc-endpoint`
2.  `terraform init`
3.  `terraform apply -var-file=../dev.tfvars` (Confirm `yes`)
4.  **Record Output & Update `dev.tfvars`:** Note `psc_forwarding_rule_ip`. Edit `../dev.tfvars` and update this value.

**Step 4: Deploy Confluent Cluster (`04-confluent-cluster`)**

1.  `cd ../04-confluent-cluster`
2.  `terraform init`
3.  `terraform apply -var-file=../dev.tfvars` (Confirm `yes`)
4.  **WAIT (20-40+ mins)** for cluster creation.
5.  **Record Outputs:** Note cluster details. **Retrieve and securely store API Key/Secret:**
    ```bash
    terraform output -raw kafka_cluster_bootstrap_endpoint
    terraform output -json | jq -r .kafka_api_key.value
    terraform output -json | jq -r .kafka_api_secret.value # STORE SECURELY!
    ```

**Step 5: Deploy GCP DNS (`05-gcp-dns`)**

1.  `cd ../05-gcp-dns`
2.  `terraform init`
3.  `terraform apply -var-file=../dev.tfvars` (Confirm `yes`). This enables internal GCP DNS resolution.

**Step 6: Configure VPN Access (Optional)**

This step provides secure access from your laptop into the private GCP VPC, allowing you to reach the Kafka cluster via its private endpoint.

1.  **Prerequisites:** Ensure the Client VM (`YOUR_VM_NAME`) was created in Step 1 and you have its external IP (`vm_external_ip` output). Ensure firewall rules from Step 1 were applied.
2.  **Setup Instructions:** For detailed instructions on configuring the WireGuard server on the VM and setting up your client application, please refer to the **`wireguard-config.md`** file included in this repository.
3.  **Client DNS Requirement:** Remember that when the VPN is active, your laptop needs a way to resolve the private Kafka bootstrap hostname (`KAFKA_BOOTSTRAP_HOSTNAME`) to the PSC endpoint IP (e.g., `10.10.0.3`), as detailed in `wireguard-config.md`.

## Testing Connectivity

1.  **From within GCP (e.g., via SSH to the Client VM):**
    * Use `kcat` or `openssl` as shown previously, targeting the private `KAFKA_BOOTSTRAP_HOSTNAME` and using the API credentials from Step 4.

2.  **From Laptop (Requires successful completion of VPN setup as described in `wireguard-config.md`):**
    * Ensure the WireGuard tunnel is active on your laptop.
    * Ensure your laptop can resolve the `KAFKA_BOOTSTRAP_HOSTNAME` to the `PSC_ENDPOINT_IP` (e.g., via `/etc/hosts`).
    * Use `kcat` or `openssl` from your laptop's terminal, targeting the private `KAFKA_BOOTSTRAP_HOSTNAME` and using the API credentials.

## Cleanup

To destroy all resources, run `terraform destroy` in **reverse order** (05 -> 04 -> 03 -> 02 -> 01).

1.  `cd 05-gcp-dns && terraform destroy -var-file=../dev.tfvars` (Confirm `yes`)
2.  `cd ../04-confluent-cluster && terraform destroy -var-file=../dev.tfvars` (Confirm `yes`)
3.  `cd ../03-gcp-psc-endpoint && terraform destroy -var-file=../dev.tfvars` (Confirm `yes`)
4.  `cd ../02-confluent-network && terraform destroy -var-file=../dev.tfvars` (Confirm `yes`)
5.  `cd ../01-gcp-base && terraform destroy -var-file=../dev.tfvars` (Confirm `yes`)

Remember cleanup tasks for VPN (stop tunnel, remove hosts entry) and unset environment variables.

## Using an Existing VPC/Subnet

If you need to deploy the PSC connection within an existing VPC/Subnet:

1.  **Prerequisites:** Obtain the names of your existing VPC and the Subnet where the PSC endpoint should reside, and the Subnet's region.
2.  **Terraform Modifications & Workflow:**
    * **Skip `01-gcp-base` `apply` for VPC/Subnet:** Do not apply `google_compute_network`/`google_compute_subnetwork`.
    * **Populate `dev.tfvars`:** Manually set `vpc_name` and `subnet_name` with your existing resource names. Ensure `region` matches.
    * **Run Step 02 (`02-confluent-network`):** Apply as normal. Update `dev.tfvars` with outputs.
    * **Run Step 03 (`03-gcp-psc-endpoint`):** Apply as normal. Resources will be placed within your existing subnet. Update `dev.tfvars`.
    * **Run Step 04 (`04-confluent-cluster`):** Apply as normal.
    * **Run Step 05 (`05-gcp-dns`):** Apply as normal. The private zone will be associated with your existing VPC.
    * **(Optional) VM/VPN/NAT/Firewalls:** Decide if you need these components from Step 01. If yes, carefully adapt `01-gcp-base/main.tf` to only create these resources, referencing your existing network. If no, omit these resources. VPN setup details remain in `wireguard-config.md`.

## Notes & Disclaimers

* **Costs:** Resources deployed will incur costs in GCP and Confluent Cloud. Destroy resources after use if applicable.
* **Security:** Review all security settings (firewalls, IAM, RBAC) against best practices before production use. Handle credentials securely.
* **Manual Steps:** This guide uses manual output passing; using Terraform remote state is recommended for improved workflows. VPN setup details are in `wireguard-config.md`.
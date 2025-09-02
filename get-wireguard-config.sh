#!/bin/bash

# WireGuard Client Config Retrieval Script
# This script retrieves the WireGuard client configuration from the VM

set -e

echo "🔧 Retrieving WireGuard client configuration..."

# Check if we're in the right directory
if [ ! -f "dev.tfvars" ] || [ ! -d "01-gcp-base" ]; then
    echo "❌ Error: Please run this script from the cluster-terraform directory"
    echo "   Expected files: dev.tfvars, 01-gcp-base/"
    exit 1
fi

# Extract values from terraform outputs or tfvars
VM_NAME=$(terraform -chdir=01-gcp-base output -raw vm_name 2>/dev/null || echo "")
PROJECT_ID=$(grep 'gcp_project_id' dev.tfvars | cut -d'"' -f2)
ZONE=$(grep 'zone' dev.tfvars | cut -d'"' -f2)

if [ -z "$VM_NAME" ]; then
    # Fallback to constructing VM name from tfvars
    USERNAME=$(grep 'username' dev.tfvars | cut -d'"' -f2)
    RESOURCE_PREFIX=$(grep 'resource_prefix' dev.tfvars | cut -d'"' -f2)
    VM_NAME="${USERNAME}-${RESOURCE_PREFIX}-vm-client"
fi

echo "📋 Using configuration:"
echo "  VM Name: $VM_NAME"
echo "  Project: $PROJECT_ID"
echo "  Zone: $ZONE"

# Check if WireGuard setup is complete
echo ""
echo "🔍 Checking WireGuard setup status..."
if gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" --command="test -f /tmp/wireguard-setup-complete" 2>/dev/null; then
    echo "✅ WireGuard setup completed successfully"
else
    echo "⏳ WireGuard setup may still be in progress..."
    echo "   Checking for setup completion file..."
    
    if ! gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" --command="cat /tmp/wireguard-setup-complete 2>/dev/null || echo 'Setup not yet complete'" 2>/dev/null; then
        echo "❌ Unable to connect to VM or setup not complete"
        echo "   Try again in a few minutes"
        exit 1
    fi
fi

# Retrieve the client configuration
echo ""
echo "📥 Downloading WireGuard client configuration..."
CONFIG_FILE="wireguard-client-$(date +%Y%m%d-%H%M%S).conf"

if gcloud compute ssh "$VM_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --command="cat /tmp/client.conf" > "$CONFIG_FILE" 2>/dev/null; then
    
    echo "✅ Client configuration downloaded successfully!"
    echo ""
    echo "📁 Configuration saved as: $CONFIG_FILE"
    echo ""
    echo "🔧 Next steps:"
    echo "  1. Import this file into your WireGuard client application"
    echo "  2. Connect to the VPN"
    echo "  3. Test connectivity to your private resources"
    echo ""
    echo "📱 For mobile devices, you can generate a QR code:"
    echo "   qrencode -t ansiutf8 < $CONFIG_FILE"
    echo ""
    
    # Display a preview of the config (without private key)
    echo "📋 Configuration preview:"
    echo "----------------------------------------"
    grep -v "PrivateKey" "$CONFIG_FILE" | head -20
    echo "   [PrivateKey line hidden for security]"
    echo "----------------------------------------"
    
else
    echo "❌ Failed to download client configuration"
    echo "   This might be because:"
    echo "   - VM is still starting up"
    echo "   - WireGuard setup hasn't completed yet"
    echo "   - Network connectivity issues"
    echo ""
    echo "🔧 Troubleshooting commands:"
    echo "  Check VM status:"
    echo "    gcloud compute instances describe $VM_NAME --zone=$ZONE --project=$PROJECT_ID"
    echo ""
    echo "  Check setup logs:"
    echo "    gcloud compute ssh $VM_NAME --zone=$ZONE --project=$PROJECT_ID --command='sudo journalctl -u google-startup-scripts.service'"
    exit 1
fi
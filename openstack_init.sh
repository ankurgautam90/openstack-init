#!/bin/bash

###############################################################################
# Stop on errors, unset variables, or errors in pipelines
set -o errexit
set -o nounset
set -o pipefail

# Trap any error and print a message (but do not close SSH).
trap 'echo "[ERROR] An error occurred. Exiting the script now."; exit 1' ERR
###############################################################################

# --- Prompt for Ceph usage right away ---
echo "Are you using Ceph with OpenStack for image storage? (Y/N)"
read -r ceph_choice

# Default to not converting images
CONVERT_IMAGES=false

case "${ceph_choice,,}" in  # Convert input to lowercase for easy checking
  y|yes)
    # If user says yes => DO NOT convert
    CONVERT_IMAGES=false
    echo "User indicated Ceph usage => skipping image conversions."
    ;;
  n|no)
    # If user says no => CONVERT images
    CONVERT_IMAGES=true
    echo "User indicated NO Ceph usage => will convert Windows & Ubuntu images to QCOW2."
    ;;
  *)
    echo "Invalid choice. Please type yes or no."
    exit 1
    ;;
esac

# --- Define variables ---
CIRROS_URL="https://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img"
WINDOWS_URL="https://xloud.tech/s3/Cloud-images/Windows_Srv_Std_2022_Eval.raw"
UBUNTU_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"

CIRROS_IMG="cirros-0.6.2-x86_64-disk.img"
WINDOWS_RAW="Windows_Srv_Std_2022_Eval.raw"
WINDOWS_QCOW2="Windows_Srv_Std_2022_Eval.qcow2"
UBUNTU_IMG="jammy-server-cloudimg-amd64.img"
UBUNTU_QCOW2="jammy-server-cloudimg-amd64-converted.qcow2"

NETWORK_NAME="Pvt_Net"
SUBNET_NAME="sb_pvt_net"

# Final image/file variables after conversion or not
WINDOWS_FINAL="$WINDOWS_RAW"
WINDOWS_FORMAT="raw"
UBUNTU_FINAL="$UBUNTU_IMG"
UBUNTU_FORMAT="qcow2"  # Official Ubuntu cloud images are typically already QCOW2

# --- Create a temporary directory ---
create_tempdir() {
    echo "Creating temporary directory..."
    mkdir -p openstack_temp
    cd openstack_temp || exit
    echo "Temporary directory 'openstack_temp' created and switched into it."
}

# --- Check prerequisites ---
check_prerequisites() {
    echo "Checking prerequisites..."
    if ! command -v wget &>/dev/null; then
        echo "[INFO] Installing wget..."
        sudo apt-get update && sudo apt-get install -y wget
    fi
    if ! command -v qemu-img &>/dev/null; then
        echo "[INFO] Installing qemu-utils..."
        sudo apt-get update && sudo apt-get install -y qemu-utils
    fi
    if ! command -v openstack &>/dev/null; then
        echo "[INFO] Installing OpenStack CLI via pip..."
        sudo apt-get update && sudo apt-get install -y python3-pip
        pip install --user python-openstackclient
        # Ensure pip's local bin is in the path:
        export PATH="$PATH:$HOME/.local/bin"
    fi
}

# --- Download images ---
download_images() {
    echo "Downloading Cirros image..."
    wget "$CIRROS_URL" -O "$CIRROS_IMG"

    echo "Downloading Windows Server image..."
    wget "$WINDOWS_URL" -O "$WINDOWS_RAW" --no-check-certificate

    echo "Downloading Ubuntu image..."
    wget "$UBUNTU_URL" -O "$UBUNTU_IMG"
}

# --- Convert Windows & Ubuntu images if user said "no" for Ceph ---
convert_images() {
    echo "Converting Windows raw image to qcow2 format..."
    qemu-img convert -p -f raw -O qcow2 "$WINDOWS_RAW" "$WINDOWS_QCOW2"
    WINDOWS_FINAL="$WINDOWS_QCOW2"
    WINDOWS_FORMAT="qcow2"

    echo "Converting Ubuntu image to qcow2 format..."
    # Using '-f qcow2' as input since Ubuntu official is often QCOW2;
    # if it's raw, just change to '-f raw'
    qemu-img convert -p -f qcow2 -O qcow2 "$UBUNTU_IMG" "$UBUNTU_QCOW2"
    UBUNTU_FINAL="$UBUNTU_QCOW2"
    UBUNTU_FORMAT="qcow2"
}

# --- Source OpenStack environment ---
source_openrc() {
    echo "Sourcing OpenStack environment..."
    # Adjust path to your admin-openrc if it's somewhere else
    source /etc/kolla/admin-openrc.sh
}

# --- Upload images to OpenStack ---
upload_images() {
    echo "Uploading Cirros image to OpenStack..."
    openstack image create "cirros-image" \
        --disk-format qcow2 --container-format bare \
        --file "$CIRROS_IMG" \
        --public --progress

    echo "Uploading Windows image to OpenStack..."
    openstack image create "windows-image" \
        --disk-format "$WINDOWS_FORMAT" --container-format bare \
        --file "$WINDOWS_FINAL" \
        --public --progress

    echo "Uploading Ubuntu image to OpenStack..."
    openstack image create "ubuntu-image" \
        --disk-format "$UBUNTU_FORMAT" --container-format bare \
        --file "$UBUNTU_FINAL" \
        --public --progress
}

# --- Create OpenStack flavors ---
create_flavors() {
    echo "Creating OpenStack flavors..."
    # Original
    openstack flavor create tiny --vcpus 1 --ram 1024 --disk 10
    openstack flavor create m1.small --vcpus 1 --ram 2048 --disk 10
    openstack flavor create m1.medium --vcpus 2 --ram 4096 --disk 20

    # New (requested)
    openstack flavor create m1.large --vcpus 4 --ram 8192 --disk 20
    openstack flavor create m1.xlarge --vcpus 8 --ram 16384 --disk 20
}

# --- Create Network & Subnet ---
create_network() {
    echo "Creating OpenStack network..."
    openstack network create "$NETWORK_NAME"
    openstack subnet create --network "$NETWORK_NAME" --subnet-range 12.0.118.0/24 \
        --dns-nameserver 8.8.8.8 --dns-nameserver 1.1.1.1 "$SUBNET_NAME"
}

# --- Create test user & project ---
create_user_and_project() {
    echo "Creating OpenStack project 'test-project' and user 'test'..."
    # Create a new project
    openstack project create test-project

    # Create a new user in that project
    openstack user create --project test-project --password "Test@1" test

    # Assign role (member) so user can actually use the project
    openstack role add --project test-project --user test member

    echo "OpenStack user 'test' was created with password 'Test@1' in project 'test-project'."
}

# --- Cleanup temporary directory ---
destroy() {
    echo "Cleaning up temporary directory..."
    cd ..
    rm -rf ./openstack_temp
}

###############################################################################
#                            MAIN SCRIPT FLOW
###############################################################################
echo "Starting the script..."

# 1. Create and enter temp directory
create_tempdir

# 2. Check or install prerequisites
check_prerequisites

# 3. Download images
download_images

# 4. Convert images only if user answered "no" (i.e., not using Ceph)
if [ "$CONVERT_IMAGES" = true ]; then
    convert_images
fi

# 5. Source OpenStack environment
source_openrc

# 6. Upload images
upload_images

# 7. Create flavors
create_flavors

# 8. Create network
create_network

# 9. Create 'test' user and 'test-project'
create_user_and_project

# 10. Destroy temp directory
destroy

# 11. Final output
echo "Script execution completed successfully!"
echo "New user credentials: username='test', password='Test@1', project='test-project'."
echo "You can now log in as 'test' on the 'test-project' if desired."

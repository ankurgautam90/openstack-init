# OpenStack Image & Environment Setup Script

## Overview

This repository contains a single Bash script (`openstack_init.sh`) that automates several OpenStack setup tasks:

- **Downloads Images:** Cirros, Windows Server 2022 Evaluation, and Ubuntu Jammy.
- **Conditional Conversion:** Converts Windows and Ubuntu images to QCOW2 if Ceph is **not** used.
- **Uploads to OpenStack:** Uploads the images into Glance (OpenStack Image service).
- **Creates Flavors:** Sets up five flavors (`tiny`, `m1.small`, `m1.medium`, `m1.large`, and `m1.xlarge`).
- **Network Creation:** Creates a private network (`Pvt_Net`) and subnet (`sb_pvt_net`).
- **User & Project Setup:** Creates a new project (`test-project`) and user (`test`) with the member role.

## Author and Maintainer

- **Author:** [Ankur Kumar](https://www.linkedin.com/in/ankurgauti/)
- **Maintainer:** [@ankurgautam90](https://github.com/ankurgautam90)


## Assumptions

1. **Operating System:** debian-based distribution (the script uses `apt-get`).
2. **Privileges:** You have `sudo` privileges to install missing dependencies.
3. **OpenStack Environment File:** Located at `/etc/kolla/admin-openrc.sh` (common in Kolla-Ansible setups).
4. **Network Range:** The script creates a subnet `12.0.118.0/24` under the network `Pvt_Net`.
5. **Internet Access:** The system can download images from the specified URLs.


## How to Use

###############################################################################
### 1. Clone the Repository
###############################################################################
```bash
git clone https://github.com/ankurgautam90/openstack-init.git
cd openstack-init
```

###############################################################################
### 2. Make the Script Executable
###############################################################################
```bash
chmod +x openstack_init.sh
```

###############################################################################
### 3. Run the Script
###############################################################################
```bash
./openstack_init.sh
```

The script will prompt:
 "Are you using Ceph with OpenStack for image storage? (Y/N)"
   - Type 'Y' or 'Yes' to skip conversions (Ceph usage).
   - Type 'N' or 'No' to convert Windows and Ubuntu images to QCOW2.

## Verification

After the script completes successfully, you can verify your OpenStack setup using commands like:

```bash
openstack project list
openstack user list
openstack image list
openstack flavor list
openstack network list
```

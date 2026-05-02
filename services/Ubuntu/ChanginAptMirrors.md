# Ubuntu Internal Mirror Setup

This guide and script configure Ubuntu to use the `mirror.cdn.ir` internal repository. It automatically detects if you are using Ubuntu 22.04 and older (`sources.list`) or Ubuntu 24.04 and newer (`ubuntu.sources`), creates a backup of the original configuration, and applies the new mirror addresses.

## Automated Bash Script (`setup-ubuntu-mirror.sh`)

Create a file named `setup-ubuntu-mirror.sh`, paste the following code, make it executable (`chmod +x setup-ubuntu-mirror.sh`), and run it with `sudo`.

```bash
#!/bin/bash
set -e

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (use sudo)"
  exit 1
fi

# Ask user for mirror choice
echo "Select Mirror Configuration:"
echo "1) Default Liara Mirrors"
echo "   - Main: http://linux-mirror.liara.ir/repository/ubuntu/"
echo "   - Security: http://linux-mirror.liara.ir/repository/ubuntu-security/"
echo "2) Custom Mirrors"
read -p "Enter choice [1 or 2, default is 1]: " MIRROR_CHOICE

if [ "$MIRROR_CHOICE" == "2" ]; then
    read -p "Enter Main Mirror URI (e.g., http://mirror.cdn.ir/ubuntu/): " MAIN_MIRROR
    read -p "Enter Security Mirror URI (e.g., http://mirror.cdn.ir/ubuntu-security/): " SECURITY_MIRROR
else
    MAIN_MIRROR="http://linux-mirror.liara.ir/repository/ubuntu/"
    SECURITY_MIRROR="http://linux-mirror.liara.ir/repository/ubuntu-security/"
fi

# Detect Ubuntu version
source /etc/os-release
VERSION_MAJOR=$(echo $VERSION_ID | cut -d'.' -f1)

echo "Detected Ubuntu Version: $VERSION_ID"

# Determine target file based on Ubuntu version
if [ "$VERSION_MAJOR" -ge 24 ]; then
    TARGET_FILE="/etc/apt/sources.list.d/ubuntu.sources"
else
    TARGET_FILE="/etc/apt/sources.list"
fi

if [ ! -f "$TARGET_FILE" ]; then
    echo "Error: Target file $TARGET_FILE does not exist."
    exit 1
fi

# 1. Backup the original file
BACKUP_FILE="${TARGET_FILE}.bak.$(date +%F_%T)"
cp "$TARGET_FILE" "$BACKUP_FILE"
echo "Backed up original sources to: $BACKUP_FILE"

# 2. Modify the addresses by replacing the whole URL/URI
if [ "$VERSION_MAJOR" -ge 24 ]; then
    # For deb822 format (Ubuntu 24.04+) - replaces the whole URIs: line
    sed -i -E "s|URIs: .*archive\.ubuntu\.com.*|URIs: $MAIN_MIRROR|g" "$TARGET_FILE"
    sed -i -E "s|URIs: .*security\.ubuntu\.com.*|URIs: $SECURITY_MIRROR|g" "$TARGET_FILE"
else
    # For traditional sources.list format (Ubuntu 22.04 and older) - replaces the URL part
    sed -i -E "s|https?://[a-zA-Z0-9.-]*archive\.ubuntu\.com[^ ]*|$MAIN_MIRROR|g" "$TARGET_FILE"
    sed -i -E "s|https?://[a-zA-Z0-9.-]*security\.ubuntu\.com[^ ]*|$SECURITY_MIRROR|g" "$TARGET_FILE"
fi

echo "Mirrors successfully updated."
echo "Running apt update..."
apt update -y

```

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

# 2. Modify the addresses
sed -i "s/archive.ubuntu.com/mirror.cdn.ir\/repository/g" "$TARGET_FILE"
sed -i "s/security.ubuntu.com/mirror.cdn.ir\/repository/g" "$TARGET_FILE"

echo "Mirror successfully updated to mirror.cdn.ir/repository."
echo "Running apt update..."
apt update -y
```

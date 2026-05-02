# Docker Installation & Registry Mirror Setup (CDN.ir)

This guide and script install Docker Engine directly from the `cdn.ir` internal repository and configure the Docker daemon to pull images from the `mirror.cdn.ir` registry mirror.

## Automated Bash Script (`setup-docker-mirror.sh`)

Create a file named `setup-docker-mirror.sh`, paste the following code, make it executable (`chmod +x setup-docker-mirror.sh`), and run it with `sudo`.

```bash
#!/bin/bash
set -e

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (use sudo)"
  exit 1
fi

echo "--- 1. Installing Docker from CDN.ir ---"

# Create keyrings directory if it doesn't exist
install -m 0755 -d /etc/apt/keyrings

# Download the GPG key
curl -fsSL https://mirror.cdn.ir/repository/docker/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the Docker repository (deb822 format)
source /etc/os-release
cat <<EOF > /etc/apt/sources.list.d/docker.sources
Types: deb
URIs: https://mirror.cdn.ir/repository/docker/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

# Install Docker packages
apt update -y
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable and start Docker service
systemctl enable docker --now

echo "--- 2. Configuring Docker Registry Mirror ---"

# Create or overwrite daemon.json with registry mirrors
mkdir -p /etc/docker
cat <<EOF > /etc/docker/daemon.json
{
  "registry-mirrors": ["https://mirror.cdn.ir"]
}
EOF

# Reload and restart Docker to apply changes
systemctl daemon-reload
systemctl restart docker

echo "--- Setup Complete! Testing Docker with hello-world ---"
docker pull hello-world
docker run --rm hello-world
```

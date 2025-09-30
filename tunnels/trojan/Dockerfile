# Dockerfile - extend the official trojan image with iptables/ipset and tools
FROM trojangfw/trojan:latest

USER root

# Install iptables / ipset / dns tools - handle both Alpine and Debian-based images
RUN set -eux; \
    if command -v apk >/dev/null 2>&1; then \
        apk add --no-cache iptables ipset bind-tools bash procps; \
    elif command -v apt-get >/dev/null 2>&1; then \
        apt-get update && apt-get install -y --no-install-recommends \
            iptables ipset dnsutils bash procps iproute2 && \
        rm -rf /var/lib/apt/lists/*; \
    else \
        echo "No supported package manager found (apk or apt-get)" >&2; \
        exit 1; \
    fi

# Add startup script
COPY start-with-blocklist.sh /usr/local/bin/start-with-blocklist.sh
RUN chmod +x /usr/local/bin/start-with-blocklist.sh

# Make sure trojan config directory is owned by root (if needed)
# (keep same user as base image at runtime if base runs non-root)
USER 0

# Use our start script as the container entrypoint and default to trojan command
ENTRYPOINT ["/usr/local/bin/start-with-blocklist.sh"]
CMD ["trojan", "-c", "/config/config.json"]

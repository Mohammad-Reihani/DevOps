#!/usr/bin/env bash
set -euo pipefail

BLOCKFILE="/config/blocklist.txt"
IPSET4="blocklist4"
IPSET6="blocklist6"
REFRESH_INTERVAL="${BLOCKLIST_REFRESH_INTERVAL:-300}"  # seconds, default 5min

# Create ipset sets (ignore if exist)
create_ipsets() {
  if ! ipset list "${IPSET4}" >/dev/null 2>&1; then
    ipset create "${IPSET4}" hash:ip family inet hashsize 1024 maxelem 65536 || true
  fi
  if ! ipset list "${IPSET6}" >/dev/null 2>&1; then
    ipset create "${IPSET6}" hash:ip family inet6 hashsize 1024 maxelem 65536 || true
  fi
}

# Ensure iptables rules exist to drop destinations in the ipsets
ensure_iptables_rules() {
  # IPv4: block outgoing to addresses in the ipset
  if ! iptables -C OUTPUT -m set --match-set "${IPSET4}" dst -j REJECT >/dev/null 2>&1; then
    iptables -I OUTPUT 1 -m set --match-set "${IPSET4}" dst -j REJECT || true
  fi
  # IPv6
  if command -v ip6tables >/dev/null 2>&1; then
    if ! ip6tables -C OUTPUT -m set --match-set "${IPSET6}" dst -j REJECT >/dev/null 2>&1; then
      ip6tables -I OUTPUT 1 -m set --match-set "${IPSET6}" dst -j REJECT || true
    fi
  fi
}

# Parse blocklist, resolve hostnames, fill ipsets
update_blocklist() {
  # flush sets (keeps set objects)
  ipset flush "${IPSET4}" || true
  ipset flush "${IPSET6}" || true

  if [ ! -f "${BLOCKFILE}" ]; then
    echo "[blocklist] no blocklist file found at ${BLOCKFILE}"
    return
  fi

  echo "[blocklist] reading ${BLOCKFILE}"
  # Read file line by line
  while IFS= read -r line || [ -n "$line" ]; do
    # Trim whitespace
    entry="$(echo "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    # Skip empty and comments
    [ -z "$entry" ] && continue
    case "$entry" in
      \#*) continue ;;
    esac

    # If entry is IPv4 or IPv6 address, add directly
    if printf '%s' "$entry" | grep -Eiq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
      ipset add -exist "${IPSET4}" "$entry"
      continue
    fi
    if printf '%s' "$entry" | grep -Eiq '^[0-9a-fA-F:]+$'; then
      ipset add -exist "${IPSET6}" "$entry"
      continue
    fi

    # Otherwise assume domain, resolve A and AAAA records using dig
    if command -v dig >/dev/null 2>&1; then
      # A records
      for a in $(dig +short A "$entry" 2>/dev/null || true); do
        [ -z "$a" ] && continue
        ipset add -exist "${IPSET4}" "$a"
      done
      # AAAA records
      for a in $(dig +short AAAA "$entry" 2>/dev/null || true); do
        [ -z "$a" ] && continue
        ipset add -exist "${IPSET6}" "$a"
      done
    else
      # fallback to getent (if available)
      if command -v getent >/dev/null 2>&1; then
        getent ahosts "$entry" | awk '{print $1}' | sort -u | while read -r ip; do
          if printf '%s' "$ip" | grep -Eiq '^[0-9]+\.'; then
            ipset add -exist "${IPSET4}" "$ip"
          else
            ipset add -exist "${IPSET6}" "$ip"
          fi
        done
      else
        echo "[blocklist] no resolver tool (dig/getent) available; can't resolve $entry" >&2
      fi
    fi
  done < "${BLOCKFILE}"
}

# Clean ipsets on exit
cleanup() {
  echo "[blocklist] cleaning up ipsets"
  ipset destroy "${IPSET4}" >/dev/null 2>&1 || true
  ipset destroy "${IPSET6}" >/dev/null 2>&1 || true
  exit 0
}
trap cleanup SIGTERM SIGINT EXIT

# Setup
create_ipsets
ensure_iptables_rules
update_blocklist

# background refresher
(
  while true; do
    sleep "${REFRESH_INTERVAL}"
    echo "[blocklist] refreshing at $(date -Is)"
    update_blocklist || true
  done
) &

# Finally exec the real trojan command (passed in via CMD or override)
echo "[entrypoint] starting trojan (exec $@)"
exec "$@"

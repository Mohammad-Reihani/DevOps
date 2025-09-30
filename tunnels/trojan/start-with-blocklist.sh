#!/usr/bin/env bash
set -euo pipefail

BLOCKFILE="/config/blocklist.txt"
IPSET4="blocklist4"
IPSET6="blocklist6"
REFRESH_INTERVAL="${BLOCKLIST_REFRESH_INTERVAL:-300}"

log(){ echo "[$(date -Is)] $*"; }

# validators
is_ipv4(){
  local ip="$1"
  printf '%s' "$ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' || return 1
  IFS='.' read -r a b c d <<<"$ip"
  for o in "$a" "$b" "$c" "$d"; do
    [ "$o" -gt 255 ] 2>/dev/null && return 1
  done
  return 0
}
is_private_ipv4(){
  local ip="$1"
  # RFC1918, loopback, link-local, multicast, broadcast
  case "$ip" in
    127.*|10.*|192.168.*|169.254.*) return 0 ;;
  esac
  # 172.16.0.0 - 172.31.255.255
  if printf '%s' "$ip" | grep -Eq '^172\.([1][6-9]|2[0-9]|3[0-1])\.'; then return 0; fi
  # multicast 224.0.0.0/4
  if printf '%s' "$ip" | grep -Eq '^22[4-9]\.|^23[0-9]\.'; then return 0; fi
  return 1
}
is_ipv6(){
  local ip="$1"
  printf '%s' "$ip" | grep -Eq ':' || return 1
  return 0
}
is_private_ipv6(){
  local ip="$1"
  # local checks: ::1, fc00::/7, fe80::/10, ff00::/8
  case "$ip" in
    ::1|fe80::*|ff* ) return 0 ;;
  esac
  if printf '%s' "$ip" | grep -Eq '^(fc|fd)'; then return 0; fi
  return 1
}

# create ipsets
create_ipsets(){
  if ! ipset list "$IPSET4" >/dev/null 2>&1; then
    log "creating $IPSET4"
    ipset create "$IPSET4" hash:ip family inet hashsize 1024 maxelem 65536 || true
  fi
  if ! ipset list "$IPSET6" >/dev/null 2>&1; then
    log "creating $IPSET6"
    ipset create "$IPSET6" hash:ip family inet6 hashsize 1024 maxelem 65536 || true
  fi
}

# allow essential traffic (put at top)
ensure_allow_rules(){
  # loopback
  if ! iptables -C OUTPUT -o lo -j ACCEPT >/dev/null 2>&1; then
    log "allowing loopback (OUTPUT -o lo ACCEPT)"
    iptables -I OUTPUT 1 -o lo -j ACCEPT || true
  fi
  # DNS UDP/TCP
  if ! iptables -C OUTPUT -p udp --dport 53 -j ACCEPT >/dev/null 2>&1; then
    log "allowing UDP dport 53"
    iptables -I OUTPUT 1 -p udp --dport 53 -j ACCEPT || true
  fi
  if ! iptables -C OUTPUT -p tcp --dport 53 -j ACCEPT >/dev/null 2>&1; then
    log "allowing TCP dport 53"
    iptables -I OUTPUT 1 -p tcp --dport 53 -j ACCEPT || true
  fi

  # explicit allow for resolvers from /etc/resolv.conf
  if [ -r /etc/resolv.conf ]; then
    awk '/^nameserver/ { print $2 }' /etc/resolv.conf | while read -r ns; do
      [ -z "$ns" ] && continue
      if is_ipv4 "$ns"; then
        if ! iptables -C OUTPUT -d "$ns" -p udp --dport 53 -j ACCEPT >/dev/null 2>&1; then
          log "allowing DNS server $ns"
          iptables -I OUTPUT 1 -d "$ns" -p udp --dport 53 -j ACCEPT || true
          iptables -I OUTPUT 1 -d "$ns" -p tcp --dport 53 -j ACCEPT || true
        fi
      else
        if command -v ip6tables >/dev/null 2>&1; then
          if ! ip6tables -C OUTPUT -d "$ns" -p udp --dport 53 -j ACCEPT >/dev/null 2>&1; then
            log "allowing IPv6 DNS server $ns"
            ip6tables -I OUTPUT 1 -d "$ns" -p udp --dport 53 -j ACCEPT || true
            ip6tables -I OUTPUT 1 -d "$ns" -p tcp --dport 53 -j ACCEPT || true
          fi
        fi
      fi
    done
  fi
}

# append REJECT rules (after allow)
ensure_iptables_rules(){
  ensure_allow_rules
  if ! iptables -C OUTPUT -m set --match-set "$IPSET4" dst -j REJECT >/dev/null 2>&1; then
    log "appending REJECT rule for $IPSET4"
    iptables -A OUTPUT -m set --match-set "$IPSET4" dst -j REJECT || true
  fi
  if command -v ip6tables >/dev/null 2>&1; then
    if ! ip6tables -C OUTPUT -m set --match-set "$IPSET6" dst -j REJECT >/dev/null 2>&1; then
      log "appending REJECT rule for $IPSET6"
      ip6tables -A OUTPUT -m set --match-set "$IPSET6" dst -j REJECT || true
    fi
  fi
}

# MAIN updater: only add real IPs, filter private/reserved
update_blocklist(){
  log "update_blocklist: reading $BLOCKFILE"
  [ -f "$BLOCKFILE" ] || { log "no blocklist file"; return; }

  # flush existing entries, keep sets
  ipset flush "$IPSET4" >/dev/null 2>&1 || true
  ipset flush "$IPSET6" >/dev/null 2>&1 || true

  local total
  total=$(grep -E -v '^[[:space:]]*(#|$)' "$BLOCKFILE" | wc -l || true)
  log "update_blocklist: $total entries"

  local processed=0 added4=0 added6=0
  while IFS= read -r raw || [ -n "$raw" ]; do
    line="$(printf '%s' "$raw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac

    processed=$((processed+1))

    # If an IP literal, add after checks
    if is_ipv4 "$line"; then
      is_private_ipv4 "$line" && { log "skipping private/reserved ipv4 $line"; continue; }
      ipset add -exist "$IPSET4" "$line" && added4=$((added4+1)) || log "ipset add failed $line"
      continue
    fi
    if is_ipv6 "$line"; then
      is_private_ipv6 "$line" && { log "skipping private/reserved ipv6 $line"; continue; }
      ipset add -exist "$IPSET6" "$line" && added6=$((added6+1)) || log "ipset add failed $line"
      continue
    fi

    # Domain: resolve with dig +short (returns only IPs) -- bounded timeout & attempts
    if command -v dig >/dev/null 2>&1; then
      # A records
      mapfile -t a_ips < <(dig +short +time=2 +tries=1 A "$line" 2>/dev/null || true)
      for ip in "${a_ips[@]}"; do
        [ -z "$ip" ] && continue
        if is_ipv4 "$ip"; then
          is_private_ipv4 "$ip" && { log "skipping private/reserved resolved ipv4 $ip for $line"; continue; }
          ipset add -exist "$IPSET4" "$ip" && added4=$((added4+1)) || log "ipset add failed $ip (from $line)"
        fi
      done

      # AAAA records
      mapfile -t a6_ips < <(dig +short +time=2 +tries=1 AAAA "$line" 2>/dev/null || true)
      for ip in "${a6_ips[@]}"; do
        [ -z "$ip" ] && continue
        if is_ipv6 "$ip"; then
          is_private_ipv6 "$ip" && { log "skipping private/reserved resolved ipv6 $ip for $line"; continue; }
          ipset add -exist "$IPSET6" "$ip" && added6=$((added6+1)) || log "ipset add failed $ip (from $line)"
        fi
      done
    else
      # getent fallback (less preferred)
      getent ahosts "$line" | awk '{print $1}' | sort -u | while read -r ip; do
        if is_ipv4 "$ip"; then
          is_private_ipv4 "$ip" && continue
          ipset add -exist "$IPSET4" "$ip" && added4=$((added4+1)) || log "ipset add failed $ip (getent)"
        elif is_ipv6 "$ip"; then
          is_private_ipv6 "$ip" && continue
          ipset add -exist "$IPSET6" "$ip" && added6=$((added6+1)) || log "ipset add failed $ip (getent)"
        fi
      done
    fi
  done < "$BLOCKFILE"

  log "update_blocklist: processed=$processed, added4=$added4, added6=$added6"
}

cleanup(){
  log "cleanup: destroy ipsets"
  ipset destroy "$IPSET4" >/dev/null 2>&1 || true
  ipset destroy "$IPSET6" >/dev/null 2>&1 || true
  exit 0
}
trap cleanup SIGTERM SIGINT

# startup
log "startup: blocklist engine starting"
create_ipsets
ensure_iptables_rules

# background initial update
( log "background initial update starting"; update_blocklist || log "initial update failed" ) &

# periodic refresher
( while true; do sleep "$REFRESH_INTERVAL"; log "scheduled refresh"; update_blocklist || log "refresh failed"; done ) &

# exec trojan
if [ "$#" -gt 0 ]; then
  log "exec: $*"
  exec "$@"
else
  log "exec: trojan -c /config/config.json"
  exec trojan -c /config/config.json
fi

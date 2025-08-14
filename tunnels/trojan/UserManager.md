# UserManager

We are not doing massive user management system, just a helper script will suffice. now if you did the basic setup with me, you can follow here.

its so easy, first install this:

```bash
sudo apt update
sudo apt install -y jq openssl
```

then copy this in your desired location:

```bash
#!/usr/bin/env bash
set -euo pipefail

# ============ CONFIG =============
CONFIG_PATH="/etc/trojan/config.json"
USERS_MAP="/etc/trojan/users.json"
BACKUP_DIR="/etc/trojan/backups"
DOCKER_COMPOSE_PATH="/opt/trojan/docker-compose.yml"   # adjust if needed
CONTAINER_NAME="trojan"

# Default hostname used in printed URIs (no per-run prompt)
DEFAULT_HOSTNAME="vpn.your.domain"    # <-- set your domain here (no prompt anymore)

# Default password length; user will be prompted and can accept this by pressing ENTER
DEFAULT_PW_LEN=32

# Colors (nice & consistent)
CLR_RESET="\e[0m"
CLR_BOLD="\e[1m"
CLR_OK="\e[1;32m"
CLR_WARN="\e[1;33m"
CLR_ERR="\e[1;31m"
CLR_INFO="\e[1;36m"
CLR_TITLE="\e[1;35m"

# ============ Helpers =============
die(){ echo -e "${CLR_ERR}[ERROR]${CLR_RESET} $*" >&2; exit 1; }
info(){ echo -e "${CLR_OK}[INFO]${CLR_RESET} $*"; }
warn(){ echo -e "${CLR_WARN}[WARN]${CLR_RESET} $*"; }
title(){ echo -e "${CLR_TITLE}${CLR_BOLD}$*${CLR_RESET}"; }

ensure_paths(){
  mkdir -p "$(dirname "$CONFIG_PATH")"
  mkdir -p "$BACKUP_DIR"
  if [ ! -f "$CONFIG_PATH" ]; then
    die "Config not found at $CONFIG_PATH"
  fi
  if ! command -v jq >/dev/null 2>&1; then
    die "jq not found. Install with: sudo apt install -y jq"
  fi
}

backup_config(){
  ts=$(date -u +%Y%m%d%H%M%S)
  cp -a "$CONFIG_PATH" "$BACKUP_DIR/config.json.bak.$ts"
  info "Backed up config to $BACKUP_DIR/config.json.bak.$ts"
}

restart_trojan(){
  if [ -f "$DOCKER_COMPOSE_PATH" ]; then
    if command -v docker >/dev/null 2>&1 && docker compose -f "$DOCKER_COMPOSE_PATH" version >/dev/null 2>&1; then
      info "Restarting trojan via docker compose..."
      docker compose -f "$DOCKER_COMPOSE_PATH" restart "$CONTAINER_NAME" || warn "docker compose restart failed"
      return
    fi
  fi
  if command -v docker >/dev/null 2>&1; then
    info "Restarting container $CONTAINER_NAME..."
    docker restart "$CONTAINER_NAME" >/dev/null 2>&1 || warn "docker restart failed"
    return
  fi
  warn "Could not restart container automatically. Please run 'docker compose -f $DOCKER_COMPOSE_PATH restart $CONTAINER_NAME' or 'docker restart $CONTAINER_NAME'"
}

load_users(){
  if [ -f "$USERS_MAP" ]; then
    if ! jq empty "$USERS_MAP" >/dev/null 2>&1; then
      warn "Invalid JSON in $USERS_MAP — resetting file."
      echo '{}' > "$USERS_MAP"
    fi
  else
    echo '{}' > "$USERS_MAP"
  fi
}

rand_password(){
  # generate base64-ish password and trim to requested length
  local len=${1:-32}
  # openssl produces base64; strip =+/ and cut to length
  openssl rand -base64 $(( (len*3)/4 + 4 )) | tr -d '=+/ ' | cut -c1-"$len"
}

# ============ UI / Actions =============
list_clients(){
  title "Trojan users"
  if [ ! -f "$USERS_MAP" ]; then
    echo "(no users)"
    return
  fi
  local keys
  keys=$(jq -r 'keys[]?' "$USERS_MAP" 2>/dev/null || true)
  if [ -z "$keys" ]; then
    echo "(no users)"
    return
  fi
  printf "%-20s %-22s %-30s\n" "NAME" "CREATED (UTC)" "COMMENT"
  printf "%-20s %-22s %-30s\n" "----" "--------------" "-------"
  while IFS= read -r k; do
    created=$(jq -r --arg k "$k" '.[$k].created_at // "?"' "$USERS_MAP")
    comment=$(jq -r --arg k "$k" '.[$k].comment // ""' "$USERS_MAP")
    # truncate comment for display
    if [ ${#comment} -gt 28 ]; then
      comment="${comment:0:27}…"
    fi
    printf "${CLR_INFO}%-20s${CLR_RESET} %-22s %-30s\n" "$k" "$created" "$comment"
  done <<< "$keys"
}

add_client(){
  read -rp "Client name (id): " name
  name=$(echo "$name" | tr -d '[:space:]')
  [ -z "$name" ] && { echo "aborted"; return; }
  if jq -e --arg n "$name" '.[$n] // empty' "$USERS_MAP" >/dev/null; then
    warn "User '$name' already exists."
    return
  fi

  # password length prompt with default
  read -rp "Password length [${DEFAULT_PW_LEN}]: " plen
  plen=$(echo "$plen" | tr -d '[:space:]')
  if [ -z "$plen" ]; then
    plen=$DEFAULT_PW_LEN
  fi
  if ! [[ "$plen" =~ ^[0-9]+$ ]] || [ "$plen" -lt 8 ] || [ "$plen" -gt 128 ]; then
    warn "Invalid length; using default ${DEFAULT_PW_LEN}."
    plen=$DEFAULT_PW_LEN
  fi

  read -rp "Comment (optional): " comment

  pwd=$(rand_password "$plen")
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  backup_config

  # add to trojan config.json: ensure .password exists then append
  tmp=$(mktemp)
  jq --arg p "$pwd" '(.password //= []) | (.password += [$p])' "$CONFIG_PATH" > "$tmp" && mv "$tmp" "$CONFIG_PATH"
  info "Added password to $CONFIG_PATH"

  # add to users map with optional comment
  tmp2=$(mktemp)
  jq --arg n "$name" --arg p "$pwd" --arg t "$ts" --arg c "$comment" '. + {($n): {password:$p, created_at:$t, comment:$c}}' "$USERS_MAP" > "$tmp2" && mv "$tmp2" "$USERS_MAP"
  info "Added user '$name' to $USERS_MAP"

  echo
  info "User $name added."
  echo -e " ${CLR_BOLD}Password:${CLR_RESET} ${CLR_INFO}$pwd${CLR_RESET}"
  if [ -n "$DEFAULT_HOSTNAME" ] && [ "$DEFAULT_HOSTNAME" != "vpn.your.domain" ]; then
    echo -e " ${CLR_BOLD}URI:${CLR_RESET} ${CLR_OK}trojan://$pwd@$DEFAULT_HOSTNAME:443${CLR_RESET}"
  else
    echo -e " ${CLR_WARN}DEFAULT_HOSTNAME is not set/edited in script. Set DEFAULT_HOSTNAME at top to auto-print URIs.${CLR_RESET}"
  fi

  restart_trojan
}

delete_client(){
  read -rp "Client name to delete: " name
  name=$(echo "$name" | tr -d '[:space:]')
  [ -z "$name" ] && { echo "aborted"; return; }
  if ! jq -e --arg n "$name" '.[$n] // empty' "$USERS_MAP" >/dev/null; then
    warn "User '$name' not found."
    return
  fi
  pwd=$(jq -r --arg n "$name" '.[$n].password' "$USERS_MAP")
  read -rp "Type DELETE to confirm deletion of $name: " confirm
  if [ "$confirm" != "DELETE" ]; then
    echo "aborted."
    return
  fi
  backup_config

  # remove password from config.json
  tmp=$(mktemp)
  jq --arg p "$pwd" '( .password // [] ) | map(select(. != $p)) as $new | .password = $new' "$CONFIG_PATH" > "$tmp" && mv "$tmp" "$CONFIG_PATH"
  info "Removed password from $CONFIG_PATH (if it existed)"

  # remove from users map
  tmp2=$(mktemp)
  jq --arg n "$name" 'del(.[$n])' "$USERS_MAP" > "$tmp2" && mv "$tmp2" "$USERS_MAP"
  info "Removed user '$name' from $USERS_MAP"

  restart_trojan
  info "Deleted $name"
}

view_client(){
  read -rp "Client name to view: " name
  name=$(echo "$name" | tr -d '[:space:]')
  [ -z "$name" ] && { echo "aborted"; return; }
  if ! jq -e --arg n "$name" '.[$n] // empty' "$USERS_MAP" >/dev/null; then
    warn "User '$name' not found."
    return
  fi
  pwd=$(jq -r --arg n "$name" '.[$n].password' "$USERS_MAP")
  created=$(jq -r --arg n "$name" '.[$n].created_at' "$USERS_MAP")
  comment=$(jq -r --arg n "$name" '.[$n].comment // ""' "$USERS_MAP")
  title "User: $name"
  echo -e " ${CLR_BOLD}Password:${CLR_RESET} ${CLR_INFO}$pwd${CLR_RESET}"
  echo -e " ${CLR_BOLD}Created:${CLR_RESET} $created"
  if [ -n "$comment" ]; then
    echo -e " ${CLR_BOLD}Comment:${CLR_RESET} $comment"
  fi
  if [ -n "$DEFAULT_HOSTNAME" ] && [ "$DEFAULT_HOSTNAME" != "vpn.your.domain" ]; then
    echo -e "\n ${CLR_BOLD}URI:${CLR_RESET} ${CLR_OK}trojan://$pwd@$DEFAULT_HOSTNAME:443${CLR_RESET}"
  else
    echo -e "\n ${CLR_WARN}DEFAULT_HOSTNAME is not set/edited in script. Set it at top to auto-print URIs.${CLR_RESET}"
  fi
}

show_menu(){
  cat <<'EOF'

${CLR_TITLE}${CLR_BOLD} Trojan User Manager ${CLR_RESET}

1) View clients names
2) Add client
3) Delete client
4) View one client settings
5) Exit

EOF
}

main(){
  if [ "$(id -u)" -ne 0 ]; then
    die "Run as root (sudo). This script writes /etc/trojan and restarts container."
  fi
  ensure_paths
  load_users
  while true; do
    show_menu
    read -rp "Choice: " choice
    case "$choice" in
      1) list_clients ;;
      2) add_client ;;
      3) delete_client ;;
      4) view_client ;;
      5) exit 0 ;;
      *) echo "unknown choice" ;;
    esac
    echo
  done
}

# run
main
SH
```

and finally:

```bash
# make executable
sudo chmod +x /usr/local/bin/trojan_user_manager.sh

# run it
sudo /usr/local/bin/trojan_user_manager.sh
```

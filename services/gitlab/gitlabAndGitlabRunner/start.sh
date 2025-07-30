#!/bin/bash
if [ -z "$BASH_VERSION" ]; then exec bash "$0" "$@"; fi

# =============================================================
# Step 2. Define Environment Variables
# -------------------------------------------------------------
# Please ensure the following environment variables are defined in your ~/.bashrc file:
#
#   # Gitlab Related
#   export GITLAB_HOME=/opt/gitlab
#   export GITLAB_RUNNER_HOME=/opt/gitlab-runner
#   export HOST_IP=$(hostname -I | awk '{print $1}')  # gets first non-loopback IP
#
# To add them, run:
#   echo -e '\n# Gitlab Related\nexport GITLAB_HOME=/opt/gitlab\nexport GITLAB_RUNNER_HOME=/opt/gitlab-runner\nexport HOST_IP=$(hostname -I | awk '{print $1}')' >> ~/.bashrc
#   source ~/.bashrc
#
# This script will now check if these variables are set and guide you if not.
# =============================================================

# Detect the invoking user's home and bashrc
if [ "$SUDO_USER" ]; then
  INVOKING_USER="$SUDO_USER"
else
  INVOKING_USER="$USER"
fi
INVOKING_HOME=$(eval echo "~${INVOKING_USER}")
BASHRC_FILE="$INVOKING_HOME/.bashrc"

if [ "$EUID" -eq 0 ] && [ -f "$BASHRC_FILE" ]; then
  set -a
  . "$BASHRC_FILE"
  set +a
fi




# Prompt for GITLAB_PORT if not set
DEFAULT_GITLAB_PORT=8998
if [ -z "$GITLAB_PORT" ]; then
    read -p "Enter the port you want GitLab to use (default: $DEFAULT_GITLAB_PORT): " USER_PORT
    if [ -z "$USER_PORT" ]; then
        GITLAB_PORT=$DEFAULT_GITLAB_PORT
    else
        GITLAB_PORT=$USER_PORT
    fi
    echo -e "\033[1;33m[INFO]\033[0m Using GitLab port: $GITLAB_PORT"
fi

# Prompt for HOST_IP if not set or to confirm/change
if [ -z "$HOST_IP" ]; then
    DETECTED_HOST_IP=$(hostname -I | awk '{print $1}')
else
    DETECTED_HOST_IP="$HOST_IP"
fi
read -p "Detected HOST_IP is '$DETECTED_HOST_IP'. Press Enter to accept or enter a new value: " USER_HOST_IP
if [ -z "$USER_HOST_IP" ]; then
    HOST_IP="$DETECTED_HOST_IP"
else
    HOST_IP="$USER_HOST_IP"
fi
echo -e "\033[1;33m[INFO]\033[0m Using HOST_IP: $HOST_IP"


# POSIX-compatible env check and append
MISSING_ENV=""
ADDED_ENV=""



# Safely update ~/.bashrc only as the user, not as root
append_or_update_bashrc() {
  local VAR_NAME="$1"
  local VAR_VALUE="$2"

  if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    # As root: drop privileges to writing user so ownership stays intact
    sudo -u "$INVOKING_USER" sh -c "
      sed -i -E '/^(export[[:space:]]+)?${VAR_NAME}=/d' \"$BASHRC_FILE\"
      printf '\nexport %s=\"%s\"\n' '${VAR_NAME}' '${VAR_VALUE}' >> \"$BASHRC_FILE\"
    "
  else
    # Running as non-root or directly as the user
    sed -i -E '/^(export[[:space:]]+)?'"$VAR_NAME"='/d' "$BASHRC_FILE"
    printf '\nexport %s="%s"\n' "$VAR_NAME" "$VAR_VALUE" >> "$BASHRC_FILE"
  fi

  # 3) Export in the current shell
  export "$VAR_NAME"="$VAR_VALUE"
  ADDED_ENV="$ADDED_ENV $VAR_NAME"
}


[ -z "$GITLAB_HOME" ] && MISSING_ENV="$MISSING_ENV GITLAB_HOME"
[ -z "$GITLAB_RUNNER_HOME" ] && MISSING_ENV="$MISSING_ENV GITLAB_RUNNER_HOME"
[ -z "$HOST_IP" ] && MISSING_ENV="$MISSING_ENV HOST_IP"
MISSING_ENV="$MISSING_ENV GITLAB_PORT" # Always write GITLAB_PORT

if [ -n "$MISSING_ENV" ]; then
    echo -e "\033[1;33m[INFO]\033[0m The following environment variables are not set: $MISSING_ENV"
    echo -e "\033[1;33m[INFO]\033[0m Adding missing variables to $BASHRC_FILE..."
    for VAR in $MISSING_ENV; do
        case "$VAR" in
            GITLAB_HOME)
                append_or_update_bashrc "GITLAB_HOME" "${GITLAB_HOME:-/opt/gitlab}"
                ;;
            GITLAB_RUNNER_HOME)
                append_or_update_bashrc "GITLAB_RUNNER_HOME" "${GITLAB_RUNNER_HOME:-/opt/gitlab-runner}"
                ;;
            HOST_IP)
                append_or_update_bashrc "HOST_IP" "$HOST_IP"
                ;;
            GITLAB_PORT)
                append_or_update_bashrc "GITLAB_PORT" "$GITLAB_PORT"
                ;;
        esac
    done
    if [ -n "$ADDED_ENV" ]; then
        echo -e "\033[0;32m[OK]\033[0m Added:$ADDED_ENV to $BASHRC_FILE."
        echo -e "\033[1;33m[INFO]\033[0m Exported missing variables for this session. Continuing..."
    else
        echo -e "\033[1;33m[INFO]\033[0m No new variables were added. Please check $BASHRC_FILE."
    fi
    # Continue script without exit since we exported variables for this session
else
    echo -e "\033[0;32m[OK]\033[0m All required environment variables are set."
fi

# Define the network name
NETWORK_NAME="gitlab-net"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

# Function to print messages with color
print_message() {
    local message=$1
    local color=$2
    echo -e "${color}${message}${RESET}"
}


# Require root privileges
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m[ERROR]\033[0m This script must be run as root."
    echo -e "\033[1;33m[INFO]\033[0m Please run: sudo $0"
    exit 1
fi

# Check if the network exists
if ! docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}$"; then
    print_message "🔧 Creating Docker network: $NETWORK_NAME" "$YELLOW"
    docker network create "$NETWORK_NAME"
    if [[ $? -eq 0 ]]; then
        print_message "✅ Docker network '$NETWORK_NAME' created successfully." "$GREEN"
    else
        print_message "❌ Failed to create Docker network '$NETWORK_NAME'." "$RED"
        exit 1
    fi
else
    print_message "✅ Docker network '$NETWORK_NAME' already exists." "$GREEN"
fi

# Detect which compose command to use
if command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
elif docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
else
    print_message "❌ Neither 'docker-compose' nor 'docker compose' is available. Please install Docker Compose." "$RED"
    exit 1
fi


# Write .env file for docker-compose THIS IS NOT NEEDED ANYMORE BUT WE ARE DOING IT JUST IN CASE...
cat > .env <<EOF
GITLAB_HOME=$GITLAB_HOME
GITLAB_RUNNER_HOME=$GITLAB_RUNNER_HOME
HOST_IP=$HOST_IP
GITLAB_PORT=$GITLAB_PORT
EOF

print_message "🚀 Bringing up the Docker Compose stack..." "$YELLOW"
$COMPOSE_CMD up -d
if [[ $? -eq 0 ]]; then
    print_message "✅ Docker Compose stack is up and running." "$GREEN"
else
    print_message "❌ Failed to bring up the Docker Compose stack." "$RED"
    exit 1
fi

# Restart the GitLab Runner service
print_message "🔧 Restarting GitLab Runner service..." "$YELLOW"
docker exec gitlab-runner gitlab-runner restart
if [[ $? -eq 0 ]]; then
    print_message "✅ GitLab Runner service restarted successfully." "$GREEN"
else
    print_message "❌ Failed to restart GitLab Runner service." "$RED"
    exit 1
fi
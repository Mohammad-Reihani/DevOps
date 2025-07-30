
#!/bin/bash

# =============================================================
# Step 2. Define Environment Variables
# -------------------------------------------------------------
# Please ensure the following environment variables are defined in your ~/.bashrc file:
#
#   # Gitlab Related
#   export GITLAB_HOME=/srv/gitlab
#   export GITLAB_RUNNER_HOME=/srv/gitlab-runner
#   export HOST_IP=$(hostname -I | awk '{print $1}')  # gets first non-loopback IP
#
# To add them, run:
#   echo -e '\n# Gitlab Related\nexport GITLAB_HOME=/srv/gitlab\nexport GITLAB_RUNNER_HOME=/srv/gitlab-runner\nexport HOST_IP=$(hostname -I | awk '{print $1}')' >> ~/.bashrc
#   source ~/.bashrc
#
# This script will now check if these variables are set and guide you if not.
# =============================================================

# Check for required environment variables and add them to ~/.bashrc if missing
missing_env=()
added_env=()

# Helper to append to bashrc if not present
append_if_missing() {
    local var_name=$1
    local var_value=$2
    local bashrc=~/.bashrc
    if ! grep -q "^export $var_name=" "$bashrc"; then
        echo "export $var_name=$var_value" >> "$bashrc"
        added_env+=("$var_name")
    fi
}

[ -z "$GITLAB_HOME" ] && missing_env+=("GITLAB_HOME")
[ -z "$GITLAB_RUNNER_HOME" ] && missing_env+=("GITLAB_RUNNER_HOME")
[ -z "$HOST_IP" ] && missing_env+=("HOST_IP")

if [ ${#missing_env[@]} -ne 0 ]; then
    echo -e "\033[1;33m[INFO]\033[0m The following environment variables are not set: ${missing_env[*]}"
    echo -e "\033[1;33m[INFO]\033[0m Adding missing variables to your ~/.bashrc..."
    for var in "${missing_env[@]}"; do
        case "$var" in
            GITLAB_HOME)
                append_if_missing "GITLAB_HOME" "/srv/gitlab"
                ;;
            GITLAB_RUNNER_HOME)
                append_if_missing "GITLAB_RUNNER_HOME" "/srv/gitlab-runner"
                ;;
            HOST_IP)
                append_if_missing "HOST_IP" "$(hostname -I | awk '{print $1}')"
                ;;
        esac
    done
    if [ ${#added_env[@]} -ne 0 ]; then
        echo -e "\033[0;32m[OK]\033[0m Added: ${added_env[*]} to ~/.bashrc."
        echo -e "\033[1;33m[INFO]\033[0m Please run: `source ~/.bashrc`, OR restart your terminal then re-run this script."
    else
        echo -e "\033[1;33m[INFO]\033[0m No new variables were added. Please check your ~/.bashrc."
    fi
    exit 1
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

# Start the Compose stack
print_message "🚀 Bringing up the Docker Compose stack..." "$YELLOW"
docker-compose up -d
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
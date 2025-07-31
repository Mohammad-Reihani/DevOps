#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Simple HTTP File Server Launcher
#
# Prompts for a directory, duration, port, and mode (tmux or background),
# then serves the specified directory over HTTP on 0.0.0.0:<port>.
# - Mode 1: Runs inside a detached tmux session for interactive logs.
# - Mode 2: Runs in the background with an auto‐kill timer.
# Provides clear PID/session info and instructions for stopping the server.
# -----------------------------------------------------------------------------
set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
CYAN="\e[1;36m"
RED="\e[1;31m"
RESET="\e[0m"

# ─── Prompts ──────────────────────────────────────────────────────────
printf "${CYAN}📂 Directory to serve (default: current dir): ${RESET}"
read -r SERVE_DIR
SERVE_DIR=${SERVE_DIR:-$(pwd)}

if [ ! -d "$SERVE_DIR" ]; then
  printf "${RED}✖ Directory does not exist: %s${RESET}\n" "$SERVE_DIR"
  exit 1
fi

printf "${CYAN}⏱ How many minutes should the server run? ${RESET}"
read -r MINUTES

printf "${CYAN}🌐 Port to serve on (default 8000): ${RESET}"
read -r PORT
PORT=${PORT:-8000}

printf "${CYAN}Choose mode:\n"
printf "  1) tmux session (auto-kill)\n"
printf "  2) background timer (auto-kill)\n"
printf "${CYAN}Enter 1 or 2: ${RESET}"
read -r MODE

# ─── Mode Handling ────────────────────────────────────────────────────
case "$MODE" in
  1)
    # tmux mode
    if ! command -v tmux &>/dev/null; then
      printf "${RED}✖ tmux not found! Install with: sudo apt install tmux${RESET}\n"
      exit 1
    fi

    SESSION="websrv_$$"
    printf "${YELLOW}▶ Creating tmux session '%s'…${RESET}\n" "$SESSION"
    tmux new-session -d -s "$SESSION" \
      "cd '$SERVE_DIR' && python3 -m http.server $PORT --bind 0.0.0.0"

    printf "${GREEN}✔ Server running in tmux session:${RESET} %s\n" "$SESSION"
    printf "  ${CYAN}Attach:${RESET} tmux attach -t %s\n" "$SESSION"
    printf "  ${CYAN}Kill:  ${RESET}tmux kill-session -t %s\n" "$SESSION"
    printf "${YELLOW}⏲ Will auto-kill tmux session in %d minute(s)…${RESET}\n" "$MINUTES"

    # ─── Auto‐kill the tmux session after the timeout ─────────────────────────
    # Launch a detached killer that survives shell exit
    nohup bash -c " \
      sleep $(( MINUTES * 60 )); \
      printf '\n\033[1;31m⏹ Timer expired: killing tmux session $SESSION\033[0m\n'; \
      tmux kill-session -t $SESSION 2>/dev/null || true \
    " >/dev/null 2>&1 &
    ;;
  2)
    # background timer mode
    printf "${YELLOW}▶ Serving '%s' in background…${RESET}\n" "$SERVE_DIR"
    nohup bash -c "cd '$SERVE_DIR' && python3 -m http.server $PORT --bind 0.0.0.0" \
      > webserver.log 2>&1 &
    SERVER_PID=$!
    printf "${GREEN}✔ Server PID:${RESET} ${CYAN}%d${RESET}\n" "$SERVER_PID"
    printf "  ${CYAN}Kill manually:${RESET} kill %d\n" "$SERVER_PID"
    printf "${YELLOW}⏲ Will auto-kill in %d minute(s)…${RESET}\n" "$MINUTES"

    # Timer to kill
    nohup bash -c " \
      sleep $(( MINUTES * 60 )); \
      printf '\n\033[1;31m⏹ Timer expired: killing PID $SERVER_PID\033[0m\n'; \
      kill $SERVER_PID 2>/dev/null || true \
    " >/dev/null 2>&1 &
    ;;
  *)
    printf "${RED}✖ Invalid choice. Exiting.${RESET}\n"
    exit 1
    ;;
esac

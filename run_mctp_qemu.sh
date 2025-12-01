#!/usr/bin/env bash
# Launch both MCTP QEMU instances in a tmux session (host first, then endpoint).
set -euo pipefail

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux is required for this helper. Install tmux and retry." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_NAME="mctp_qemu"
NETWORK_ARGS="${DOCKER_EXTRA_ARGS:---network host}"
PORT="${MCTP_PORT:-4321}"

echo "Starting tmux session '${SESSION_NAME}' with MCTP_PORT=${PORT} and DOCKER_EXTRA_ARGS=${NETWORK_ARGS}"

# Start the host (listener) first so the endpoint can reconnect to it.
tmux new-session -d -s "${SESSION_NAME}" \
  "cd '${ROOT_DIR}' && DOCKER_EXTRA_ARGS='${NETWORK_ARGS}' MCTP_PORT=${PORT} ./setup.sh qemu-test -d build/mctp_host"

# Split horizontally and start the endpoint (client) in the new pane.
tmux split-window -h -t "${SESSION_NAME}:0" \
  "cd '${ROOT_DIR}' && DOCKER_EXTRA_ARGS='${NETWORK_ARGS}' MCTP_PORT=${PORT} ./setup.sh qemu-test -d build/mctp_endpoint"

tmux select-pane -t "${SESSION_NAME}:0.0"
tmux attach -t "${SESSION_NAME}"

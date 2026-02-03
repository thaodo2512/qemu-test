#!/bin/bash
set -e

# --- CONFIGURATION ---
DEFAULT_APP_PATH="zephyr/samples/subsys/pmci/pldm"
BUILD_DIR="build"
WORKSPACE_ROOT="$PWD"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[1;36m'
NC='\033[0m'

usage() {
    echo "Usage: $0 --target <board_name> [options]"
    echo "Options:"
    echo "  --target <board>   (Required) e.g. pldm_qemu"
    echo "  --app <dir>        (Default: $DEFAULT_APP_PATH)"
    exit 1
}

# Parse Args
APP_INPUT="$DEFAULT_APP_PATH"
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --target) TARGET_BOARD="$2"; shift ;;
        --app) APP_INPUT="$2"; shift ;;
        --clean) rm -rf "$BUILD_DIR"; shift ;;
        --help) usage ;;
        *) echo "Unknown: $1"; usage ;;
    esac
    shift
done

if [ -z "$TARGET_BOARD" ]; then
    echo -e "${RED}Error: --target is required.${NC}"
    usage
fi

# Resolve Paths
if [ -d "$APP_INPUT" ]; then
    APP_ABS_PATH=$(cd "$APP_INPUT" && pwd)
else
    echo -e "${RED}Error: Host path '$APP_INPUT' not found.${NC}"
    exit 1
fi

DOCKER_APP_PATH=".${APP_ABS_PATH#$WORKSPACE_ROOT}"
BOARD_ROOT="$DOCKER_APP_PATH"

echo -e "${YELLOW}--- [HOST] PREPARING DEBUG RUN ---${NC}"
echo "Workspace:  $WORKSPACE_ROOT"
echo "Target App: $DOCKER_APP_PATH"
echo "Board Root: $BOARD_ROOT"

# --- THE DEBUG SCRIPT TO RUN INSIDE DOCKER ---
# We construct a bash script that runs inside the container
DEBUG_CMD="
echo -e '${CYAN}--- [DOCKER] 1. VERIFY FILE STRUCTURE ---${NC}'
if [ -d \"$BOARD_ROOT/boards\" ]; then
    echo '[PASS] Found boards directory at: $BOARD_ROOT/boards'
    ls -F \"$BOARD_ROOT/boards\"
else
    echo -e '${RED}[FAIL] Directory not found: $BOARD_ROOT/boards${NC}'
    echo 'Current directory content:'
    ls -F \"$DOCKER_APP_PATH\"
    exit 1
fi

echo -e '\n${CYAN}--- [DOCKER] 2. VERIFY BOARD DEFINITION ---${NC}'
# Look deeper into the vendor folder
VENDOR_DIR=\$(find \"$BOARD_ROOT/boards\" -mindepth 1 -maxdepth 1 -type d | head -n 1)
if [ -z \"\$VENDOR_DIR\" ]; then
    echo -e '${RED}[FAIL] No vendor folder found inside boards/ ${NC}'
    ls -R \"$BOARD_ROOT/boards\"
    exit 1
fi
echo \"Vendor Dir: \$VENDOR_DIR\"
ls -F \"\$VENDOR_DIR\"

echo -e '\n${CYAN}--- [DOCKER] 3. TEST WEST BOARDS ---${NC}'
echo \"Running: west boards --board-root $BOARD_ROOT -n $TARGET_BOARD\"
west boards --board-root \"$BOARD_ROOT\" -n \"$TARGET_BOARD\" || echo -e '${RED}[FAIL] West cannot see the board${NC}'

echo -e '\n${CYAN}--- [DOCKER] 4. ATTEMPTING BUILD ---${NC}'
west build -p always -b \"$TARGET_BOARD\" \"$DOCKER_APP_PATH\" -- -DBOARD_ROOT=\"$BOARD_ROOT\"
"

echo -e "${YELLOW}--- [HOST] STARTING DOCKER ---${NC}"

docker run --rm \
    -v "$WORKSPACE_ROOT":/workdir \
    -w /workdir \
    zephyrprojectrtos/zephyr-build:latest \
    /bin/bash -c "$DEBUG_CMD"

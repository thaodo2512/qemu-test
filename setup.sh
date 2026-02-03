#!/bin/bash
set -e

# Default values
APP_INPUT="pldm_sample" 
TARGET_BOARD=""
BUILD_DIR="build"
WORKSPACE_ROOT="$PWD"
DO_CHECK=0

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
    echo "Usage: $0 --target <board_name> [options]"
    echo "Options:"
    echo "  --target <board>   Specify board (e.g., pldm_qemu)"
    echo "  --app <dir>        Application directory (default: pldm_sample)"
    echo "  --check            Run CI Check (Twister) instead of just building"
    echo "  --clean            Clean build directory"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --target) TARGET_BOARD="$2"; shift ;;
        --app) APP_INPUT="$2"; shift ;;
        --check) DO_CHECK=1 ;;
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

# --- SMART PATH LOGIC ---
if [ -d "$APP_INPUT" ]; then
    APP_ABS_PATH=$(cd "$APP_INPUT" && pwd)
else
    echo -e "${RED}Error: App dir '$APP_INPUT' not found.${NC}"
    exit 1
fi

if [[ "$APP_ABS_PATH" != "$WORKSPACE_ROOT"* ]]; then
    echo -e "${RED}Error: App must be inside workspace ($WORKSPACE_ROOT).${NC}"
    exit 1
fi

# Calculate relative path for Docker
DOCKER_APP_PATH=".${APP_ABS_PATH#$WORKSPACE_ROOT}"

# --- BUILD COMMAND CONSTRUCTION ---

# CRITICAL FIX: We explicitly tell CMake where the board root is.
# We point BOARD_ROOT to the application directory (where 'boards/' is located).
BOARD_ROOT_FLAG="-DBOARD_ROOT=$DOCKER_APP_PATH"

if [ $DO_CHECK -eq 1 ]; then
    MODE="CI CHECK (Twister)"
    # Twister uses --board-root directly
    CMD="west twister -T $DOCKER_APP_PATH -p $TARGET_BOARD --board-root $DOCKER_APP_PATH --integration"
else
    MODE="BUILD (West)"
    # West Build passes CMake args after '--'
    CMD="west build -p always -b $TARGET_BOARD $DOCKER_APP_PATH -- $BOARD_ROOT_FLAG"
fi

echo "=========================================="
echo "Mode:   $MODE"
echo "Board:  $TARGET_BOARD"
echo "App:    $DOCKER_APP_PATH"
echo "Root:   Using Board Root -> $DOCKER_APP_PATH"
echo "=========================================="

echo -e "${YELLOW}[DEBUG] Pulling Docker Image...${NC}"
docker pull zephyrprojectrtos/zephyr-build:latest > /dev/null

echo -e "${YELLOW}[DEBUG] Running inside Docker:${NC}"
echo "$CMD"

docker run --rm \
    -v "$WORKSPACE_ROOT":/workdir \
    -w /workdir \
    -u "$(id -u):$(id -g)" \
    -e HOME=/workdir \
    zephyrprojectrtos/zephyr-build:latest \
    /bin/bash -c "$CMD"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ $MODE Successful!${NC}"
    if [ $DO_CHECK -eq 1 ]; then
        echo "Report: $WORKSPACE_ROOT/twister-out/twister.html"
    fi
else
    echo ""
    echo -e "${RED}❌ $MODE Failed.${NC}"
    # Help the user debug if it fails
    echo "Tip: If 'Board not found' persists, ensure $DOCKER_APP_PATH/boards exists."
    exit 1
fi

#!/bin/bash
set -e

# --- CONFIGURATION ---
DEFAULT_APP_PATH="zephyr/samples/subsys/pmci/pldm"
BUILD_DIR="build"
WORKSPACE_ROOT="$PWD"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parse Args
APP_INPUT="$DEFAULT_APP_PATH"
TARGET_BOARD=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --target) TARGET_BOARD="$2"; shift ;;
        --app) APP_INPUT="$2"; shift ;;
        --clean) rm -rf "$BUILD_DIR"; shift ;;
        *) shift ;;
    esac
done

if [ -z "$TARGET_BOARD" ]; then
    echo -e "${RED}Error: --target is required.${NC}"; exit 1
fi

# 1. Resolve Host Paths
if [ -d "$APP_INPUT" ]; then
    APP_ABS_PATH=$(cd "$APP_INPUT" && pwd)
else
    echo -e "${RED}Error: Path '$APP_INPUT' not found.${NC}"; exit 1
fi

# 2. Check Docker Mount
if [[ "$APP_ABS_PATH" != "$WORKSPACE_ROOT"* ]]; then
    echo -e "${RED}Error: App must be inside workspace.${NC}"; exit 1
fi

# 3. Calculate Docker Paths
# Relative path for Source Code (West handles this fine)
DOCKER_APP_RELATIVE=".${APP_ABS_PATH#$WORKSPACE_ROOT}"

# CRITICAL FIX: Absolute Path for BOARD_ROOT
# We force it to start with /workdir so CMake never gets lost
DOCKER_BOARD_ROOT="/workdir${APP_ABS_PATH#$WORKSPACE_ROOT}"

echo "=========================================="
echo "Target Board:   $TARGET_BOARD"
echo "Source Dir:     $DOCKER_APP_RELATIVE"
echo "Board Root:     $DOCKER_BOARD_ROOT (Absolute)"
echo "=========================================="

# 4. Run Docker
# Note: We pass -DBOARD_ROOT using the ABSOLUTE path
CMD="west build -p always -b $TARGET_BOARD $DOCKER_APP_RELATIVE -- -DBOARD_ROOT=$DOCKER_BOARD_ROOT"

docker run --rm \
    -v "$WORKSPACE_ROOT":/workdir \
    -w /workdir \
    -u "$(id -u):$(id -g)" \
    -e HOME=/workdir \
    zephyrprojectrtos/zephyr-build:latest \
    /bin/bash -c "$CMD"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Build Successful!${NC}"
else
    echo -e "${RED}❌ Build Failed.${NC}"
    exit 1
fi

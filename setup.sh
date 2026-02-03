#!/bin/bash
set -e

# --- CONFIGURATION ---
# Default to your specific path inside the Zephyr tree
DEFAULT_APP_PATH="zephyr/samples/subsys/pmci/pldm"
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
    echo "  --app <dir>        App directory (Default: $DEFAULT_APP_PATH)"
    echo "  --check            Run CI Check (Twister)"
    echo "  --clean            Clean build directory"
    exit 1
}

# Parse Args
APP_INPUT="$DEFAULT_APP_PATH" # Set default before parsing
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
    echo -e "${RED}Error: --target is required (e.g., --target pldm_qemu)${NC}"
    usage
fi

# --- SAFETY CHECKS ---

# 1. Verify we are at the Workspace Root
if [ ! -d ".west" ]; then
    echo -e "${YELLOW}[WARN] No '.west' folder found in current directory.${NC}"
    echo "       Please run this script from the top-level workspace root."
    echo "       (The folder containing 'zephyr/', 'modules/', and '.west/')"
    # We don't exit, just warn, in case you have a non-standard setup.
fi

# 2. Resolve App Path
if [ -d "$APP_INPUT" ]; then
    APP_ABS_PATH=$(cd "$APP_INPUT" && pwd)
else
    echo -e "${RED}Error: Application directory '$APP_INPUT' not found.${NC}"
    echo "       Are you running this from the workspace root?"
    exit 1
fi

# 3. Ensure App is inside Workspace (Docker Requirement)
if [[ "$APP_ABS_PATH" != "$WORKSPACE_ROOT"* ]]; then
    echo -e "${RED}Error: App must be inside workspace ($WORKSPACE_ROOT).${NC}"
    exit 1
fi

# Calculate Docker Path
DOCKER_APP_PATH=".${APP_ABS_PATH#$WORKSPACE_ROOT}"

# --- BUILD COMMAND ---

# We explicitly point BOARD_ROOT to the App Directory so it finds 'boards/'
BOARD_ROOT_FLAG="-DBOARD_ROOT=$DOCKER_APP_PATH"

if [ $DO_CHECK -eq 1 ]; then
    MODE="CI CHECK (Twister)"
    CMD="west twister -T $DOCKER_APP_PATH -p $TARGET_BOARD --board-root $DOCKER_APP_PATH --integration"
else
    MODE="BUILD (West)"
    CMD="west build -p always -b $TARGET_BOARD $DOCKER_APP_PATH -- $BOARD_ROOT_FLAG"
fi

echo "=========================================="
echo "Build Mode:  $MODE"
echo "Target:      $TARGET_BOARD"
echo "App Path:    $DOCKER_APP_PATH"
echo "Board Root:  $DOCKER_APP_PATH"
echo "=========================================="

echo -e "${YELLOW}[DEBUG] Pulling Docker Image...${NC}"
docker pull zephyrprojectrtos/zephyr-build:latest > /dev/null

echo -e "${YELLOW}[DEBUG] Executing...${NC}"

docker run --rm \
    -v "$WORKSPACE_ROOT":/workdir \
    -w /workdir \
    -u "$(id -u):$(id -g)" \
    -e HOME=/workdir \
    zephyrprojectrtos/zephyr-build:latest \
    /bin/bash -c "$CMD"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Build Successful!${NC}"
else
    echo ""
    echo -e "${RED}❌ Build Failed.${NC}"
    echo "Tip: Verify that '$APP_INPUT/boards/my_company/$TARGET_BOARD' exists."
    exit 1
fi

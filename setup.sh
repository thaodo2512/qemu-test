#!/bin/bash
set -e  # Exit immediately if any command fails

# Default values
APP_INPUT="pldm_sample" 
TARGET_BOARD=""
BUILD_DIR="build"
WORKSPACE_ROOT="$PWD"

# Color codes for easier reading
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 --target <board_name> [options]"
    echo "Options:"
    echo "  --target <board>   Specify the board to build for (e.g., pldm_qemu)"
    echo "  --app <dir>        Specify application directory (default: pldm_sample)"
    echo "  --clean            Clean build directory before building"
    echo "  --help             Show this help message"
    exit 1
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --target) TARGET_BOARD="$2"; shift ;;
        --app) APP_INPUT="$2"; shift ;;
        --clean) rm -rf "$BUILD_DIR"; shift ;;
        --help) usage ;;
        *) echo "Unknown parameter: $1"; usage ;;
    esac
    shift
done

if [ -z "$TARGET_BOARD" ]; then
    echo -e "${RED}Error: You must specify a target board.${NC}"
    usage
fi

echo -e "${YELLOW}--- [DEBUG] Starting Path Resolution ---${NC}"
echo "Current Workspace Root (Host): $WORKSPACE_ROOT"
echo "Raw Input App Path:            $APP_INPUT"

# --- SMART PATH LOGIC ---

# 1. Resolve absolute path of the App
if [ -d "$APP_INPUT" ]; then
    APP_ABS_PATH=$(cd "$APP_INPUT" && pwd)
    echo "Resolved Absolute App Path:    $APP_ABS_PATH"
else
    echo -e "${RED}❌ Error: Application directory '$APP_INPUT' not found on host.${NC}"
    exit 1
fi

# 2. Check if App is inside the Workspace
if [[ "$APP_ABS_PATH" != "$WORKSPACE_ROOT"* ]]; then
    echo -e "${RED}❌ Error: The application MUST be inside the current workspace.${NC}"
    echo "  Reason: Docker mounts '$WORKSPACE_ROOT' to '/workdir'"
    echo "  But your app is at '$APP_ABS_PATH' (Outside mount point)"
    exit 1
else
    echo "✅ Check passed: App is inside Workspace."
fi

# 3. Calculate the Relative Path for Docker
# This removes the WORKSPACE_ROOT prefix from APP_ABS_PATH
DOCKER_APP_PATH=".${APP_ABS_PATH#$WORKSPACE_ROOT}"

echo "Calculated Path for Docker:    $DOCKER_APP_PATH"
echo -e "${YELLOW}--- [DEBUG] Resolution Complete ---${NC}"
echo ""

echo "=========================================="
echo "🚀 Building Board: $TARGET_BOARD"
echo "📂 App Directory:  $DOCKER_APP_PATH"
echo "=========================================="

# 4. Pull Image
echo -e "${YELLOW}[DEBUG] Checking for Docker image updates...${NC}"
docker pull zephyrprojectrtos/zephyr-build:latest

# 5. Run Docker
echo -e "${YELLOW}[DEBUG] Executing Docker Command:${NC}"
echo "docker run --rm -v $WORKSPACE_ROOT:/workdir -w /workdir ... west build -b $TARGET_BOARD $DOCKER_APP_PATH"

docker run --rm \
    -v "$WORKSPACE_ROOT":/workdir \
    -w /workdir \
    -u "$(id -u):$(id -g)" \
    -e HOME=/workdir \
    zephyrprojectrtos/zephyr-build:latest \
    west build -p always -b "$TARGET_BOARD" "$DOCKER_APP_PATH"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Build Successful!${NC}"
    echo "Artifacts located in: $APP_INPUT/build/zephyr/"
else
    echo ""
    echo -e "${RED}❌ Build Failed.${NC}"
    exit 1
fi

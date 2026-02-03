#!/bin/bash
set -e

# Default to current directory if not provided
APP_DIR="${1:-sample/pcmi/pldm}"
WORKSPACE_ROOT="$PWD"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo " 🩺  Zephyr Custom Board Diagnostic Tool"
echo "==========================================${NC}"
echo "Inspecting App Directory: $APP_DIR"

# 1. Check if App Directory exists
if [ ! -d "$APP_DIR" ]; then
    echo -e "${RED}[FAIL] Directory '$APP_DIR' does not exist.${NC}"
    exit 1
fi
echo -e "${GREEN}[PASS] App Directory exists.${NC}"

# 2. Check for 'boards' folder (Must be PLURAL)
BOARDS_DIR="$APP_DIR/boards"
if [ -d "$APP_DIR/board" ]; then
    echo -e "${RED}[FAIL] Found 'board' (singular). Zephyr REQUIRES 'boards' (plural).${NC}"
    echo "       Fix: mv $APP_DIR/board $APP_DIR/boards"
    exit 1
fi

if [ ! -d "$BOARDS_DIR" ]; then
    echo -e "${RED}[FAIL] Could not find '$BOARDS_DIR'.${NC}"
    exit 1
fi
echo -e "${GREEN}[PASS] 'boards' directory found.${NC}"

# 3. Detect Vendor Directory
# We take the first directory found inside boards/
VENDOR_DIR=$(find "$BOARDS_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)

if [ -z "$VENDOR_DIR" ]; then
    echo -e "${RED}[FAIL] No vendor directory found inside 'boards/'.${NC}"
    echo "       Structure must be: boards/<vendor>/<board_name>"
    exit 1
fi
VENDOR_NAME=$(basename "$VENDOR_DIR")
echo -e "${GREEN}[PASS] Vendor directory found: '$VENDOR_NAME'${NC}"

# 4. Detect Board Directory
BOARD_PATH=$(find "$VENDOR_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
if [ -z "$BOARD_PATH" ]; then
    echo -e "${RED}[FAIL] No board directory found inside '$VENDOR_NAME/'.${NC}"
    exit 1
fi
BOARD_NAME=$(basename "$BOARD_PATH")
echo -e "${GREEN}[PASS] Board directory found:  '$BOARD_NAME'${NC}"

# 5. Check Critical Files
echo -e "\n${BLUE}--- Checking Critical Files ---${NC}"

check_file() {
    if [ -f "$BOARD_PATH/$1" ]; then
        echo -e "${GREEN}[PASS] Found $1${NC}"
    else
        echo -e "${RED}[FAIL] Missing $1${NC}"
        MISSING_FILES=1
    fi
}

check_file "board.cmake"
check_file "Kconfig.board"
check_file "Kconfig.defconfig"
check_file "$BOARD_NAME.dts"
check_file "board.yml"

if [ "$MISSING_FILES" == "1" ]; then
    echo -e "${RED}\n[CRITICAL] One or more required files are missing.${NC}"
    echo "For Zephyr Main/v3.7+, 'board.yml' is MANDATORY."
    # We don't exit here, we try to run the docker check anyway to see what happens
fi

# 6. Check board.yml content (HWMv2 requirement)
if [ -f "$BOARD_PATH/board.yml" ]; then
    if grep -q "vendor: $VENDOR_NAME" "$BOARD_PATH/board.yml"; then
        echo -e "${GREEN}[PASS] board.yml matches vendor '$VENDOR_NAME'${NC}"
    else
        echo -e "${YELLOW}[WARN] board.yml does not seem to contain 'vendor: $VENDOR_NAME'${NC}"
    fi
    if grep -q "name: $BOARD_NAME" "$BOARD_PATH/board.yml"; then
        echo -e "${GREEN}[PASS] board.yml matches name '$BOARD_NAME'${NC}"
    else
        echo -e "${YELLOW}[WARN] board.yml does not seem to contain 'name: $BOARD_NAME'${NC}"
    fi
fi

# 7. Run West Boards inside Docker
echo -e "\n${BLUE}--- Running Docker Verification ---${NC}"

# Calculate relative path for docker
ABS_APP_PATH=$(cd "$APP_DIR" && pwd)
DOCKER_APP_PATH=".${ABS_APP_PATH#$WORKSPACE_ROOT}"

echo "Command: west boards --board-root $DOCKER_APP_PATH -n $BOARD_NAME"

docker run --rm \
    -v "$WORKSPACE_ROOT":/workdir \
    -w /workdir \
    zephyrprojectrtos/zephyr-build:latest \
    west boards --board-root "$DOCKER_APP_PATH" > docker_output.txt 2>&1

# Check output
if grep -q "$BOARD_NAME" docker_output.txt; then
    echo -e "${GREEN}[SUCCESS] Zephyr Docker Image SUCCESSFULLY found the board!${NC}"
    echo "Found:"
    grep "$BOARD_NAME" docker_output.txt
else
    echo -e "${RED}[FAIL] Zephyr Docker Image could NOT find the board.${NC}"
    echo "Output from 'west boards':"
    cat docker_output.txt
fi

rm docker_output.txt

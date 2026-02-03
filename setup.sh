#!/bin/bash

# Default values
APP_DIR="pldm_sample"  # Change this if your app folder has a different name
TARGET_BOARD=""
BUILD_DIR="build"

# Function to display usage
usage() {
    echo "Usage: $0 --target <board_name> [options]"
    echo ""
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
        --app) APP_DIR="$2"; shift ;;
        --clean) rm -rf "$BUILD_DIR"; shift ;; # Simple clean
        --help) usage ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# Validation
if [ -z "$TARGET_BOARD" ]; then
    echo "Error: You must specify a target board."
    usage
fi

if [ ! -d "$APP_DIR" ]; then
    echo "Error: Application directory '$APP_DIR' not found!"
    exit 1
fi

echo "=========================================="
echo "Building '$APP_DIR' for board '$TARGET_BOARD'"
echo "Using Docker Image: zephyrprojectrtos/zephyr-build:latest"
echo "=========================================="

# The Docker Command
# 1. -v "$PWD":/workdir   : Mounts your entire workspace into the container
# 2. -w /workdir          : Sets the working directory inside the container
# 3. -u $(id -u):$(id -g) : Runs as your current user (prevents permission issues on output files)
# 4. -e ZEPHYR_BASE...    : Helps west locate the installation if needed (often auto-detected)

docker run --rm \
    -v "$PWD":/workdir \
    -w /workdir \
    -u "$(id -u):$(id -g)" \
    -e HOME=/workdir \
    zephyrprojectrtos/zephyr-build:latest \
    west build -p always -b "$TARGET_BOARD" "$APP_DIR"

# Check status
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build Successful!"
    echo "Artifacts are in: $APP_DIR/build/zephyr/"
else
    echo ""
    echo "❌ Build Failed."
    exit 1
fi

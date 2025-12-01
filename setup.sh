#!/bin/bash

# Bash script for Zephyr OS development using Docker.
# Supports initializing the workspace from scratch, building projects,
# running local CI tests with Twister, running tests in QEMU,
# and cleaning up the workspace + Docker image.
# build docker locally
# git clone https://github.com/zephyrproject-rtos/docker-image.git
# cd docker-image
# docker build -f Dockerfile.base --build-arg UID=$(id -u) --build-arg GID=$(id -g) -t zephyrprojectrtos/ci-base:main .
# docker build -f Dockerfile.ci --build-arg UID=$(id -u) --build-arg GID=$(id -g) -t zephyrprojectrtos/ci:main .

# Configuration
DOCKER_IMAGE="zephyrprojectrtos/ci:main"  # Official Zephyr CI image (slimmer, no VNC for build-only workflows)
WORKSPACE_DIR="$(pwd)/zephyrproject"  # Workspace directory (adjust if needed)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_DIR="${SCRIPT_DIR}/patches"
ZEPHYR_SDK_DIR="/opt/toolchains/zephyr-sdk-0.17.4"  # Path to SDK in the Docker image (updated to latest known version)

# Get host UID and GID to avoid permission issues with mounted volumes
HOST_UID=$(id -u)
HOST_GID=$(id -g)

# Function to run commands inside the Docker container
run_docker() {
    docker run --rm -it \
        --user "${HOST_UID}:${HOST_GID}" \
        --env ZEPHYR_SDK_INSTALL_DIR="${ZEPHYR_SDK_DIR}" \
        --env CMAKE_PREFIX_PATH="${ZEPHYR_SDK_DIR}/cmake" \
        --env ZEPHYR_TOOLCHAIN_VARIANT=zephyr \
        -v "${WORKSPACE_DIR}:/workdir" \
        -w /workdir/zephyr \
        "${DOCKER_IMAGE}" \
        "$@"
}

# Function to pull the Docker image if not present
pull_image() {
    if ! docker image inspect "${DOCKER_IMAGE}" &> /dev/null; then
        echo "Pulling Docker image: ${DOCKER_IMAGE}"
        docker pull "${DOCKER_IMAGE}"
    fi
}

# Main logic
case "$1" in
    init)
        pull_image

        # Initialize the Zephyr workspace from scratch
        if [ -d "${WORKSPACE_DIR}" ] && [ "$(ls -A "${WORKSPACE_DIR}")" ]; then
            echo "Warning: Workspace directory '${WORKSPACE_DIR}' is not empty."
            read -p "Continue and potentially overwrite files? (y/n): " confirm
            if [ "$confirm" != "y" ]; then
                exit 1
            fi
        fi

        mkdir -p "${WORKSPACE_DIR}"
        cd "${WORKSPACE_DIR}" || exit 1

        docker run --rm -it \
            --user "${HOST_UID}:${HOST_GID}" \
            --env ZEPHYR_SDK_INSTALL_DIR="${ZEPHYR_SDK_DIR}" \
            --env CMAKE_PREFIX_PATH="${ZEPHYR_SDK_DIR}/cmake" \
            --env ZEPHYR_TOOLCHAIN_VARIANT=zephyr \
            -v "${WORKSPACE_DIR}:/workdir" \
            -w /workdir \
            "${DOCKER_IMAGE}" \
            west init -m https://github.com/zephyrproject-rtos/zephyr --mr main

        docker run --rm -it \
            --user "${HOST_UID}:${HOST_GID}" \
            --env ZEPHYR_SDK_INSTALL_DIR="${ZEPHYR_SDK_DIR}" \
            --env CMAKE_PREFIX_PATH="${ZEPHYR_SDK_DIR}/cmake" \
            --env ZEPHYR_TOOLCHAIN_VARIANT=zephyr \
            -v "${WORKSPACE_DIR}:/workdir" \
            -w /workdir \
            "${DOCKER_IMAGE}" \
            west update

        # Prompt for git user identity for the Zephyr workspace (required for git am)
        while [ -z "${GIT_USER_NAME}" ]; do
            read -p "Enter git user.name for Zephyr workspace: " GIT_USER_NAME
        done
        while [ -z "${GIT_USER_EMAIL}" ]; do
            read -p "Enter git user.email for Zephyr workspace: " GIT_USER_EMAIL
        done

        run_docker git config user.name "${GIT_USER_NAME}"
        run_docker git config user.email "${GIT_USER_EMAIL}"

        # Note: Skipped 'west zephyr-export' as it's optional and not required for Docker-based builds inside the workspace.
        # It registers Zephyr for external CMake find_package, but west build handles it internally.

        echo "Zephyr workspace initialized in '${WORKSPACE_DIR}'."
        ;;

    build)
        shift
        if [ $# -eq 0 ]; then
            echo "Usage: $0 build [west build options]"
            exit 1
        fi
        run_docker west build "$@"
        ;;

    ci-test)
        shift
        if [ $# -eq 0 ]; then
            echo "Usage: $0 ci-test [west twister options]"
            echo "Example: $0 ci-test -p qemu_x86 --all"
            exit 1
        fi
        run_docker west twister --inline-logs "$@"
        ;;

    qemu-test)
        shift
        run_docker west build -t run "$@"
        ;;

    apply-mctp-patch)
        if [ ! -d "${PATCH_DIR}" ]; then
            echo "Patch directory not found at ${PATCH_DIR}"
            exit 1
        fi
        if [ ! -d "${WORKSPACE_DIR}/zephyr" ]; then
            echo "Zephyr workspace not found at ${WORKSPACE_DIR}/zephyr. Run '$0 init' first."
            exit 1
        fi

        shopt -s nullglob
        PATCH_FILES=("${PATCH_DIR}"/*.patch)
        shopt -u nullglob

        if [ ${#PATCH_FILES[@]} -eq 0 ]; then
            echo "No .patch files found in ${PATCH_DIR}"
            exit 1
        fi

        PATCH_ARGS=()
        for pf in "${PATCH_FILES[@]}"; do
            cp "${pf}" "${WORKSPACE_DIR}/"
            PATCH_ARGS+=("../$(basename "${pf}")")
        done

        # Apply all patches in order; git am will stop on conflicts/duplicates
        run_docker git am "${PATCH_ARGS[@]}"
        ;;

    clean)
        echo "=== Cleanup ==="

        # Clean workspace/repo
        if [ -d "${WORKSPACE_DIR}" ]; then
            echo "Workspace found: ${WORKSPACE_DIR}"
            read -p "Delete the entire workspace (all cloned repos, builds, etc.)? [y/N]: " confirm_ws
            if [[ "$confirm_ws" =~ ^[Yy]$ ]]; then
                rm -rf "${WORKSPACE_DIR}"
                echo "Workspace deleted."
            else
                echo "Workspace kept."
            fi
        else
            echo "No workspace directory found (${WORKSPACE_DIR})."
        fi

        # Clean Docker image
        if docker image inspect "${DOCKER_IMAGE}" &> /dev/null; then
            echo "Docker image found: ${DOCKER_IMAGE}"
            read -p "Remove the Docker image (will be re-downloaded next time)? [y/N]: " confirm_img
            if [[ "$confirm_img" =~ ^[Yy]$ ]]; then
                docker rmi "${DOCKER_IMAGE}"
                echo "Docker image removed."
            else
                echo "Docker image kept."
            fi
        else
            echo "Docker image ${DOCKER_IMAGE} not present on this machine."
        fi

        echo "Cleanup complete."
        ;;

    *)
        echo "Usage: $0 {init|build|ci-test|qemu-test|clean} [options]"
        echo ""
        echo "Commands:"
        echo "  init          Initialize Zephyr workspace from scratch"
        echo "  build         Build a project (pass west build args)"
        echo "  ci-test       Run local CI with Twister (pass west twister args)"
        echo "  qemu-test     Run built app in QEMU"
        echo "  apply-mctp-patch  Copy and apply all .patch files from ./patches into the Zephyr workspace"
        echo "  clean         Interactively delete workspace and/or Docker image"
        exit 1
        ;;
esac

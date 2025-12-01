# MCTP over UART between two QEMU instances (Zephyr in Docker)

This guide shows how to run two `qemu_x86` Zephyr instances inside the official Zephyr CI Docker image, wire their secondary UARTs together over TCP, and exercise the built‑in MCTP host/endpoint samples (host sends “hello”, endpoint replies “world”).

## Prerequisites
- Linux host with Docker available to your user.
- ~4–5 GB free disk for the Zephyr workspace and image layers.
- Two terminals/panes to run each QEMU instance.
- A free TCP port for the UART tunnel (examples use `4321`).

## Reference script (verbatim)

`setup.sh` used below (already in this repo):
```bash
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
        echo "  clean         Interactively delete workspace and/or Docker image"
        exit 1
        ;;
esac
```

## Quick variables
- `MCTP_PORT` (default `4321`) – TCP port carrying UART1 between QEMUs.
- `QEMU_EXTRA_FLAGS` – appended to QEMU; we use it to define UART1 TCP wiring.

## Workspace setup
```bash
# From repo root (contains setup.sh)
./setup.sh init
```

## Devicetree overlays for qemu_x86 (use UART1 for MCTP)
```bash
cat > zephyrproject/zephyr/samples/subsys/pmci/mctp/host/boards/qemu_x86.overlay <<'EOF'
/ {
	aliases {
		arduino-serial = &arduino_serial;
	};
};

arduino_serial: &uart1 {
	status = "okay";
	current-speed = <115200>;
};
EOF

cat > zephyrproject/zephyr/samples/subsys/pmci/mctp/endpoint/boards/qemu_x86.overlay <<'EOF'
/ {
	aliases {
		arduino-serial = &arduino_serial;
	};
};

arduino_serial: &uart1 {
	status = "okay";
	current-speed = <115200>;
};
EOF
```

## Build commands (host listens, endpoint connects)
```bash
cd /home/thaomeo/Documents/op
# Host: server on TCP port
./setup.sh build --pristine=always \
  -b qemu_x86 samples/subsys/pmci/mctp/host -d build/mctp_host \
  -- -DQEMU_EXTRA_FLAGS="-serial tcp::${MCTP_PORT:-4321},server=on,wait=off,nodelay"

# Endpoint: client connects to host port
./setup.sh build --pristine=always \
  -b qemu_x86 samples/subsys/pmci/mctp/endpoint -d build/mctp_endpoint \
  -- -DQEMU_EXTRA_FLAGS="-serial tcp:127.0.0.1:${MCTP_PORT:-4321},server=off,wait=on,nodelay"
```

## Running (two terminals)
- Terminal 1 (host or endpoint depending on who is server):
```bash
MCTP_PORT=4321 ./setup.sh qemu-test -d build/mctp_endpoint
```
- Terminal 2:
```bash
MCTP_PORT=4321 ./setup.sh qemu-test -d build/mctp_host
```
- Exit QEMU: `Ctrl+a`, then `x`.

## Verification (expected logs)
- Endpoint console: `I: got mctp message hello for eid 20, replying to 5 with "world"`
- Host console: `I: received message world for endpoint 10, msg_tag 0, len 6`

## Troubleshooting
- Port busy: choose another `MCTP_PORT`, rebuild with `--pristine=always`.
- No traffic: confirm overlays map `arduino_serial` to `uart1` in each build (`grep -n arduino_serial build/*/zephyr/zephyr.dts`).
- Stuck waiting: add `,wait=off` on the client side; ensure listener started first.
- Deeper debug: add `-d guest_errors -D /workdir/qemu.log` to `QEMU_EXTRA_FLAGS`.

## Cleanup
- Stop QEMU: `Ctrl+a x` in each terminal.
- Remove build outputs: `rm -rf build/mctp_host build/mctp_endpoint`.
- Full cleanup (workspace/image): `./setup.sh clean`.


# MCTP over UART between two QEMU instances (Zephyr in Docker)

This guide shows how to run two `qemu_x86` Zephyr instances inside the official Zephyr CI Docker image, wire their secondary UARTs together over TCP, and exercise the built‑in MCTP host/endpoint samples (host sends “hello”, endpoint replies “world”).

## Prerequisites
- Linux host with Docker available to your user.
- ~4–5 GB free disk for the Zephyr workspace and image layers.
- Two terminals/panes to run each QEMU instance.
- A free TCP port for the UART tunnel (examples use `4321`).

## Quick variables
- `MCTP_PORT` (default `4321`) – TCP port carrying UART1 between QEMUs.
- `QEMU_EXTRA_FLAGS` – appended to QEMU; we use it to define UART1 TCP wiring.

## Workspace setup
```bash
# From repo root (contains setup.sh)
./setup.sh init
```

## Apply UART1 overlay patch (recommended)
- This applies `patches/0001-qemu-x86-mctp-uart1.patch` into the Zephyr workspace, adding `qemu_x86.overlay` for host and endpoint to map `arduino_serial` to UART1 (leaving console on UART0).
```bash
./setup.sh apply-mctp-patch
```
If you rerun after it is already applied, `git am` will fail; that’s expected—skip if already applied.

## Build commands (host listens, endpoint connects)
```bash
cd /home/thaomeo/Documents/op
# Host: server on TCP port (UART1 over chardev socket)
./setup.sh build --pristine=always \
  -b qemu_x86 samples/subsys/pmci/mctp/host -d build/mctp_host \
  -- -DQEMU_EXTRA_FLAGS="-chardev;socket,id=uart1,host=0.0.0.0,port=${MCTP_PORT:-4321},server=on,wait=on,nodelay=on;-serial;chardev:uart1;-no-shutdown"

# Endpoint: client connects to host port
./setup.sh build --pristine=always \
  -b qemu_x86 samples/subsys/pmci/mctp/endpoint -d build/mctp_endpoint \
  -- -DQEMU_EXTRA_FLAGS="-chardev;socket,id=uart1,host=127.0.0.1,port=${MCTP_PORT:-4321},server=off,reconnect=1,nodelay=on;-serial;chardev:uart1;-no-shutdown"
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
- If QEMU errors with “invalid option”, make sure `QEMU_EXTRA_FLAGS` is semicolon-separated so CMake passes each flag separately (see commands above). You can confirm in the build tree: `grep -n \"-chardev socket\" build/mctp_endpoint/build.ninja` (and host accordingly) — the flags should appear without backslash-escaped spaces.
- QEMU 10 rejects `wait=` in client mode (`server=off`); use the `reconnect=` form shown above and rebuild if you see an “invalid option” or “wait option is incompatible” error.
- Port busy: choose another `MCTP_PORT`, rebuild with `--pristine=always`.
- No traffic: confirm overlays map `arduino_serial` to `uart1` in each build (`grep -n arduino_serial build/*/zephyr/zephyr.dts`).
- Stuck waiting: the client uses `reconnect=1`; start the listener first or bump the reconnect interval if you want longer retries.
- Deeper debug: add `-d guest_errors -D /workdir/qemu.log` to `QEMU_EXTRA_FLAGS`.

## Cleanup
- Stop QEMU: `Ctrl+a x` in each terminal.
- Remove build outputs: `rm -rf build/mctp_host build/mctp_endpoint`.
- Full cleanup (workspace/image): `./setup.sh clean`.

#!/usr/bin/env bash
# Install the Go toolchain natively (aarch64). Idempotent.
set -euo pipefail

sudo pacman -Sy --needed --noconfirm go
echo "go ready: $(go version)"

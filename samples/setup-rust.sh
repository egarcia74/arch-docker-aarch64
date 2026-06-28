#!/usr/bin/env bash
# Install Rust via rustup (native aarch64). Toolchains land in ~/.rustup and ~/.cargo,
# which persist in the home volume. Idempotent.
set -euo pipefail

sudo pacman -Sy --needed --noconfirm rustup
rustup default stable
echo "rust ready: $(rustc --version)"

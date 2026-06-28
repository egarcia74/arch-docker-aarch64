#!/usr/bin/env bash
# Common native build tooling (base-devel is already in the image). Idempotent.
set -euo pipefail

sudo pacman -Sy --needed --noconfirm cmake ninja meson pkgconf ccache
echo "build tools ready: $(cmake --version | head -1)"

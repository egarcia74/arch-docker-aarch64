#!/usr/bin/env bash
# Install the .NET SDK natively (linux-arm64) via Microsoft's official installer.
# Arch's dotnet-sdk package is not built for aarch64 in the ALARM repos, and the
# installer auto-detects arm64 and installs into ~/.dotnet, which persists in the home
# volume. Idempotent. Override the channel with: ARCH_DOTNET_CHANNEL=9.0 ...
set -euo pipefail

channel="${ARCH_DOTNET_CHANNEL:-LTS}"
dotnet_root="$HOME/.dotnet"

command -v curl >/dev/null 2>&1 || sudo pacman -Sy --needed --noconfirm curl

curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
bash /tmp/dotnet-install.sh --channel "$channel" --install-dir "$dotnet_root"
rm -f /tmp/dotnet-install.sh

# Put dotnet on PATH for future interactive shells (persists in the home volume).
path_line='export PATH="$HOME/.dotnet:$PATH"'
grep -qxF "$path_line" "$HOME/.bashrc" 2>/dev/null || printf '%s\n' "$path_line" >> "$HOME/.bashrc"

echo "dotnet ready: $("$dotnet_root/dotnet" --version) (channel $channel)"

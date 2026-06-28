#!/usr/bin/env bash
# Configure and start sshd for key-based login as the dev user.
# Idempotent: safe to re-run (e.g. after a container restart, since there is no
# systemd to keep sshd alive). The public key is installed by Enable-ArchSsh.ps1.
set -euo pipefail

# openssh ships in the image; only install (with a DB sync) if it is somehow missing,
# so the common path avoids a needless mirror sync on every SSH enable.
command -v sshd >/dev/null 2>&1 || sudo pacman -Sy --needed --noconfirm openssh
sudo ssh-keygen -A # generate host keys if missing

# Harden: key-only auth, no root login, no passwords (a drop-in the default
# sshd_config Includes). The dev user has no password anyway, so this is belt-and-braces.
printf 'PermitRootLogin no\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nPubkeyAuthentication yes\n' |
    sudo tee /etc/ssh/sshd_config.d/10-arch-docker.conf >/dev/null

install -d -m 0700 "$HOME/.ssh"
[ -f "$HOME/.ssh/authorized_keys" ] && chmod 600 "$HOME/.ssh/authorized_keys"

# No systemd in the container: start the daemon directly (restart if already up).
sudo pkill -x sshd 2>/dev/null || true
sudo /usr/sbin/sshd

keys=0
[ -f "$HOME/.ssh/authorized_keys" ] && keys=$(grep -c . "$HOME/.ssh/authorized_keys" || true)
echo "sshd started; ${keys} authorised key(s) for $(whoami)"

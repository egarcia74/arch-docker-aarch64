#!/usr/bin/env bash
# Container entrypoint (runs as root, PID 1). When StartSshOnBoot is enabled
# (ARCH_START_SSHD=1) and the dev user has an authorised key, start sshd on boot so
# SSH survives stop/start without re-running Enable-ArchSsh. Then idle so the container
# stays up. No -e: the conditional must never prevent the final exec.
set -uo pipefail

home="${ARCH_DEV_HOME:-/home/dev}"
# ARCH_START_SSHD is set by scripts/Start-ArchContainer.ps1 when StartSshOnBoot is true.
if [[ "${ARCH_START_SSHD:-0}" == "1" && -s "${home}/.ssh/authorized_keys" ]]; then
    ssh-keygen -A 2>/dev/null || true
    /usr/sbin/sshd || true
fi

exec sleep infinity

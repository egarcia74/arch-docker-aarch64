#!/usr/bin/env bash
# Container entrypoint (runs as root, PID 1). When StartSshOnBoot is enabled
# (ARCH_START_SSHD=1) and the dev user has an authorised key, start sshd on boot so
# SSH survives stop/start without re-running Enable-ArchSsh. Then idle so the container
# stays up. No -e: the conditional must never prevent the final exec.
set -uo pipefail

home="${ARCH_DEV_HOME:-/home/dev}"
# ARCH_START_SSHD is set by scripts/Start-ArchContainer.ps1 when StartSshOnBoot is true.
if [[ "${ARCH_START_SSHD:-0}" == "1" && -s "${home}/.ssh/authorized_keys" ]]; then
    # Persist host keys in the home volume so the server identity survives a container
    # remove+recreate (only removing the volume resets it). Keeps known_hosts stable.
    # NOTE: keep this restore-or-generate logic in sync with samples/setup-ssh.sh (the
    # manual SSH-enable path) — both must use the same dir, sentinel, and copy semantics.
    hk="${home}/.ssh-hostkeys"
    if [[ -f "${hk}/ssh_host_ed25519_key" ]]; then
        cp -a "${hk}"/ssh_host_* /etc/ssh/
    else
        ssh-keygen -A
        mkdir -p "${hk}"
        cp -a /etc/ssh/ssh_host_* "${hk}/"
    fi
    /usr/sbin/sshd || true
fi

exec sleep infinity

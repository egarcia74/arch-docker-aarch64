#Requires -Version 7
<#
.SYNOPSIS
    Enable key-based SSH into the container, then print the connection command.
.DESCRIPTION
    Ensures the container exists and publishes the SSH port (recreating it once if it
    predates the port mapping - the home volume is preserved), installs your public key
    into the dev user's authorized_keys (which persists via the volume), and starts sshd.
    No password auth: key only. Re-run after a container restart (sshd is not a service).
.PARAMETER PublicKey
    Path to the public key to authorise. Defaults to ~/.ssh/id_ed25519.pub or id_rsa.pub.
.EXAMPLE
    ./scripts/Enable-ArchSsh.ps1
.EXAMPLE
    ./scripts/Enable-ArchSsh.ps1 -PublicKey ~/.ssh/work.pub
#>
[CmdletBinding()]
param(
    [string]$PublicKey
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

$cfg = Get-ArchConfig
Test-DockerRunning

# Resolve the host public key.
if (-not $PublicKey) {
    $PublicKey = @(
        (Join-Path $HOME '.ssh/id_ed25519.pub')
        (Join-Path $HOME '.ssh/id_rsa.pub')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $PublicKey -or -not (Test-Path $PublicKey)) {
    throw 'No SSH public key found. Generate one (ssh-keygen -t ed25519) or pass -PublicKey <path>.'
}
$keyText = (Get-Content -Raw $PublicKey).Trim()

# Ensure the container exists and publishes the SSH port; recreate once if it predates it.
if (Test-ContainerExists $cfg.ContainerName) {
    $portMap = docker port $cfg.ContainerName 22/tcp 2>$null
    if (-not $portMap) {
        Write-Step 'Existing container has no SSH port - recreating it (home volume preserved)'
        Invoke-Docker -Arguments @('rm', '-f', $cfg.ContainerName) -FailMessage 'Failed to remove container.'
    }
}
Assert-ContainerRunning $cfg.ContainerName

# Install the public key (passed as a positional arg so spaces/special chars are safe).
Write-Step "Authorising $(Split-Path -Leaf $PublicKey) for '$($cfg.DevUser)'"
$installKey = @'
set -euo pipefail
key="$1"
install -d -m 0700 "$HOME/.ssh"
touch "$HOME/.ssh/authorized_keys"
chmod 600 "$HOME/.ssh/authorized_keys"
grep -qxF "$key" "$HOME/.ssh/authorized_keys" || printf '%s\n' "$key" >> "$HOME/.ssh/authorized_keys"
'@
Invoke-ContainerScript -Script $installKey -ScriptArgs $keyText -FailMessage 'Failed to install the public key.'

# Start sshd via the ssh sample.
& (Join-Path $PSScriptRoot 'Invoke-ArchSample.ps1') -Name 'ssh'

Write-Ok 'SSH ready. Connect with:'
Write-Info "ssh $($cfg.DevUser)@127.0.0.1 -p $($cfg.SshHostPort)"
Write-Info "VS Code: Remote-SSH -> Connect to Host -> $($cfg.DevUser)@127.0.0.1:$($cfg.SshHostPort)"

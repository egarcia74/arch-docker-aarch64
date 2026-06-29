#Requires -Version 7
<#
.SYNOPSIS
    Open an interactive shell in the running arch-aarch64 container as the dev user,
    or run a single command with -Command.
.PARAMETER Command
    Run this single command instead of opening a login shell. A TTY is allocated when
    attached to a real terminal, so interactive programs (htop, vim) work; it degrades to
    a plain pipe when stdin is redirected, so piped/CI callers still succeed.
.EXAMPLE
    ./scripts/Enter-ArchContainer.ps1
.EXAMPLE
    ./scripts/Enter-ArchContainer.ps1 -Command 'uname -m'
#>
[CmdletBinding()]
param(
    [string]$Command
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

$cfg = Get-ArchConfig
Test-DockerRunning

# Ensure the container is up (which builds the image if missing), so a fresh clone can
# bootstrap everything by just opening a shell.
Assert-ContainerRunning $cfg.ContainerName

# -t (allocate a TTY) only works when attached to a real terminal. Detect a
# redirected/non-interactive stdin and drop -t so one-off commands and piped
# callers don't fail with "cannot attach stdin to a TTY-enabled container"; a real
# terminal keeps -t so interactive programs (htop, vim, the login shell) render.
$ttyFlags = if ([Console]::IsInputRedirected) { '-i' } else { '-it' }
if ($Command) {
    docker exec $ttyFlags -u $cfg.DevUser -w $cfg.MountPath $cfg.ContainerName bash -lc $Command
}
else {
    docker exec $ttyFlags -u $cfg.DevUser -w $cfg.MountPath $cfg.ContainerName bash -l
}

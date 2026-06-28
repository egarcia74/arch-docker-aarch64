#Requires -Version 7
<#
.SYNOPSIS
    Open an interactive shell in the running arch-aarch64 container as the dev user,
    or run a single command with -Command.
.PARAMETER Command
    Run this command non-interactively instead of opening a login shell.
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
# callers don't fail with "cannot attach stdin to a TTY-enabled container".
if ($Command) {
    docker exec -i -u $cfg.DevUser -w $cfg.MountPath $cfg.ContainerName bash -lc $Command
}
else {
    $ttyFlags = if ([Console]::IsInputRedirected) { '-i' } else { '-it' }
    docker exec $ttyFlags -u $cfg.DevUser -w $cfg.MountPath $cfg.ContainerName bash -l
}

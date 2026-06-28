#Requires -Version 7
<#
.SYNOPSIS
    Start the arch-aarch64 container, creating it (with its persistent home volume)
    on first run. Idempotent.
.EXAMPLE
    ./scripts/Start-ArchContainer.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

$cfg = Get-ArchConfig
Test-DockerRunning

if (Test-ContainerRunning $cfg.ContainerName) {
    Write-Ok "Container '$($cfg.ContainerName)' is already running."
}
elseif (Test-ContainerExists $cfg.ContainerName) {
    Write-Step "Starting existing container '$($cfg.ContainerName)'"
    Invoke-Docker -Arguments @('start', $cfg.ContainerName) -FailMessage 'Failed to start container.'
    Write-Ok 'Started.'
}
else {
    if (-not (Test-ImageExists $cfg.ImageName)) {
        # Ensure semantics: build the image on demand the first time (a conditional
        # step a VS Code task dependsOn cannot express). Only runs when truly missing.
        Write-Step "Image '$($cfg.ImageName)' not found - building it now (one-time, this can take a few minutes)"
        & (Join-Path $PSScriptRoot 'Build-ArchImage.ps1')
        if (-not (Test-ImageExists $cfg.ImageName)) {
            throw "Image build did not produce '$($cfg.ImageName)'; cannot start."
        }
    }

    Write-Step "Creating and starting container '$($cfg.ContainerName)'"
    $runArgs = @(
        'run', '-d'
        '--name', $cfg.ContainerName
        '--hostname', $cfg.Hostname
        '--platform', $cfg.Platform
        # SSH port, bound to localhost only (nothing listens until sshd is started).
        '--publish', "127.0.0.1:$($cfg.SshHostPort):22"
        '--volume', "$($cfg.VolumeName):$($cfg.MountPath)"
    )
    if ($cfg.StartSshOnBoot) {
        # Producer of the ARCH_START_SSHD contract consumed by docker/entrypoint.sh (which
        # starts sshd on boot when it sees =1 and a key is present). Keep the name in sync.
        $runArgs += @('--env', 'ARCH_START_SSHD=1')
    }
    $runArgs += $cfg.ImageName
    Invoke-Docker -Arguments $runArgs -FailMessage 'Failed to create container.'

    Write-Ok "Container '$($cfg.ContainerName)' created and running."
    Write-Info "Enter it with: ./scripts/Enter-ArchContainer.ps1"
}

# Optional top-up: install config Packages not already in the (possibly prebuilt) image.
# `pacman -T` is a fast, offline check, so this is a no-op when everything is present (always
# the case for a locally-built image). Installs into the writable layer (re-applied on each
# recreate, lost on remove), so it's a convenience for using a prebuilt BaseImage without
# rebuilding, NOT a substitute for baking packages into the image.
if ($cfg.SupplementPackages) {
    Write-Step 'Supplementing packages from config (installing any not already present)'
    $topUp = @'
set -euo pipefail
missing=$(pacman -T "$@" || true)
if [ -n "$missing" ]; then
    echo "installing: $missing"
    # -Sy (partial sync), not -Syu: install just the missing delta into the writable layer.
    # A full upgrade would be heavy on every Start, and these packages are transient anyway.
    sudo pacman -Sy --needed --noconfirm $missing
else
    echo "all configured packages already present"
fi
'@
    try {
        Invoke-ContainerScript -Script $topUp -ScriptArgs $cfg.Packages
    }
    catch {
        Write-Warning "Package supplement failed (container is up): $($_.Exception.Message)"
    }
}

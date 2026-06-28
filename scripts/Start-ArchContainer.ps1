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
    return
}

if (Test-ContainerExists $cfg.ContainerName) {
    Write-Step "Starting existing container '$($cfg.ContainerName)'"
    Invoke-Docker -Arguments @('start', $cfg.ContainerName) -FailMessage 'Failed to start container.'
    Write-Ok 'Started.'
    return
}

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

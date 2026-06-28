#Requires -Version 7
<#
.SYNOPSIS
    Remove the arch-aarch64 container. Optionally also remove the persistent home
    volume and/or the image.
.PARAMETER RemoveVolume
    Also delete the named home volume (DESTROYS the dev user's persisted data).
    Prompts for confirmation unless -Force is given.
.PARAMETER RemoveImage
    Also delete the built image.
.PARAMETER Force
    Do not prompt before removing the volume.
.EXAMPLE
    ./scripts/Remove-ArchContainer.ps1
.EXAMPLE
    ./scripts/Remove-ArchContainer.ps1 -RemoveVolume -RemoveImage -Force
#>
[CmdletBinding()]
param(
    [switch]$RemoveVolume,
    [switch]$RemoveImage,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

$cfg = Get-ArchConfig
Test-DockerRunning

if (Test-ContainerExists $cfg.ContainerName) {
    Write-Step "Removing container '$($cfg.ContainerName)'"
    Invoke-Docker -Arguments @('rm', '-f', $cfg.ContainerName) -FailMessage 'Failed to remove container.'
    Write-Ok 'Container removed.'
}
else {
    Write-Info "Container '$($cfg.ContainerName)' does not exist."
}

if ($RemoveVolume) {
    if (-not (Test-VolumeExists $cfg.VolumeName)) {
        Write-Info "Volume '$($cfg.VolumeName)' does not exist."
    }
    elseif ($Force -or $PSCmdlet.ShouldContinue(
            "Permanently delete volume '$($cfg.VolumeName)' and all data in $($cfg.MountPath)?",
            'Confirm volume removal')) {
        Invoke-Docker -Arguments @('volume', 'rm', $cfg.VolumeName) -FailMessage 'Failed to remove volume.'
        Write-Ok 'Volume removed.'
    }
    else {
        Write-Info 'Volume kept.'
    }
}

if ($RemoveImage) {
    if (Test-ImageExists $cfg.ImageName) {
        Write-Step "Removing image '$($cfg.ImageName)'"
        Invoke-Docker -Arguments @('rmi', $cfg.ImageName) -FailMessage 'Failed to remove image.'
        Write-Ok 'Image removed.'
    }
    else {
        Write-Info "Image '$($cfg.ImageName)' does not exist."
    }
}

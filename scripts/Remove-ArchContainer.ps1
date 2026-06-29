#Requires -Version 7
<#
.SYNOPSIS
    Remove the arch-aarch64 container. Optionally also remove the persistent home
    volume and/or the image.
.PARAMETER RemoveVolume
    Also delete the named home volume (DESTROYS the dev user's persisted data).
    Prompts for confirmation unless -Force is given.
.PARAMETER RemoveImage
    Also remove the local image tag (config ImageName, e.g. arch-aarch64:latest). For a
    FROM-scratch build this deletes the image and frees its disk. When ImageName was tagged
    from a pulled BaseImage, it shares one image ID with the source tag, so this only untags
    the local name - the source (e.g. the GHCR image) stays cached for a fast re-tag; `docker
    rmi` it directly to reclaim that space.
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
        # The persisted SSH host identity lived in that volume, so a recreated container
        # gets a new host key. Remind how to clear the now-stale known_hosts entry.
        Write-Info "SSH host identity was reset. If you re-enable SSH, clear the old key on your host:"
        Write-Info "  ssh-keygen -R '[127.0.0.1]:$($cfg.SshHostPort)'"
    }
    else {
        Write-Info 'Volume kept.'
    }
}

if ($RemoveImage) {
    if (Test-ImageExists $cfg.ImageName) {
        Write-Step "Removing image '$($cfg.ImageName)'"
        # Capture the underlying image ID first. If other tags (e.g. a pulled BaseImage's GHCR
        # tag) point at the same ID, `docker rmi <name>` only untags our local name and the
        # image data stays cached - report that honestly rather than claiming it was deleted.
        $imageId = docker images -q $cfg.ImageName | Select-Object -First 1
        Invoke-Docker -Arguments @('rmi', $cfg.ImageName) -FailMessage 'Failed to remove image.'
        $remainingTags = if ($imageId) {
            docker image inspect $imageId --format '{{join .RepoTags ", "}}' 2>$null
        }
        if ($LASTEXITCODE -eq 0 -and $remainingTags) {
            Write-Ok "Untagged '$($cfg.ImageName)' - image data kept (still tagged: $remainingTags)."
            Write-Info "To reclaim the disk, remove that tag too: docker rmi $remainingTags"
        }
        else {
            Write-Ok 'Image removed.'
        }
    }
    else {
        Write-Info "Image '$($cfg.ImageName)' does not exist."
    }
}

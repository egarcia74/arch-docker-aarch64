#Requires -Version 7
<#
.SYNOPSIS
    Show the container and data-volume state for the configured Arch container.
.EXAMPLE
    ./scripts/Get-ArchStatus.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

$cfg = Get-ArchConfig
Test-DockerRunning

# Anchored filters (^/name$ / ^name$) match exactly, like the _Common Test-* helpers,
# so the volume isn't matched only by sharing the container's name prefix.
Write-Step "Container '$($cfg.ContainerName)'"
docker ps -a --filter "name=^/$($cfg.ContainerName)$" --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'

Write-Step "Volume '$($cfg.VolumeName)'"
docker volume ls --filter "name=^$($cfg.VolumeName)$" --format 'table {{.Driver}}\t{{.Name}}'

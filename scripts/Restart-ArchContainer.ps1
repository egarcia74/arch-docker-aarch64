#Requires -Version 7
<#
.SYNOPSIS
    Restart the arch-aarch64 container.
.EXAMPLE
    ./scripts/Restart-ArchContainer.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

$cfg = Get-ArchConfig
Test-DockerRunning

if (-not (Test-ContainerExists $cfg.ContainerName)) {
    throw "Container '$($cfg.ContainerName)' does not exist. Create it with ./scripts/Start-ArchContainer.ps1"
}

Write-Step "Restarting '$($cfg.ContainerName)'"
Invoke-Docker -Arguments @('restart', $cfg.ContainerName) -FailMessage 'Failed to restart container.'
Write-Ok 'Restarted.'

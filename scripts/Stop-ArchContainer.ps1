#Requires -Version 7
<#
.SYNOPSIS
    Stop the running arch-aarch64 container. Idempotent.
.EXAMPLE
    ./scripts/Stop-ArchContainer.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

$cfg = Get-ArchConfig
Test-DockerRunning

if (-not (Test-ContainerExists $cfg.ContainerName)) {
    Write-Info "Container '$($cfg.ContainerName)' does not exist; nothing to stop."
    return
}
if (-not (Test-ContainerRunning $cfg.ContainerName)) {
    Write-Ok "Container '$($cfg.ContainerName)' is already stopped."
    return
}

Write-Step "Stopping '$($cfg.ContainerName)'"
Invoke-Docker -Arguments @('stop', $cfg.ContainerName) -FailMessage 'Failed to stop container.'
Write-Ok 'Stopped.'

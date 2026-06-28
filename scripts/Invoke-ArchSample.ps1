#Requires -Version 7
<#
.SYNOPSIS
    Run a use-case init script from samples/ inside the container as the dev user.
.DESCRIPTION
    Streams samples/setup-<Name>.sh into the running container's bash. Ensures the
    container is running first. Omit -Name to list available samples.
.PARAMETER Name
    Sample name without the 'setup-' prefix or '.sh' suffix (e.g. dotnet, rust, go,
    build-tools, ssh).
.EXAMPLE
    ./scripts/Invoke-ArchSample.ps1            # list samples
.EXAMPLE
    ./scripts/Invoke-ArchSample.ps1 -Name dotnet
#>
[CmdletBinding()]
param(
    [string]$Name
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

$cfg = Get-ArchConfig
$samplesDir = Join-Path $RepoRoot 'samples'

$available = Get-ChildItem $samplesDir -Filter 'setup-*.sh' |
    ForEach-Object { $_.BaseName -replace '^setup-', '' } | Sort-Object

if (-not $Name) {
    Write-Step 'Available samples (run with -Name <name>):'
    $available | ForEach-Object { Write-Info $_ }
    return
}

$file = Join-Path $samplesDir "setup-$Name.sh"
if (-not (Test-Path $file)) {
    throw "Unknown sample '$Name'. Available: $($available -join ', ')"
}

Test-DockerRunning
Assert-ContainerRunning $cfg.ContainerName

Write-Step "Running sample '$Name' inside '$($cfg.ContainerName)'"
Invoke-ContainerScript -Script (Get-Content -Raw $file) -FailMessage "Sample '$Name' failed."
Write-Ok "Sample '$Name' complete."

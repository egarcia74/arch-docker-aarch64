#Requires -Version 7
<#
.SYNOPSIS
    Run the Pester test suite in tests/.
.PARAMETER CI
    Emit a NUnit results file and set a failing exit code on test failures.
.EXAMPLE
    ./scripts/Invoke-Tests.ps1
#>
[CmdletBinding()]
param(
    [switch]$CI
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

Assert-Module -Name Pester -MinimumVersion 5.0 -InstallHint 'Run: Install-Module Pester -Scope CurrentUser -MinimumVersion 5.0'
Import-Module Pester -MinimumVersion 5.0

Write-Step 'Running Pester tests'
$config = New-PesterConfiguration
$config.Run.Path = Join-Path $RepoRoot 'tests'
$config.Output.Verbosity = 'Detailed'
if ($CI) {
    $config.Run.Exit = $true
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = Join-Path $RepoRoot 'tests/testresults.xml'
}
Invoke-Pester -Configuration $config

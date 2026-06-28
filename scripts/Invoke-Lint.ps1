#Requires -Version 7
<#
.SYNOPSIS
    Run PSScriptAnalyzer over scripts/ using the project settings. Throws if any
    finding is reported (suitable for CI / pre-commit).
.EXAMPLE
    ./scripts/Invoke-Lint.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

Assert-Module -Name PSScriptAnalyzer -InstallHint 'Run: Install-Module PSScriptAnalyzer -Scope CurrentUser'

$settings = Join-Path $RepoRoot 'config/PSScriptAnalyzerSettings.psd1'
Write-Step 'Running PSScriptAnalyzer over scripts/'
$results = Invoke-ScriptAnalyzer -Path $PSScriptRoot -Recurse -Settings $settings

if ($results) {
    $results | Sort-Object ScriptName, Line |
        Format-Table @{ L = 'Sev'; E = { $_.Severity } },
            @{ L = 'File'; E = { Split-Path $_.ScriptName -Leaf } },
            Line, RuleName, Message -AutoSize -Wrap
    throw "PSScriptAnalyzer reported $($results.Count) issue(s)."
}

Write-Ok 'PSScriptAnalyzer: 0 issues.'

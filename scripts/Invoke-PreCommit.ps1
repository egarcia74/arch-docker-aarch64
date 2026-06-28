#Requires -Version 7
<#
.SYNOPSIS
    Pre-commit quality gate: PSScriptAnalyzer, Pester, and Markdown lint/format check.
.DESCRIPTION
    Runs every check (collecting all results rather than failing fast) and exits
    non-zero if any fail. Suitable to wire as a git pre-commit hook once the repo is
    initialised, e.g. a .git/hooks/pre-commit that runs:
        pwsh -NoProfile -File ./scripts/Invoke-PreCommit.ps1
.EXAMPLE
    ./scripts/Invoke-PreCommit.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

# Each check runs in its own pwsh process: one failure neither aborts the others nor
# (via Pester's Run.Exit) terminates this aggregator, and we collect every result.
$steps = @(
    @{ Name = 'PSScriptAnalyzer'; File = 'Invoke-Lint.ps1';     Args = @() }
    @{ Name = 'Pester tests';     File = 'Invoke-Tests.ps1';    Args = @('-CI') }
    @{ Name = 'Markdown';         File = 'Format-Markdown.ps1'; Args = @('-Check') }
)

# Collect into an explicit list so each child's streamed stdout goes to the host
# rather than being captured into $results alongside the status objects.
$results = [System.Collections.Generic.List[object]]::new()
foreach ($step in $steps) {
    Write-Step "Pre-commit: $($step.Name)"
    $path = Join-Path $PSScriptRoot $step.File
    $stepArgs = $step.Args
    & pwsh -NoProfile -File $path @stepArgs
    $results.Add([pscustomobject]@{ Name = $step.Name; Passed = ($LASTEXITCODE -eq 0) })
}

Write-Step 'Pre-commit summary'
foreach ($r in $results) {
    if ($r.Passed) { Write-Ok $r.Name } else { Write-Fail $r.Name }
}

$failed = @($results | Where-Object { -not $_.Passed })
if ($failed) {
    throw "Pre-commit FAILED: $($failed.Count) of $($results.Count) check(s) did not pass."
}
Write-Ok 'All pre-commit checks passed.'

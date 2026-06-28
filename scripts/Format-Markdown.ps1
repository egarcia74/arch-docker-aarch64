#Requires -Version 7
<#
.SYNOPSIS
    Format and lint Markdown with prettier + markdownlint-cli2 (via npx).
.DESCRIPTION
    Default: prettier --write, then markdownlint-cli2 --fix (modifies files).
    -Check:  prettier --check, then markdownlint-cli2 (no writes); throws on issues,
             suitable for CI / pre-commit.
    Uses npx, which runs the versions pinned in package.json if `npm install` has been
    run, otherwise fetches them on demand.
.EXAMPLE
    ./scripts/Format-Markdown.ps1
.EXAMPLE
    ./scripts/Format-Markdown.ps1 -Check
#>
[CmdletBinding()]
param(
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

Assert-Command -Name npx -InstallHint 'Install Node.js to run the Markdown tooling.'

$mdGlob = '**/*.md'
Push-Location $RepoRoot
try {
    if ($Check) {
        Write-Step 'Checking Markdown formatting (prettier --check)'
        npx --yes prettier --check $mdGlob
        if ($LASTEXITCODE -ne 0) { throw 'prettier found unformatted files. Run without -Check to fix.' }

        Write-Step 'Linting Markdown (markdownlint-cli2)'
        npx --yes markdownlint-cli2
        if ($LASTEXITCODE -ne 0) { throw 'markdownlint-cli2 reported issues.' }
    }
    else {
        Write-Step 'Formatting Markdown (prettier --write)'
        npx --yes prettier --write $mdGlob
        if ($LASTEXITCODE -ne 0) { throw 'prettier failed.' }

        Write-Step 'Auto-fixing Markdown (markdownlint-cli2 --fix)'
        npx --yes markdownlint-cli2 --fix
        if ($LASTEXITCODE -ne 0) { Write-Warning 'markdownlint-cli2 reported issues it could not auto-fix (see above).' }
    }
    Write-Ok 'Markdown tooling complete.'
}
finally {
    Pop-Location
}

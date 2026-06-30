#Requires -Version 7
<#
.SYNOPSIS
    Load short `arch <command>` shortcuts for the lifecycle scripts into the current pwsh session.
.DESCRIPTION
    Dot-source this file to use it - for this session only, or from your $PROFILE for every session:

        . ./scripts/arch.ps1
        # permanent: add  . /full/path/to/scripts/arch.ps1  to $PROFILE

    Then drive everything with one verb (tab-completes; run `arch help` for the list):

        arch build [-NoCache -ForceDownload]      arch start | stop | restart
        arch enter [cmd]   (alias: shell)         arch status
        arch ssh                                  arch sample <name>
        arch rm [-RemoveImage -RemoveVolume]      (alias: remove)

    Each verb just invokes the matching scripts/*.ps1 and passes any extra args straight through,
    so every flag the underlying script accepts works unchanged - e.g. `arch enter htop`,
    `arch build -NoCache`, `arch sample dotnet`, `arch rm -RemoveImage`.

    NOTE: unlike the other scripts, this loader intentionally does NOT set `Set-StrictMode` or
    `$ErrorActionPreference` at file scope - dot-sourcing would leak those into your interactive
    session. The lifecycle scripts it calls set their own (in their own scope) as usual.
#>

# Must be DOT-SOURCED. Run normally, the shortcuts get defined in a child scope that vanishes
# on exit - and `arch` would then fall through to the macOS /usr/bin/arch binary, so a later
# `arch help` fails confusingly. Detect that and guide the user instead of printing a
# misleading "loaded" message. ($MyInvocation.InvocationName is '.' only when dot-sourced.)
if ($MyInvocation.InvocationName -ne '.') {
    Write-Warning 'arch.ps1 only works when DOT-SOURCED (note the leading ". "):'
    Write-Warning "    . $PSCommandPath"
    Write-Warning 'Add that line to your $PROFILE to load the shortcuts in every session.'
    return
}

# Resolved once at load (this file lives in scripts/), so `arch ...` works from any directory.
$script:ArchScriptsDir = $PSScriptRoot

# verb -> script. 'shell' and 'rm' are convenience aliases of 'enter' and 'remove'.
$script:ArchCommands = [ordered]@{
    build   = 'Build-ArchImage.ps1'
    start   = 'Start-ArchContainer.ps1'
    stop    = 'Stop-ArchContainer.ps1'
    restart = 'Restart-ArchContainer.ps1'
    enter   = 'Enter-ArchContainer.ps1'
    shell   = 'Enter-ArchContainer.ps1'
    status  = 'Get-ArchStatus.ps1'
    ssh     = 'Enable-ArchSsh.ps1'
    sample  = 'Invoke-ArchSample.ps1'
    remove  = 'Remove-ArchContainer.ps1'
    rm      = 'Remove-ArchContainer.ps1'
}

function arch {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Command = 'help',
        [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    if ($Command -in 'help', '-h', '--help', '/?') {
        Write-Host 'arch <command> [args] - shortcuts for the arch-aarch64 lifecycle scripts' -ForegroundColor Cyan
        $usage = [ordered]@{
            'build [-NoCache -ForceDownload]'  = 'Build (or pull a BaseImage) the image'
            'start | stop | restart'           = 'Container lifecycle'
            'enter [cmd]   (alias: shell)'     = 'Shell in as dev, or run one command (e.g. arch enter htop)'
            'status'                           = 'Show container + volume state'
            'ssh'                              = 'Install key + start sshd'
            'sample <name>'                    = 'Run a samples/ use-case (dotnet/rust/go/build-tools/ssh)'
            'rm [-RemoveImage -RemoveVolume]'  = 'Remove the container (alias: remove)'
        }
        foreach ($key in $usage.Keys) { Write-Host ('  {0,-34} {1}' -f $key, $usage[$key]) }
        return
    }

    $scriptName = $script:ArchCommands[$Command]
    if (-not $scriptName) {
        Write-Error "Unknown command 'arch $Command'. Run 'arch help' for the list."
        return
    }
    $target = Join-Path $script:ArchScriptsDir $scriptName
    # Only splat when there are extra args; @Rest on an empty/$null value would pass a stray
    # argument to scripts that take none (e.g. `arch status`).
    if ($Rest) { & $target @Rest } else { & $target }
}

# Tab-complete the verb. The list is captured by closure so it resolves at completion time
# regardless of scope.
$archVerbs = @($script:ArchCommands.Keys) + 'help'
Register-ArgumentCompleter -CommandName arch -ParameterName Command -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    $null = $commandName, $parameterName # required by the completer signature; unused here
    $archVerbs |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}.GetNewClosure()

Write-Host "Loaded 'arch' shortcuts (run 'arch help')." -ForegroundColor Green

#Requires -Version 7
# Shared configuration loader and helpers. Dot-source from every lifecycle script:
#   . (Join-Path $PSScriptRoot '_Common.ps1')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ScriptsDir = $PSScriptRoot
$script:RepoRoot   = Split-Path -Parent $PSScriptRoot
$script:ConfigPath = Join-Path $script:RepoRoot 'config/container.psd1'

# Single source for the required config keys: enforced by Confirm-ArchConfig and
# enumerated by tests/Config.Tests.ps1 (which dot-sources this file to read it).
$script:RequiredConfigKeys = @(
    'ImageName', 'BaseImage', 'ContainerName', 'Hostname', 'VolumeName', 'Platform',
    'RootfsUrl', 'Packages', 'DevUser', 'SshHostPort', 'StartSshOnBoot', 'SupplementPackages'
)

function Get-ArchConfig {
    <#  .SYNOPSIS Load config/container.psd1 as a hashtable, with derived values. #>
    if (-not (Test-Path $script:ConfigPath)) {
        throw "Config file not found: $script:ConfigPath"
    }
    $cfg = Import-PowerShellDataFile -Path $script:ConfigPath
    # Optional gitignored local overrides, merged over the base (local keys win) so you
    # can experiment without editing/committing container.psd1.
    $localPath = Join-Path $script:RepoRoot 'config/container.local.psd1'
    if (Test-Path $localPath) {
        $local = Import-PowerShellDataFile -Path $localPath
        foreach ($key in $local.Keys) { $cfg[$key] = $local[$key] }
    }
    # The persisted mount is the dev user's home; derive it so DevUser is the
    # single knob for "who and where" (keeps it from drifting out of sync).
    $cfg.MountPath = "/home/$($cfg.DevUser)"
    Confirm-ArchConfig $cfg
    $cfg
}

function Confirm-ArchConfig {
    <#  .SYNOPSIS Validate a loaded config so bad values (incl. local overrides) fail fast
        with a clear message instead of surfacing as an obscure error much later. #>
    param([Parameter(Mandatory)][hashtable]$Config)

    foreach ($key in $script:RequiredConfigKeys) {
        if (-not $Config.ContainsKey($key)) { throw "Config: required key '$key' is missing." }
    }
    foreach ($key in 'ImageName', 'ContainerName', 'Hostname', 'VolumeName') {
        if ($Config[$key] -isnot [string] -or [string]::IsNullOrWhiteSpace($Config[$key])) {
            throw "Config: $key must be a non-empty string."
        }
    }
    # Docker object names / hostnames: alphanumeric start, then a restricted set.
    foreach ($key in 'ContainerName', 'VolumeName') {
        if ($Config[$key] -notmatch '^[a-zA-Z0-9][\w.-]*$') {
            throw "Config: $key '$($Config[$key])' is not a valid Docker name."
        }
    }
    if ($Config.Hostname -notmatch '^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$') {
        throw "Config: Hostname '$($Config.Hostname)' is not a valid hostname."
    }
    if ($Config.Platform -notmatch '^[\w.-]+/[\w./-]+$') {
        throw "Config: Platform '$($Config.Platform)' is not a valid '<os>/<arch>' value."
    }
    if (-not [uri]::IsWellFormedUriString($Config.RootfsUrl, [System.UriKind]::Absolute)) {
        throw "Config: RootfsUrl '$($Config.RootfsUrl)' is not a valid absolute URI."
    }
    if ($Config.SshHostPort -isnot [int] -or $Config.SshHostPort -lt 1 -or $Config.SshHostPort -gt 65535) {
        throw "Config: SshHostPort '$($Config.SshHostPort)' must be an integer in 1..65535."
    }
    if ($Config.Packages -isnot [array] -or $Config.Packages.Count -eq 0) {
        throw 'Config: Packages must be a non-empty array.'
    }
    if ($Config.DevUser -notmatch '^[a-z_][a-z0-9_-]*$') {
        throw "Config: DevUser '$($Config.DevUser)' is not a valid Linux username."
    }
    if ($Config.StartSshOnBoot -isnot [bool]) {
        throw 'Config: StartSshOnBoot must be a boolean ($true/$false).'
    }
    if ($Config.SupplementPackages -isnot [bool]) {
        throw 'Config: SupplementPackages must be a boolean ($true/$false).'
    }
    if ($Config.BaseImage -isnot [string]) {
        throw 'Config: BaseImage must be a string ('''' to build locally).'
    }
}

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Info { param([string]$Message) Write-Host "    $Message" -ForegroundColor Gray }
function Write-Ok   { param([string]$Message) Write-Host "[ok] $Message"   -ForegroundColor Green }
function Write-Fail { param([string]$Message) Write-Host "[fail] $Message" -ForegroundColor Red }

function Invoke-Docker {
    <#  .SYNOPSIS Run docker with the given args, suppressing its echo and throwing
        $FailMessage on a non-zero exit. For mutating commands whose stdout (a
        container/volume id or name) is noise; not for streaming commands like build. #>
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$FailMessage
    )
    docker @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw $FailMessage }
}

function Assert-Module {
    <#  .SYNOPSIS Throw a clear, install-hinted error unless a module (optionally at a
        minimum version) is available. #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [version]$MinimumVersion,
        [string]$InstallHint
    )
    $found = Get-Module -ListAvailable -Name $Name
    if ($MinimumVersion) { $found = $found | Where-Object { $_.Version -ge $MinimumVersion } }
    if (-not $found) {
        $version = if ($MinimumVersion) { " (>= $MinimumVersion)" } else { '' }
        $hint = if ($InstallHint) { " $InstallHint" } else { '' }
        throw "Required module '$Name'$version not found.$hint"
    }
}

function Assert-Command {
    <#  .SYNOPSIS Throw a clear, install-hinted error unless a command is on PATH. #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$InstallHint
    )
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        $hint = if ($InstallHint) { " $InstallHint" } else { '' }
        throw "Required command '$Name' not found on PATH.$hint"
    }
}

function Confirm-BaseImageSignature {
    <#  .SYNOPSIS Best-effort keyless-cosign verification of a prebuilt base image before it is
        adopted (a signature only protects you if it is checked at the point of consumption, and
        the BaseImage pull IS that point). Verifies GHCR images signed by this repo's CI: the
        certificate identity is derived from the image ref (ghcr.io/<owner>/<repo> -> the repo's
        GitHub URL) so forks/renames work without config. cosign absent -> warn and continue;
        a present-but-FAILED verification throws so the caller never tags an unverified image. #>
    param([Parameter(Mandatory)][string]$ImageRef)

    if (-not (Get-Command cosign -ErrorAction SilentlyContinue)) {
        Write-Warning "cosign not found - skipping signature verification of '$ImageRef'. Install it (e.g. 'brew install cosign') to verify image provenance before use."
        return
    }
    # Strip any @digest then a trailing :tag (a ':' after the last '/') to get the bare repo ref.
    $noDigest = ($ImageRef -split '@', 2)[0]
    $lastSlash = $noDigest.LastIndexOf('/')
    $lastColon = $noDigest.LastIndexOf(':')
    $repoRef = if ($lastColon -gt $lastSlash) { $noDigest.Substring(0, $lastColon) } else { $noDigest }
    if ($repoRef -notlike 'ghcr.io/*/*') {
        Write-Warning "Cannot infer a signing identity for '$ImageRef' (not a ghcr.io/<owner>/<repo> image) - skipping verification."
        return
    }
    $ownerRepo = $repoRef.Substring('ghcr.io/'.Length)

    Write-Info "Verifying cosign signature for '$ImageRef'"
    cosign verify $ImageRef `
        --certificate-identity-regexp "^https://github.com/$ownerRepo/" `
        --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "cosign signature verification FAILED for '$ImageRef' - refusing to use an unverified image. Set BaseImage to a trusted signed image, or remove it to build locally."
    }
    Write-Ok "Signature verified (built + signed by github.com/$ownerRepo CI)."
}

function Test-DockerRunning {
    <#  .SYNOPSIS Throw a clear error unless the Docker daemon is reachable. #>
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker CLI not found on PATH. Install/start Docker Desktop.'
    }
    docker info --format '{{.ServerVersion}}' *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker daemon is not running. Start Docker Desktop and retry.'
    }
}

function Test-ContainerExists {
    param([Parameter(Mandatory)][string]$Name)
    [bool](docker ps -a --filter "name=^/$Name$" --format '{{.ID}}')
}

function Test-ContainerRunning {
    param([Parameter(Mandatory)][string]$Name)
    [bool](docker ps --filter "name=^/$Name$" --format '{{.ID}}')
}

function Test-ImageExists {
    param([Parameter(Mandatory)][string]$Name)
    [bool](docker images -q $Name)
}

function Test-VolumeExists {
    param([Parameter(Mandatory)][string]$Name)
    [bool](docker volume ls -q --filter "name=^$Name$")
}

function Assert-ContainerRunning {
    <#  .SYNOPSIS Ensure the container is running: start it (which builds the image if
        missing) when it is down, then throw if it still isn't up. #>
    param([Parameter(Mandatory)][string]$Name)
    if (Test-ContainerRunning $Name) { return }
    Write-Step "Container '$Name' is not running - starting it"
    & (Join-Path $script:ScriptsDir 'Start-ArchContainer.ps1')
    if (-not (Test-ContainerRunning $Name)) {
        throw "Could not start container '$Name'."
    }
}

function Invoke-ContainerScript {
    <#  .SYNOPSIS Stream a script to `bash -s` in the container as the dev user (in the
        home dir), passing optional positional args, and throw $FailMessage on failure. #>
    param(
        [Parameter(Mandatory)][string]$Script,
        [string[]]$ScriptArgs = @(),
        [string]$FailMessage = 'In-container script failed.'
    )
    $cfg = Get-ArchConfig
    $Script | docker exec -i -u $cfg.DevUser -w $cfg.MountPath $cfg.ContainerName bash -s @ScriptArgs
    if ($LASTEXITCODE -ne 0) { throw $FailMessage }
}

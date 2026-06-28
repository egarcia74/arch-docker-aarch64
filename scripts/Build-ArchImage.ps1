#Requires -Version 7
<#
.SYNOPSIS
    Download the Arch Linux ARM (aarch64) rootfs and build the native arch-aarch64 image.
.PARAMETER NoCache
    Build without using Docker's layer cache.
.PARAMETER SkipChecksum
    Do not verify the downloaded tarball's MD5.
.PARAMETER ForceDownload
    Re-download the rootfs even if a cached copy exists.
.EXAMPLE
    ./scripts/Build-ArchImage.ps1
.EXAMPLE
    ./scripts/Build-ArchImage.ps1 -NoCache -ForceDownload
#>
[CmdletBinding()]
param(
    [switch]$NoCache,
    [switch]$SkipChecksum,
    [switch]$ForceDownload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

$cfg = Get-ArchConfig
Test-DockerRunning

$dockerDir   = Join-Path $RepoRoot 'docker'
$tarballName = Split-Path -Leaf ([Uri]$cfg.RootfsUrl).AbsolutePath
$tarballPath = Join-Path $dockerDir $tarballName

Write-Step "Preparing Arch Linux ARM rootfs ($tarballName)"
if ($ForceDownload -and (Test-Path $tarballPath)) {
    Remove-Item $tarballPath -Force
}
if (Test-Path $tarballPath) {
    Write-Info "Using cached tarball (pass -ForceDownload to refresh)."
}
else {
    Write-Info "Downloading $($cfg.RootfsUrl)"
    Invoke-WebRequest -Uri $cfg.RootfsUrl -OutFile $tarballPath
}

if (-not $SkipChecksum) {
    try {
        Write-Info 'Verifying MD5 checksum'
        # The .md5 endpoint is served as octet-stream, so .Content can be a byte[];
        # decode to text before parsing "<hash>  <filename>".
        $md5Raw = Invoke-RestMethod -Uri "$($cfg.RootfsUrl).md5"
        if ($md5Raw -is [byte[]]) { $md5Raw = [System.Text.Encoding]::ASCII.GetString($md5Raw) }
        $expected = (([string]$md5Raw).Trim() -split '\s+')[0].ToLower()
        # MD5 is the format ALARM publishes; this only matches the download, it is not
        # a security control. (Rule excluded in config/PSScriptAnalyzerSettings.psd1.)
        $actual   = (Get-FileHash -Path $tarballPath -Algorithm MD5).Hash.ToLower()
        if ($expected -and $actual -ne $expected) {
            throw "Checksum mismatch: expected $expected, got $actual. Re-run with -ForceDownload."
        }
        Write-Ok 'Checksum verified.'
    }
    catch {
        Write-Warning "Checksum verification could not be completed: $($_.Exception.Message)"
    }
}

Write-Step "Building image $($cfg.ImageName)"
$buildArgs = @(
    'build'
    '--platform', $cfg.Platform
    '-t', $cfg.ImageName
    '-f', (Join-Path $dockerDir 'Dockerfile')
    '--build-arg', "PACKAGES=$($cfg.Packages -join ' ')"
    '--build-arg', "DEV_USER=$($cfg.DevUser)"
)
if ($NoCache) { $buildArgs += '--no-cache' }
$buildArgs += $dockerDir

docker @buildArgs
if ($LASTEXITCODE -ne 0) { throw 'docker build failed.' }

Write-Ok "Image '$($cfg.ImageName)' built. Start it with ./scripts/Start-ArchContainer.ps1"

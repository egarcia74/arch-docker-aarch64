#Requires -Version 7
<#
.SYNOPSIS
    Produce the local arch-aarch64 image: build FROM scratch by downloading the Arch Linux ARM
    (aarch64) rootfs, OR, when config BaseImage is set, pull and tag that prebuilt image instead.
.DESCRIPTION
    SECURITY: the rootfs defaults to a trusted HTTPS mirror (fl.us.mirror.archlinuxarm.org,
    valid Let's Encrypt cert) and is verified against an MD5 from that same mirror. HTTPS
    authenticates transport (defeats passive eavesdrop + cert-forging MITM); the MD5 catches
    corruption. Residual trust is in the mirror operator - ALARM does not sign the rootfs
    tarball, and the canonical origin os.archlinuxarm.org is plain HTTP with an invalid cert.
    CI builds run with -StrictChecksum so a verification failure is fatal there.
    When config BaseImage is set instead of building, the pulled image's keyless cosign
    signature is verified before it is adopted (best-effort: a warning if cosign is not
    installed, fatal if an installed cosign rejects the signature). See Confirm-BaseImageSignature.
.PARAMETER NoCache
    Build without using Docker's layer cache.
.PARAMETER SkipChecksum
    Do not verify the downloaded tarball's MD5.
.PARAMETER StrictChecksum
    Make any checksum failure (retrieval, parse, or mismatch) fatal instead of a warning.
    CI passes this explicitly; local dev defaults to a warning so a flaky mirror doesn't block.
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
    [switch]$StrictChecksum,
    [switch]$ForceDownload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

$cfg = Get-ArchConfig
Test-DockerRunning

if ($cfg.BaseImage) {
    # Fast path: pull a prebuilt, fully-built image (e.g. the project's GHCR image) and tag
    # it as our local image name, skipping the FROM-scratch rootfs download + build. The rest
    # of the lifecycle (Start/Enter/Status) keeps using $cfg.ImageName unchanged.
    Write-Step "Using prebuilt base image '$($cfg.BaseImage)' (skipping the local build)"
    docker pull --platform $cfg.Platform $cfg.BaseImage
    if ($LASTEXITCODE -ne 0) { throw "Failed to pull base image '$($cfg.BaseImage)'." }
    # Verify provenance before adopting the pulled image (best-effort: warns if cosign is
    # absent, fatal if a present cosign rejects the signature). This is the consumption-point
    # check that makes the CI signing actually protect a local pull.
    Confirm-BaseImageSignature -ImageRef $cfg.BaseImage
    Invoke-Docker -Arguments @('tag', $cfg.BaseImage, $cfg.ImageName) -FailMessage 'Failed to tag base image.'
    Write-Ok "Tagged '$($cfg.BaseImage)' as '$($cfg.ImageName)'."
    return
}

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
    # -StrictChecksum (passed by CI) makes a failure fatal; local dev warns so a flaky mirror
    # doesn't block work. See the SECURITY note above on what this does and doesn't protect.
    try {
        Write-Info 'Verifying MD5 checksum'
        # The .md5 endpoint is served as octet-stream, so .Content can be a byte[];
        # decode to text before parsing "<hash>  <filename>".
        $md5Raw = Invoke-RestMethod -Uri "$($cfg.RootfsUrl).md5"
        if ($md5Raw -is [byte[]]) { $md5Raw = [System.Text.Encoding]::ASCII.GetString($md5Raw) }
        $expected = (([string]$md5Raw).Trim() -split '\s+')[0].ToLower()
        $actual = (Get-FileHash -Path $tarballPath -Algorithm MD5).Hash.ToLower()
        if (-not $expected) { throw 'could not parse the published MD5.' }
        if ($actual -ne $expected) { throw "mismatch: expected $expected, got $actual." }
        Write-Ok 'Checksum verified.'
    }
    catch {
        $detail = "Checksum verification failed: $($_.Exception.Message)"
        if ($StrictChecksum) {
            throw "$detail (strict mode) Re-run with -ForceDownload, or -SkipChecksum to bypass."
        }
        Write-Warning "$detail Continuing (local dev); use -StrictChecksum to make this fatal."
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

@{
    # Single source of truth for all lifecycle scripts and the Docker build.
    ImageName     = 'arch-aarch64:latest'

    # BaseImage: empty = build locally FROM scratch (default). Set to a prebuilt image that
    # is equivalent to this project's build — e.g. 'ghcr.io/egarcia74/arch-docker-aarch64:latest'
    # — to pull and use it directly, skipping the ~784 MB rootfs download + build. Must be a
    # fully-built compatible image (dev user + entrypoint), NOT a bare Arch rootfs.
    # CAVEAT: build-time settings (Packages, DevUser) are baked into a prebuilt image, so they
    # do NOT apply when BaseImage is set — only runtime settings (Hostname, SshHostPort,
    # StartSshOnBoot, volume) still take effect via Start. Leave BaseImage empty to apply Packages.
    BaseImage     = ''

    ContainerName = 'arch-aarch64'
    Hostname      = 'arch-aarch64'
    VolumeName    = 'arch-aarch64-home'
    Platform      = 'linux/arm64'
    SshHostPort   = 2222
    StartSshOnBoot = $false

    # When $true, Start installs any Packages not already in the image (a fast `pacman -T`
    # check; no-op when present). Useful with BaseImage to top up a prebuilt image without
    # rebuilding. Installs into the writable layer (re-applied on recreate), not persistent.
    SupplementPackages = $false
    # MountPath is derived in Get-ArchConfig as /home/<DevUser> (the persisted home).

    # Arch Linux ARM (ALARM) aarch64 root filesystem, over a trusted HTTPS mirror (valid
    # Let's Encrypt cert) for transport security. The canonical origin
    # (http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz) is plain HTTP with an
    # invalid cert; override RootfsUrl in container.local.psd1 if this mirror is unavailable.
    RootfsUrl     = 'https://fl.us.mirror.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz'

    # Packages installed into the image (general dev sandbox).
    Packages      = @('base-devel', 'git', 'vim', 'sudo', 'openssh', 'which')

    # Non-root user created inside the container.
    DevUser       = 'dev'
}

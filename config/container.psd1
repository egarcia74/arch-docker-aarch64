@{
    # Single source of truth for all lifecycle scripts and the Docker build.
    ImageName     = 'arch-aarch64:latest'

    # BaseImage: empty = build locally FROM scratch (default). Set to a prebuilt image that
    # is equivalent to this project's build — e.g. 'ghcr.io/egarcia74/arch-docker-aarch64:latest'
    # — to pull and use it directly, skipping the ~784 MB rootfs download + build. Must be a
    # fully-built compatible image (dev user + entrypoint), NOT a bare Arch rootfs.
    BaseImage     = ''

    ContainerName = 'arch-aarch64'
    Hostname      = 'arch-aarch64'
    VolumeName    = 'arch-aarch64-home'
    Platform      = 'linux/arm64'
    SshHostPort   = 2222
    StartSshOnBoot = $false
    # MountPath is derived in Get-ArchConfig as /home/<DevUser> (the persisted home).

    # Official Arch Linux ARM (ALARM) aarch64 root filesystem.
    RootfsUrl     = 'http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz'

    # Packages installed into the image (general dev sandbox).
    Packages      = @('base-devel', 'git', 'vim', 'sudo', 'openssh', 'which')

    # Non-root user created inside the container.
    DevUser       = 'dev'
}

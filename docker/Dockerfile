# syntax=docker/dockerfile:1
#
# Native aarch64 Arch Linux ARM (ALARM) image.
# Built FROM scratch by extracting the official ALARM rootfs tarball, which the
# Build-ArchImage.ps1 script downloads into this directory (the build context).
#
# Docker automatically extracts a *local* tar.gz referenced by ADD, so the
# tarball becomes the entire root filesystem.

FROM scratch
ADD ArchLinuxARM-aarch64-latest.tar.gz /

# Packages and the non-root user name come from config/container.psd1 via the
# build script, so this Dockerfile stays in sync with one source of truth.
ARG PACKAGES="base-devel git vim sudo openssh which"
ARG DEV_USER="dev"

# ALARM ships its own keyring; it must be initialised before any pacman transaction.
# pacman 7.0+ sandboxes downloads with Landlock + an 'alpm' user, which the Docker
# Desktop VM's seccomp profile blocks ("Landlock ruleset could not be applied").
# Persist DisableSandbox in pacman.conf so both this build AND runtime `sudo pacman`
# work. Then full system upgrade, install the dev packages, and clear the cache.
RUN pacman-key --init && pacman-key --populate archlinuxarm && \
    sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf && \
    pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed ${PACKAGES} && \
    pacman -Scc --noconfirm && \
    useradd -m -G wheel -s /bin/bash "${DEV_USER}" && \
    printf '%%wheel ALL=(ALL:ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/10-wheel && \
    chmod 0440 /etc/sudoers.d/10-wheel

# Expose the dev home to the entrypoint so it isn't hardcoded (DevUser stays one knob).
ENV ARCH_DEV_HOME=/home/${DEV_USER}

# Entrypoint optionally starts sshd on boot (ARCH_START_SSHD=1 + a key present; see
# StartSshOnBoot / Enable-ArchSsh.ps1), then idles so the container survives stop/start.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /home/${DEV_USER}
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

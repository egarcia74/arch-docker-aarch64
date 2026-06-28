# syntax=docker/dockerfile:1
#
# Native aarch64 Arch Linux ARM (ALARM) image, built in two stages:
#
#   builder  - FROM scratch, ADD + extract the ALARM rootfs, then provision it (pacman
#              upgrade/install, dev user, entrypoint).
#   final    - FROM scratch, COPY the provisioned tree from `builder` as ONE layer.
#
# The squash matters: a single-stage `ADD` + `RUN pacman -Syu` carries BOTH the original
# rootfs files and their upgraded replacements (layers are additive), roughly doubling the
# image. COPYing the final filesystem state collapses that to one layer.
# Build-ArchImage.ps1 downloads the tarball into this directory (the build context).

# --- Builder: extract + provision the rootfs ---------------------------------------------
FROM scratch AS builder
ADD ArchLinuxARM-aarch64-latest.tar.gz /

# Packages and the non-root user name come from config/container.psd1 via the build script,
# so this Dockerfile stays in sync with one source of truth.
ARG PACKAGES="base-devel git vim sudo openssh which"
ARG DEV_USER="dev"

# ALARM ships its own keyring; it must be initialised before any pacman transaction.
# pacman 7.0+ sandboxes downloads with Landlock + an 'alpm' user, which the Docker Desktop
# VM's seccomp profile blocks ("Landlock ruleset could not be applied"). Persist
# DisableSandbox in pacman.conf so both this build AND runtime `sudo pacman` work. Then full
# system upgrade, install the dev packages, and strip caches so the copied tree stays small.
RUN pacman-key --init && pacman-key --populate archlinuxarm && \
    sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf && \
    pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed ${PACKAGES} && \
    rm -rf /var/lib/pacman/sync/* /var/cache/pacman/pkg/* /tmp/* /var/tmp/* && \
    useradd -m -G wheel -s /bin/bash "${DEV_USER}" && \
    printf '%%wheel ALL=(ALL:ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/10-wheel && \
    chmod 0440 /etc/sudoers.d/10-wheel

# Entrypoint optionally starts sshd on boot (ARCH_START_SSHD=1 + a key present; see
# StartSshOnBoot / Enable-ArchSsh.ps1), then idles so the container survives stop/start.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# --- Final: squash the provisioned tree into a single layer ------------------------------
FROM scratch
ARG DEV_USER="dev"
COPY --from=builder / /

# Links the published GHCR package back to the repo (and shows up in image metadata).
LABEL org.opencontainers.image.source="https://github.com/egarcia74/arch-docker-aarch64" \
      org.opencontainers.image.description="Native aarch64 Arch Linux ARM dev container"

# Expose the dev home to the entrypoint so it isn't hardcoded (DevUser stays one knob).
ENV ARCH_DEV_HOME=/home/${DEV_USER}
WORKDIR /home/${DEV_USER}
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

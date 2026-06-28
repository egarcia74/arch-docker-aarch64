# Arch Linux aarch64 Docker container + PowerShell lifecycle scripts

**Date:** 2026-06-28
**Target:** Apple Silicon (`arm64`), Docker Desktop, PowerShell 7

## Goal

Provide a native **aarch64/arm64** Arch Linux container plus PowerShell 7 scripts to
**build, start, stop, restart, remove** (and shell into) it.

## Research findings

- The official `library/archlinux` Docker image is **x86_64-only** — the Arch Wiki
  ([Install Arch Linux via Docker](https://wiki.archlinux.org/title/Install_Arch_Linux_via_Docker))
  states it targets x86_64 machines and publishes no arm64 manifest. On Apple Silicon it would
  only run under QEMU emulation (`--platform linux/amd64`), which is slow.
- Native aarch64 Arch is provided by **Arch Linux ARM (ALARM)** — a separate port with its
  own `aarch64` rootfs tarball and pacman repositories
  (`http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz`).
- ALARM uses its own keyring (`archlinuxarm-keyring`); pacman needs
  `pacman-key --init && pacman-key --populate archlinuxarm` before any transaction.
- Lifecycle scripts imply a **long-lived named container** that idles (`sleep infinity`)
  so it survives stop/restart while keeping state.

## Decisions (confirmed with user)

| Decision    | Choice                                                                                                   |
| ----------- | -------------------------------------------------------------------------------------------------------- |
| Base image  | Build native aarch64 `FROM scratch` + `ADD` the ALARM rootfs tarball                                     |
| Purpose     | General dev sandbox: `base-devel git vim sudo openssh which` + non-root `dev` user                       |
| Persistence | Long-lived named container + named volume `arch-aarch64-home` mounted at the dev user's home `/home/dev` |

## Layout

```text
arch-docker-aarch64/
├── docker/
│   ├── Dockerfile                  # FROM scratch + ADD ALARM rootfs; entrypoint
│   └── entrypoint.sh               # optional sshd-on-boot, then sleep infinity
├── scripts/
│   ├── _Common.ps1                 # shared config loader + helpers (dot-sourced)
│   ├── Build-ArchImage.ps1         # download rootfs, verify, docker build
│   ├── Start-ArchContainer.ps1     # ensure-running (build if missing) or start
│   ├── Stop-ArchContainer.ps1
│   ├── Restart-ArchContainer.ps1
│   ├── Remove-ArchContainer.ps1    # -RemoveVolume / -RemoveImage / -Force
│   ├── Enter-ArchContainer.ps1     # docker exec as dev user (ensure-running)
│   ├── Get-ArchStatus.ps1          # container + volume state (config-driven)
│   ├── Invoke-Tests.ps1            # run Pester suite
│   ├── Invoke-Lint.ps1             # run PSScriptAnalyzer
│   ├── Format-Markdown.ps1         # prettier + markdownlint-cli2 (-Check)
│   ├── Invoke-PreCommit.ps1        # gate: PSScriptAnalyzer + Pester + Markdown
│   ├── Enable-ArchSsh.ps1          # publish port, install key, start sshd
│   └── Invoke-ArchSample.ps1       # run a samples/ init script in the container
├── samples/                        # idempotent bash setup-*.sh (ssh, dotnet, rust, go, build-tools)
├── tests/                          # Pester 5 (Config, Common, Static analysis)
├── config/
│   ├── container.psd1              # single source of truth (names, packages, dev user, ssh)
│   ├── container.local.psd1.example  # template for gitignored local overrides
│   └── PSScriptAnalyzerSettings.psd1
├── package.json                    # npm wrappers for quality commands (test/lint/format)
├── .github/workflows/build-image.yml  # CI: gate + native arm64 build → GHCR
├── .markdownlint-cli2.jsonc / .prettierrc.json / .prettierignore
└── docs/design.md
```

## Components

### Dockerfile

- `FROM scratch` then `ADD ArchLinuxARM-aarch64-latest.tar.gz /` (Docker auto-extracts
  local tarballs).
- `pacman-key --init && pacman-key --populate archlinuxarm`.
- `pacman -Syu` + install packages (passed via `--build-arg PACKAGES`), then `pacman -Scc`.
- Create non-root `dev` user (build-arg `DEV_USER`) in `wheel` with passwordless sudo;
  its home `/home/dev` is the persisted, mounted-over directory.
- `ENV ARCH_DEV_HOME=/home/${DEV_USER}` + `COPY entrypoint.sh`; `ENTRYPOINT` runs
  `entrypoint.sh`, which optionally starts `sshd` on boot (when `ARCH_START_SSHD=1` and a key
  exists) then `exec sleep infinity`.

### config/container.psd1 (+ local overrides)

Single source of truth: image/container/volume names, hostname, platform, rootfs URL,
package list, dev user, `SshHostPort`, `StartSshOnBoot` (mount path is derived from dev user).
Both the build script (build-args) and the runtime scripts read from here. The container is
created with `--hostname` (stable `dev@<Hostname>` prompt) and `--publish 127.0.0.1:<port>:22`.
`Get-ArchConfig` merges an optional gitignored `container.local.psd1` over the base (local
keys win) so settings can be experimented with without committing changes.

### \_Common.ps1 (shared)

`Get-ArchConfig` (loads psd1; derives `MountPath` as `/home/<DevUser>`), `Invoke-Docker`
(run a mutating docker command, suppress its echo, throw on non-zero exit),
`Test-DockerRunning`, `Test-ContainerExists`, `Test-ContainerRunning`, `Test-ImageExists`,
`Test-VolumeExists`, and `Write-Step/Info/Ok` console helpers. Every script dot-sources this
and sets `$ErrorActionPreference = 'Stop'`.

### Lifecycle scripts

- **Build** — download tarball into the build context (cached; `-ForceDownload` to refresh),
  verify MD5 (`-SkipChecksum` to skip), `docker build --platform linux/arm64` with
  `--build-arg` for packages and dev user. `-NoCache` supported.
- **Start** — _ensure running_: running → no-op; exists+stopped → `docker start`; missing →
  `docker run -d` with the named volume. If the image is absent it builds it once (calls
  Build), so Start needs no manual pre-build.
- **Stop / Restart** — existence-checked wrappers over `docker stop` / `docker restart`.
- **Remove** — `docker rm -f`; `-RemoveVolume` (prompts unless `-Force`), `-RemoveImage`.
- **Enter** — _ensure running_ (calls Start if the container is down), then
  `docker exec -u dev -w /home/dev …`; interactive `bash -l` (auto-degrades `-it`→`-i`
  when stdin is redirected) or `bash -lc <cmd>` for a one-shot `-Command`.

### Conditional sequencing: scripts, not task dependsOn

"Build only if missing" / "start only if down" are **conditional** and belong in the
idempotent scripts — VS Code task `dependsOn` is unconditional (re-runs expensive/prompting
steps every time) and only helps task users, not terminal/CI. So Start ensures the image and
Enter ensures the container; VS Code tasks stay 1:1 with scripts with no `dependsOn` chains.

## Persistence / data flow

Named volume `arch-aarch64-home` → `/home/dev` (the dev user's home). Docker seeds the
empty volume from the image's `/home/dev` on first run (so `/etc/skel` dotfiles are present).
The dev user's data — dotfiles, shell history, projects, anything installed into the home —
survives stop/start/restart **and** a full container remove+recreate. Only
`Remove-ArchContainer.ps1 -RemoveVolume` deletes it.

**Scope of persistence:**

- **Home (`/home/dev`)** → persisted by the volume; survives `remove`.
- **System changes** (e.g. `sudo pacman -S …` into `/usr`) → live in the container's
  writable layer; survive stop/start/restart but are **lost on `remove`+recreate**. To make
  a package permanent, add it to `Packages` in `config/container.psd1` and rebuild.

## Disk / install limits

No per-container quota. The image, the container writable layer, and the volume all share
Docker Desktop's single virtual disk inside its Linux VM (default ~64 GiB, adjustable in
**Docker Desktop → Settings → Resources → Virtual disk limit**). That shared disk is the
practical ceiling for how much can be installed.

## Error handling

All scripts guard on Docker running and resource existence, use `$ErrorActionPreference =
'Stop'`, check `$LASTEXITCODE` after docker calls, and are idempotent.

## Testing (manual checklist)

1. `Build-ArchImage.ps1` completes; image `arch-aarch64:latest` exists.
2. `Start-ArchContainer.ps1` runs; `Enter-ArchContainer.ps1 -Command 'uname -m'` prints
   `aarch64`.
3. Write a file under `/home/dev`; Stop → Start → file persists.
4. `Remove-ArchContainer.ps1` removes the container; volume retained until `-RemoveVolume`.

## Out of scope (YAGNI)

systemd-in-container, GUI/X11, docker-compose, CI, multi-arch publishing.

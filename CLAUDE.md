# CLAUDE.md — arch-docker-aarch64

Repo-specific guidance for Claude Code. Inherits the global rules in `~/CLAUDE.md`.

## What this is

A native **aarch64/arm64 Arch Linux** dev container for Apple Silicon, plus
PowerShell 7 lifecycle scripts. Built from the **Arch Linux ARM (ALARM)** rootfs
(`FROM scratch` + `ADD` the tarball) — NOT the upstream `archlinux` image, which is
x86_64-only and would only emulate on Apple Silicon.

## Stack

- **Container:** Docker Desktop, image `arch-aarch64:latest`, platform `linux/arm64`
- **Base:** Arch Linux ARM aarch64 rootfs (`os.archlinuxarm.org`)
- **Scripting:** PowerShell 7 (`pwsh`, never `powershell`)

## Commands

```pwsh
./scripts/Build-ArchImage.ps1            # build (downloads rootfs); flags: -NoCache -ForceDownload -SkipChecksum
./scripts/Start-ArchContainer.ps1        # create-or-start
./scripts/Stop-ArchContainer.ps1
./scripts/Restart-ArchContainer.ps1
./scripts/Remove-ArchContainer.ps1       # flags: -RemoveVolume -RemoveImage -Force
./scripts/Enter-ArchContainer.ps1        # shell as dev; -Command for one-off
```

Syntax-check scripts before relying on them:

```pwsh
pwsh -NoProfile -Command 'Get-ChildItem ./scripts/*.ps1 | % { [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$null,[ref]([ref]$null).Value) }'
```

## VS Code workspace

`arch-docker-aarch64.code-workspace` defines emoji-labelled folders and wires the scripts
as tasks. Task **icons must be codicons** (`icon: { id, color }`, e.g. `play` /
`terminal.ansiGreen`) — never emojis; emojis are only for folder names. Flag-bearing tasks
invoke pwsh via `-Command "& './scripts/X.ps1' <flags>"` (not `-File`) so multi-switch
`pickString` inputs bind correctly.

## Quality tooling

Three runners in `scripts/`, each also a VS Code `Dev:` task and an npm script:

- **Tests:** `Invoke-Tests.ps1` / `npm test` — Pester 5 suite in `tests/` (Config, Common,
  Static-analysis). Native `docker` is mocked via a `function global:docker` shadow.
- **Lint:** `Invoke-Lint.ps1` / `npm run lint:ps` — PSScriptAnalyzer over `scripts/` only
  (not `tests/`, which use `$global:` shadows + Pester DSL the analyzer would flag).
- **Markdown:** `Format-Markdown.ps1` (`-Check` for read-only) / `npm run format` +
  `npm run lint:md` — prettier + markdownlint-cli2 via npx (configs at repo root).
- **Gate:** `Invoke-PreCommit.ps1` / `npm run precommit` (and `npm run check`, an alias) —
  aggregates PSScriptAnalyzer + Pester + Markdown check. Runs each in its own pwsh child
  process (so one failure doesn't abort the rest, and Pester's `Run.Exit` can't kill the
  aggregator), collects results in a `List`, exits non-zero on any failure. Designed to wire
  as a git `pre-commit` hook once the repo is initialised.

npm wraps only quality commands, never the Docker lifecycle (that stays pwsh scripts + tasks).
Pester gotchas: `-ForEach` data is built at discovery (not `BeforeAll`); avoid `<...>` in test
names (Pester treats it as a data template).

## Conventions

- **`config/container.psd1` is the single source of truth.** Names, platform, rootfs URL,
  package list, dev user, SSH port, and `StartSshOnBoot` live there. Do not hardcode these
  elsewhere; the Dockerfile receives `PACKAGES`/`DEV_USER` as build-args from the build script.
- **Local overrides:** `Get-ArchConfig` merges an optional gitignored
  `config/container.local.psd1` over the base (local keys win), so settings can be changed
  without touching/committing the base. `MountPath` is derived after the merge.
- **`BaseImage`** (default `''`): when set, `Build-ArchImage.ps1` pulls + tags that image as
  `ImageName` and returns early (no FROM-scratch build). Must be a fully-built compatible
  image (dev user + entrypoint), e.g. the GHCR image — not a bare Arch rootfs. The rest of the
  lifecycle is unchanged since it references `ImageName`. **Caveat:** build-time config
  (`Packages`, `DevUser`, passed as build-args) is ignored when `BaseImage` is set — it's
  baked into the prebuilt image; only runtime config (`Hostname`/ports/`StartSshOnBoot`/volume,
  applied by `Start`) still takes effect.
- **`StartSshOnBoot`** (default `$false`): when true, `Start` passes `--env ARCH_START_SSHD=1`
  and the image entrypoint (`docker/entrypoint.sh`, derives home from `ENV ARCH_DEV_HOME`)
  starts `sshd` on boot if a key is present, then `exec sleep infinity`. Creation-time
  settings (`SshHostPort`, `StartSshOnBoot`, packages) need a container recreate / image
  rebuild to apply.
- All scripts dot-source `scripts/_Common.ps1`, set `$ErrorActionPreference = 'Stop'`,
  use `Set-StrictMode -Version Latest`, check `$LASTEXITCODE` after `docker`, and are
  idempotent. Follow that pattern for any new script.
- File org (per global rules): `docker/`, `scripts/`, `config/`, `docs/`. Nothing in root
  except `README.md`, `CLAUDE.md`, `.gitignore`, `*.code-workspace`.
- Scripts are **PSScriptAnalyzer-clean** against `config/PSScriptAnalyzerSettings.psd1`
  (`Invoke-ScriptAnalyzer -Path ./scripts -Recurse -Settings ./config/PSScriptAnalyzerSettings.psd1`).
  That file documents the three intentional rule exclusions (Write-Host for CLI colour,
  `Test-*Exists` naming, and MD5 broken-hash — used only to match ALARM's published
  checksum). Excluded via the settings file rather than inline because PowerShell Editor
  Services does not reliably honour script-scoped `SuppressMessageAttribute` for live
  diagnostics. Keep new scripts clean.

## Ensure semantics (why scripts, not task dependsOn)

Conditional sequencing lives in the **scripts**, not VS Code task `dependsOn` (which is
unconditional and would re-run expensive/prompting steps every time, and only helps task
users — not terminal/CI).

- `Start` ensures the image: if `arch-aarch64:latest` is missing it calls `Build-ArchImage.ps1`
  once (announced), then create-or-starts. Build runs **only when actually missing**.
- `Enter` (Shell) ensures the container: if not running it calls `Start-ArchContainer.ps1`
  (which ensures the image). So `Enter-ArchContainer.ps1` alone bootstraps from a bare clone.
- `Stop` / `Restart` / `Remove` stay explicit and independent — no hidden side effects.
- Scripts call each other via `& (Join-Path $PSScriptRoot 'Other.ps1')`. Keep VS Code tasks
  1:1 with scripts; do not add `dependsOn` chains.

## Persistence model (important)

- Named volume `arch-aarch64-home` mounts at `/home/dev` → the dev user's home survives
  stop/start AND a full `remove` + recreate. Only `-RemoveVolume` deletes it.
- System changes (`pacman -S` into `/usr`) live in the writable layer and are lost on
  `remove`. To make a package permanent, add it to `Packages` in the config and rebuild.

## Gotchas

- ALARM needs `pacman-key --init && pacman-key --populate archlinuxarm` before any pacman
  transaction (already in the Dockerfile).
- `ADD` only auto-extracts a **local** tarball, so the build script downloads the rootfs
  into `docker/` first (gitignored).
- Always build/run with `--platform linux/arm64` to stay native on Apple Silicon.

## Use cases, samples & SSH

- `samples/setup-*.sh` are idempotent bash init scripts run **inside** the container by
  `Invoke-ArchSample.ps1 -Name <x>` (streamed via `docker exec -i … bash -s`). Add a use case
  by dropping a `setup-<name>.sh`. Bash, not pwsh — not covered by the PSScriptAnalyzer/Pester
  gate.
- SSH: the container publishes `127.0.0.1:<SshHostPort>:22` (config, default 2222, set at
  `docker run`). `Enable-ArchSsh.ps1` recreates the container once if it predates the port
  (home volume preserved), installs `~/.ssh/*.pub` into the dev user's `authorized_keys`
  (persists in the volume — passed as a positional arg to `bash -s`, never interpolated), and
  starts `sshd`. No systemd, so `sshd` does not survive a container stop — re-run the script
  (it is idempotent). See `docs/use-cases.md`.
- **Host-key persistence:** both SSH start paths (`entrypoint.sh` for boot, `setup-ssh.sh` for
  manual) persist `/etc/ssh/ssh_host_*` into the home volume (`~/.ssh-hostkeys`) and restore
  them on start, so the server identity (and the client's `known_hosts`) survives a container
  remove+recreate. Only `-RemoveVolume` resets it; `Remove-ArchContainer.ps1` then prints the
  `ssh-keygen -R` reminder. The keys live in the volume; `/etc/ssh` is just the working copy.

## Out of scope (don't add unless asked)

systemd-in-container, GUI/X11, docker-compose, CI, multi-arch publishing.

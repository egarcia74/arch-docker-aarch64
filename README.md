# arch-docker-aarch64

[![build-image](https://github.com/egarcia74/arch-docker-aarch64/actions/workflows/build-image.yml/badge.svg)](https://github.com/egarcia74/arch-docker-aarch64/actions/workflows/build-image.yml)

A native **aarch64/arm64 Arch Linux** development container for Apple Silicon
with PowerShell 7 scripts to build, start, stop, restart, remove,
and shell into it.

It builds from the official **Arch Linux ARM (ALARM)** rootfs — not the upstream
`archlinux` image, which is x86_64-only and would run only under slow QEMU emulation
on Apple Silicon.

## Requirements

- macOS on Apple Silicon (`arm64`)
- Docker Desktop (running)
- PowerShell 7+ (`pwsh`)

## Quick start

The scripts are self-healing ("ensure" semantics), so from a fresh clone a single
command bootstraps everything — it builds the image if missing, then starts the
container, then opens the shell:

```pwsh
# Bootstrap + shell in one step (builds image + starts container on first run)
./scripts/Enter-ArchContainer.ps1

# ...or run a one-off command (same auto-bootstrap)
./scripts/Enter-ArchContainer.ps1 -Command 'uname -m'   # -> aarch64
```

You can still drive each step explicitly:

```pwsh
./scripts/Build-ArchImage.ps1        # build the image (downloads ALARM rootfs, pacman -Syu)
./scripts/Start-ArchContainer.ps1    # create-or-start (builds image first if missing)
./scripts/Stop-ArchContainer.ps1
```

## Use cases, samples & SSH

See **[docs/use-cases.md](docs/use-cases.md)** for what this is good for (native
`linux-arm64` .NET build/test, disposable Linux shells, native Rust/Go/C builds, AUR
testing, remote dev host) and how to get started with each.

Layer on a use case with an idempotent sample, or SSH in:

```pwsh
./scripts/Invoke-ArchSample.ps1                # list samples (dotnet/rust/go/build-tools/ssh)
./scripts/Invoke-ArchSample.ps1 -Name dotnet   # run one

./scripts/Enable-ArchSsh.ps1                   # install key + start sshd
# then: ssh dev@127.0.0.1 -p 2222   (or VS Code Remote-SSH -> dev@127.0.0.1:2222)
```

## VS Code workspace

Open `arch-docker-aarch64.code-workspace` for logical folders (🏠 Root, 🐳 Docker,
📜 Scripts, ⚙️ Config, 📚 Docs) and the scripts wired up as tasks. Run them with
**Terminal → Run Task…** (or `⇧⌘B` for the default _Arch: Build Image_):

| Task                                 | Action                                                        |
| ------------------------------------ | ------------------------------------------------------------- |
| `Arch: Build Image`                  | Build the image (prompts for cache / re-download options)     |
| `Arch: Start` / `Stop` / `Restart`   | Lifecycle                                                     |
| `Arch: Remove`                       | Remove container (prompts: container / +image / +data volume) |
| `Arch: Shell`                        | Interactive shell as `dev`                                    |
| `Arch: Status`                       | Show container + volume state                                 |
| `Arch: Enable SSH`                   | Install key + start sshd; print the ssh command               |
| `Arch: Run Sample`                   | Run a use-case sample (dotnet / rust / go / build-tools / ssh)|
| `Docs: README` / `Docs: Design Spec` | Open docs                                                     |
| `Dev: Test (Pester)`                 | Run the Pester test suite                                     |
| `Dev: Lint PowerShell`               | Run PSScriptAnalyzer over the scripts                         |
| `Dev: Format Markdown`               | prettier + markdownlint-cli2 (Format or Check)                |
| `Dev: Pre-Commit`                    | Full gate: PSScriptAnalyzer + Pester + Markdown check         |

## Scripts

| Script                      | Purpose                                                                         |
| --------------------------- | ------------------------------------------------------------------------------- |
| `Build-ArchImage.ps1`       | Download the rootfs (cached), verify MD5, build `arch-aarch64:latest`.          |
| `Start-ArchContainer.ps1`   | Ensure running: build the image if missing, then create-or-start the container. |
| `Stop-ArchContainer.ps1`    | Stop the running container.                                                     |
| `Restart-ArchContainer.ps1` | Restart the container.                                                          |
| `Remove-ArchContainer.ps1`  | Remove the container; optional `-RemoveVolume` / `-RemoveImage` / `-Force`.     |
| `Enter-ArchContainer.ps1`   | Ensure running, then shell in as `dev`, or run a single command via `-Command`. |
| `Get-ArchStatus.ps1`        | Show container + data-volume state (config-driven, exact-name match).           |
| `Enable-ArchSsh.ps1`        | Install your public key + start sshd; print the `ssh` command.                  |
| `Invoke-ArchSample.ps1`     | Run a use-case init script from `samples/` in the container (`-Name`, or list). |

Useful build flags: `-NoCache`, `-ForceDownload`, `-SkipChecksum`.

All scripts are idempotent and guard on Docker being reachable.

## Development & quality

Quality tooling has three runners (in `scripts/`), each also exposed as a VS Code task
and an npm script:

| Tool                    | Script                        | npm               |
| ----------------------- | ----------------------------- | ----------------- |
| Pester tests (`tests/`) | `Invoke-Tests.ps1`            | `npm test`        |
| PSScriptAnalyzer        | `Invoke-Lint.ps1`             | `npm run lint:ps` |
| prettier + markdownlint | `Format-Markdown.ps1[-Check]` | `npm run format`  |

```pwsh
# one-time, for the markdown tooling (prettier + markdownlint-cli2)
npm install

# full read-only gate: PSScriptAnalyzer + Pester + Markdown lint/format check
./scripts/Invoke-PreCommit.ps1      # or: npm run check  (alias of precommit)
```

`Invoke-PreCommit.ps1` runs every check (it does not fail fast, so you see all failures at
once) and exits non-zero if any fail. Once the repo is a git repo, wire it as a hook —
`.git/hooks/pre-commit` containing `pwsh -NoProfile -File ./scripts/Invoke-PreCommit.ps1`.

Requires `Pester` 5+ and `PSScriptAnalyzer` (`Install-Module Pester, PSScriptAnalyzer -Scope CurrentUser`)
and Node.js for the markdown tools. PSScriptAnalyzer is configured by
`config/PSScriptAnalyzerSettings.psd1`. The Docker lifecycle is intentionally **not** wrapped
in npm — those are the domain CLI (pwsh scripts + `Arch:` tasks), not generic dev commands.

## Continuous integration

`.github/workflows/build-image.yml` runs the same quality gate (PSScriptAnalyzer + Pester +
markdown) and then **builds the image natively on an `aarch64` GitHub runner** (no QEMU) and
publishes it to GHCR as `ghcr.io/egarcia74/arch-docker-aarch64:latest` (plus a dated tag and a
`sha-<short>` commit tag). It triggers weekly (rolling-release refresh), on changes to the
image inputs, and on demand. The build reuses `scripts/Build-ArchImage.ps1`, so CI exercises
the real build script, and a final **smoke** job pulls the published image and asserts core
invariants (aarch64, dev user, sudo, packages, SSH, entrypoint).

**Fast path — pull instead of build.** Set `BaseImage` to the published image (in
`container.local.psd1` to keep it uncommitted) and `Build` pulls + tags it instead of doing
the FROM-scratch build, skipping the ~784 MB rootfs download:

```pwsh
# config/container.local.psd1
@{ BaseImage = 'ghcr.io/egarcia74/arch-docker-aarch64:latest' }
```

`Start`/`Enter`/`Status` are unchanged — they keep using the local `ImageName` tag.

> **Caveat:** `BaseImage` pulls a prebuilt image, so **build-time** config (`Packages`,
> `DevUser`) is baked in at CI time. Only **runtime** config (`Hostname`, `SshHostPort`,
> `StartSshOnBoot`, volume) applies by default. To add packages **without rebuilding**, set
> `SupplementPackages = $true` — `Start` installs any missing `Packages` into the running
> container (a `pacman -T` check; into the writable layer, re-applied on recreate).
> `SupplementPackages` is a **convenience for topping up a base image, not long-lived package
> management** — for packages you always want, bake them into the image (leave `BaseImage`
> empty so it's built locally with your `Packages`).

## Persistence

| What                                                | Where                                    | Survives stop/start | Survives `remove` |
| --------------------------------------------------- | ---------------------------------------- | :-----------------: | :---------------: |
| Dev user's home (dotfiles, shell history, projects) | volume `arch-aarch64-home` → `/home/dev` |         ✅          |        ✅         |
| System changes (`sudo pacman -S …` into `/usr`)     | container writable layer                 |         ✅          |        ❌         |

- The named volume holds `/home/dev`, so the dev user's data survives a full
  remove + recreate. Only `Remove-ArchContainer.ps1 -RemoveVolume` deletes it.
- To make a **system package** permanent, add it to `Packages` in
  `config/container.psd1` and rebuild — otherwise reinstalling it after a `remove`
  is expected.

## Disk / install limits

There's no per-container quota. The image, the container's writable layer, and the
volume all share **Docker Desktop's single virtual disk** (default ~64 GiB,
adjustable in **Docker Desktop → Settings → Resources → Virtual disk limit**).
That shared disk is the practical ceiling for how much you can install.

## Configuration

`config/container.psd1` is the single source of truth — image/container/volume names,
hostname, platform, rootfs URL, package list, the dev user, `SshHostPort`, and
`StartSshOnBoot` (the mount path is derived as `/home/<DevUser>`). Both the build and the
runtime scripts read from it.

To experiment without committing, copy `config/container.local.psd1.example` to
`config/container.local.psd1` (gitignored) and set only the keys you want to override —
`Get-ArchConfig` merges it over the base, local keys winning.

## Layout

```text
docker/Dockerfile      # FROM scratch + ADD ALARM rootfs
scripts/*.ps1          # lifecycle scripts + _Common.ps1 helpers
config/container.psd1  # single source of truth
docs/                  # design document
```

See `docs/design.md` for the full design.

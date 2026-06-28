# Use cases & recipes

What this native aarch64 Arch container is good for, and how to get started with each.
The design — native ARM (no emulation), a persistent `/home/dev`, self-healing scripts, and
rolling-release Arch — makes it a low-friction, fast, throwaway Linux ARM environment.

## Getting started

Prerequisites: Docker Desktop running, PowerShell 7 (`pwsh`), and (for SSH) an SSH key pair
on your Mac and Node.js (for the docs tooling only).

```pwsh
# Bootstrap everything (builds image + starts container) and open a shell:
./scripts/Enter-ArchContainer.ps1
```

Then layer on a use case with a sample (installs are idempotent and land in the persistent
home or system layer):

```pwsh
./scripts/Invoke-ArchSample.ps1                 # list available samples
./scripts/Invoke-ArchSample.ps1 -Name dotnet    # run one
```

## Local config overrides (experiment without committing)

To change a setting without editing or committing `config/container.psd1`, create a
**gitignored** `config/container.local.psd1` with only the keys you want to override —
`Get-ArchConfig` merges it over the base (local wins). Copy the example to start:

```pwsh
cp config/container.local.psd1.example config/container.local.psd1
# edit it, e.g.  @{ StartSshOnBoot = $true; SshHostPort = 2250 }
```

Settings consumed at container creation (`SshHostPort`, `StartSshOnBoot`) need a recreate to
take effect: `./scripts/Remove-ArchContainer.ps1; ./scripts/Start-ArchContainer.ps1` (the home
volume is preserved).

## SSH access (and VS Code Remote-SSH)

The container publishes `127.0.0.1:2222 -> 22` (localhost only). `Enable-ArchSsh.ps1`
installs your public key into the dev user's `authorized_keys` (which persists in the home
volume), starts `sshd` (key-only, no passwords), and prints the connection command:

```pwsh
./scripts/Enable-ArchSsh.ps1                     # uses ~/.ssh/id_ed25519.pub or id_rsa.pub
./scripts/Enable-ArchSsh.ps1 -PublicKey ~/.ssh/work.pub
```

```bash
ssh dev@127.0.0.1 -p 2222
```

In VS Code: **Remote-SSH → Connect to Host → `dev@127.0.0.1:2222`** to use the container as a
full remote dev host (extensions, debugging, integrated terminal).

Notes:

- **Key persists, sshd does not (by default).** Your authorised key survives
  stop/remove/recreate (it's in the volume), but the container has no systemd, so `sshd` does
  not auto-start after a `stop`/`start` unless you opt in (below). Otherwise just re-run
  `./scripts/Enable-ArchSsh.ps1` (idempotent) to bring it back.
- **Zero-friction option:** set `StartSshOnBoot = $true` (in `container.local.psd1` to keep it
  uncommitted, or `container.psd1`) and recreate the container. The entrypoint then starts
  `sshd` on every boot — including after a `stop`/`start` — provided a key is present.
- The port is bound to `127.0.0.1`, so it is not exposed beyond your Mac.
- **Stable host identity.** The sshd host keys are persisted in the home volume
  (`~/.ssh-hostkeys`) and restored on each start, so `known_hosts` stays valid across a
  container remove+recreate. Only `Remove-ArchContainer.ps1 -RemoveVolume` resets the identity
  — and it prints the `ssh-keygen -R '[127.0.0.1]:<port>'` command to clear the stale entry.

## Sample init scripts

`samples/setup-*.sh` are idempotent bash scripts run inside the container by
`Invoke-ArchSample.ps1`. Add your own by dropping a `setup-<name>.sh` in `samples/`.

| Sample        | Installs                                      |
| ------------- | --------------------------------------------- |
| `ssh`         | `openssh` host keys + key-only sshd, started  |
| `dotnet`      | .NET SDK via official installer → `~/.dotnet` |
| `rust`        | `rustup` + stable toolchain                   |
| `go`          | `go` toolchain                                |
| `build-tools` | `cmake ninja meson pkgconf ccache`            |

## Use cases

### Native linux-arm64 .NET build/test

Run and test .NET on real ARM Linux (no QEMU), catching Linux-vs-macOS differences before a
container deploy or an ARM cloud runner (AWS Graviton, etc.).

```pwsh
./scripts/Invoke-ArchSample.ps1 -Name dotnet
./scripts/Enter-ArchContainer.ps1 -Command '~/.dotnet/dotnet --info | head -5'
```

> The ALARM repos have no aarch64 `dotnet-sdk`, so the sample uses Microsoft's official
> `dotnet-install.sh` (auto-detects arm64) into `~/.dotnet` — which persists in the home
> volume and is added to PATH for new shells. Override the channel with
> `ARCH_DOTNET_CHANNEL=9.0` etc.; LTS installs .NET 10.

### Disposable Linux shell / risky experiments

Try a CLI tool or a risky global install in isolation, then throw it away. `/home/dev`
survives a normal remove; only `Remove-ArchContainer.ps1 -RemoveVolume` wipes it.

```pwsh
./scripts/Enter-ArchContainer.ps1
# ...experiment...
./scripts/Remove-ArchContainer.ps1 -RemoveVolume -RemoveImage -Force   # full teardown
```

### Native aarch64 compile targets (Rust / Go / C/C++)

Build native code for ARM Linux at full speed.

```pwsh
./scripts/Invoke-ArchSample.ps1 -Name rust         # or: go, build-tools
./scripts/Enter-ArchContainer.ps1 -Command 'rustc --version'
```

### AUR / bleeding-edge package testing

Arch is rolling-release with the newest toolchains. Test "does my thing build against the
latest of everything?" — and a broken `pacman -Syu` experiment costs nothing.

```pwsh
./scripts/Enter-ArchContainer.ps1 -Command 'sudo pacman -Syu --noconfirm'
```

### Remote dev host

Use SSH (above) + VS Code Remote-SSH to treat the container as a persistent ARM Linux
workstation: clone repos into `/home/dev`, build, and they survive recreation.

## Persistence reminder

- **`/home/dev`** (projects, dotfiles, `~/.cargo`, `~/.rustup`, `authorized_keys`) → volume;
  survives `remove`.
- **System packages** (`pacman -S` into `/usr`) → writable layer; lost on `remove`. To make a
  package permanent, add it to `Packages` in `config/container.psd1` and rebuild.

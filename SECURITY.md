# Security

## Threat model

This is a **local development container** for Apple Silicon, run via Docker Desktop. It is not
an internet-facing service. The relevant concerns are supply-chain provenance, the (localhost)
SSH surface, and the CI/publish pipeline — not multi-tenant isolation or remote exposure.

## Posture

**Hardened:**

- **SSH** is bound to `127.0.0.1` only (never the LAN), **key-only** (no passwords, no root
  login), with persisted host keys so a real MITM trips a `known_hosts` warning.
- **Unprivileged container** — no `--privileged`, no added capabilities, default seccomp.
- **No secrets** in the repo; CI uses the ephemeral `GITHUB_TOKEN` with least-privilege scopes.
- **No injection surface** — config values reach `docker`/`pacman` as array/positional args
  (never interpolated shell); the workflow uses the `env:`-var pattern, no untrusted
  `github.event.*`.
- **Config validation** (`Confirm-ArchConfig`) rejects malformed config on load.

**Supply chain:**

- The ALARM **rootfs** is fetched over a **trusted HTTPS mirror** (valid Let's Encrypt cert)
  and checked against its MD5 — HTTPS authenticates transport; the MD5 catches corruption.
  Residual trust is the mirror operator (ALARM does not sign the rootfs tarball). Override
  `RootfsUrl` in `config/container.local.psd1` to use a different mirror.
- **Packages** are signature-verified by `pacman` against the ALARM keyring.
- The **published image** (GHCR) is **signed with cosign (keyless / Sigstore)** in CI, and
  **scanned with Trivy** (HIGH/CRITICAL, fixable) on every build.

**Known, accepted for this use case:**

- Inside the container, `dev` has passwordless `sudo` (= root) — expected for a dev sandbox.
- `DisableSandbox` in `pacman.conf` removes pacman's Landlock defense-in-depth (required under
  Docker Desktop; package signature verification still applies).
- GitHub Actions are tag-pinned (not SHA-pinned); npm dev tools are unpinned (`npx`). Both are
  dev/CI-only and low-impact; SHA-pinning + an npm lockfile are reasonable future hardening.

## Verifying the published image

The image is signed via keyless Sigstore. Verify provenance before trusting a pulled image:

```bash
cosign verify ghcr.io/egarcia74/arch-docker-aarch64:latest \
  --certificate-identity-regexp '^https://github.com/egarcia74/arch-docker-aarch64/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

A valid result confirms the image was built and signed by this repository's CI.

## Reporting

This is a personal project. Report suspected security issues by opening a
[GitHub issue](https://github.com/egarcia74/arch-docker-aarch64/issues) (or a private security
advisory for anything sensitive).

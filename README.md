# anq-server-deploy

NixOS flake for deploying and managing dedicated servers with a Nix-native installer, service modules, and SSH-based health checks.

- Declarative host + service configuration in one place.
- Bundled service modules for common game servers.
- Live health checks over SSH with port and log validation.

## Quick start

```bash
# Follow "Get started" first, then:
nix run .#install
nix run .#health
```

## Architecture

```
                    nix run .#install
                           |
options.nix --> configuration.nix --> services/<name>.nix --> systemd + firewall
                           |
                    nix run .#health (tests/<service>.nix)
```

## Get started

1) Copy `examples/options.example.nix` to `options.nix`.
2) Copy `examples/keys.example.nix` to `keys.nix`.
3) Edit `options.nix` (deploy, ssh, service, ports, backups).
4) If `deploy.mode = "install"`, set `installer.confirmInstall = true`.
5) Run `nix run .#install`.

## Daily operations

- Health check: `nix run .#health` (uses `tests/<service>.nix`).
- Non-destructive updates: set `deploy.mode = "switch"` in `options.nix`.
- Backups: set `backup.enable = true`, `backup.localDir`, and `backup.archiveKeep`.

## Included services

Bundled modules can be used as-is, removed, or extended:

- `enshrouded`
- `palworld`
- `vrising`

Service modules live in `services/`. Add a new module and a matching entry in `nixosConfigurations` to extend.

## Configuration (high-level)

- `options.nix` is the single source of truth.
- `deploy` and `ssh` contain host, user, mode, and SSH behavior.
- Per-service settings live under `services.<name>` (ports, config file, backup paths).
- `serviceDefaults` contains shared service toggles like `wineDebug`.
- `server-configs/` stores local config files; only examples are tracked.
- `options.nix` and `keys.nix` are local-only and ignored by git.

## Tests

- VM tests: `nix flake check -L -v`.
- Live health check: `nix run .#health`.
- Health check ports support `udp`, `tcp`, plus `udpOptional` and `tcpOptional` for non-fatal listeners.

## CI

- Local lint/format tools: `nix develop` (includes `alejandra`, `statix`, `deadnix`, `shellcheck`).
- Run local lint in one command: `nix run .#lint`.
- Run the same checks as CI:
  - `nix flake check -L`
  - `nix develop -c alejandra --check .`
  - `nix develop -c statix check .`
  - `nix develop -c deadnix .`
  - `nix develop -c shellcheck scripts/*.sh checks/*.sh`
- GitHub Actions workflows:
  - `Lint`: formatting + lints + shellcheck.
  - `CI`: full `nix flake check -L` (includes VM tests) plus lints.
- Run GitHub Actions locally with Act:
  - Lint only: `act -j lint -P ubuntu-latest=catthehacker/ubuntu:act-latest`
  - Full checks (requires KVM): `act -j checks --container-options "--device /dev/kvm" -P ubuntu-latest=catthehacker/ubuntu:act-latest`

## Troubleshooting

- SSH host keys change after reinstall:
  - `ssh-keygen -R <host-or-ip>`
  - Set `ssh.acceptNewHostKeys = true` in `options.nix` to auto-accept (less secure).
- Local configs (`options.nix`, `keys.nix`, and `server-configs/`) are intentionally ignored by git.
- `steamcmd` is unfree; `configuration.nix` enables unfree packages for the host build.

## Examples

- `examples/flake.example.nix`
- `examples/options.example.nix`
- `examples/keys.example.nix`
- `examples/health-check.example.nix`
- `server-configs/server-module.example.nix`

## Cleanup

- Remove unused local build artifacts:
  - `nix store gc`

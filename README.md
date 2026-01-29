# anq-server-deploy

NixOS flake for deploying and managing dedicated servers with a Nix-native installer, service modules, and SSH-based health checks.

- Declarative host + service configuration in one place.
- Bundled service modules for common game servers.
- Live health checks over SSH with port and log validation.

## Quick start

```bash
# Follow "Get started" first, then:
nix run .#install
nix run .#switch
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

1. Copy `examples/options.example.nix` to `options.nix`.
2. Copy `examples/keys.example.nix` to `keys.nix`.
3. Edit `options.nix` (deploy, ssh, service, ports, backups) and add your key to `keys.nix`.
4. When you are ready to run the destructive installer, set `installer.confirmInstall = true`.
5. Run `nix run .#install`.

- There is no `*.local.nix` wrapper workflow anymore; edit `options.nix` and `keys.nix` directly and keep them synced with this repo.

- Set `deploy.hostUser` to the non-root account you want created on the target . Use `deploy.installUser = "root"` while the installer runs so it can SSH in as root and still build that user.

## Daily operations

- Health check: `nix run .#health` (uses `tests/<service>.nix`).
- Non-destructive updates: after editing `options.nix`, run `nix run .#switch` to rebuild the live system.
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
- `deploy.hostUser` is the persistent SSH account created on the host; `deploy.installUser` (optional) is only used by the destructive installer and defaults to `deploy.hostUser`.
- Per-service settings live under `services.<name>` (ports, config file, backup paths).
- `serviceDefaults` contains shared service toggles like `wineDebug`.
- `server-configs/` stores config files consumed by the service modules; this repo ships with sample Palworld, Enshrouded, and V Rising configs so each service has a usable default.
- `options.nix` and `keys.nix` are local-only, and need to be made when setting up, see examples/ for templates.

## Tests

- Local smoke/test suite: `nix run .#test` (runs `nix flake check -L`, including the `service-check` that boots the service defined in `options.nix` and validates its directories and config file are created).
- VM tests: `nix flake check -L -v`.
- Live health check: `nix run .#health`.
- Health check ports support `udp`, `tcp`, plus `udpOptional` and `tcpOptional` for non-fatal listeners.

## CI

- Local lint/format tools: `nix develop` (includes `alejandra`, `statix`, `shellcheck`).
- Run local lint in one command: `nix run .#lint`.
- Run the same checks as CI:
  - `nix flake check -L`
  - `nix develop -c alejandra --check .`
  - `nix develop -c statix check .`
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
- `options.nix`, `keys.nix`, and the sample files inside `server-configs/` are tracked in this repo; edit them directly to customize or keep copies elsewhere if you need private overrides.
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
- Remove unused remote build artifacts:
  - `nix-collect-garbage -d`

## Contributer notes
- `CHANGELOG.md` captures what changed each session; update it before you wrap up a work cycle or tag a release.

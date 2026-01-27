# anq-server-deploy

NixOS flake for deploying and managing dedicated servers with a Nix-native installer, service modules, and SSH-based health checks.

This project is for people who want the whole host treated as code: OS state, users, firewall rules, services, and backups declared in one place, with reproducible deploys and rollbacks. Docker is often simpler for a single app; NixOS shines when you want host-level consistency and a single source of truth.

## What you get

- One config file (`options.nix`) to drive deploy behavior, SSH, services, ports, and backups.
- Remote installs via `nix run .#install` (powered by `nixos-anywhere`).
- Remote updates via `deploy.mode = "switch"` (runs `nixos-rebuild switch` on the host).
- Live health checks via `nix run .#health` (ports + optional log checks).
- Bundled service modules for common game servers.

## Get started

Prerequisites: Nix with flakes enabled on your local machine (NixOS not required).

1) Copy `examples/options.example.nix` to `options.local.nix`.
2) Copy `examples/keys.example.nix` to `keys.local.nix`.
   The tracked `options.nix`/`keys.nix` wrappers automatically import those `.local` files (or fall back to the examples when the overrides are missing).
3) Edit `options.local.nix` (deploy, ssh, service, ports, backups).
4) If `deploy.mode = "install"`, set `installer.confirmInstall = true`.
5) Run `nix run .#install` (uses [`nixos-anywhere`](https://github.com/nix-community/nixos-anywhere)).

Installations can be launched from macOS or Linux with Nix; the target host needs root access (for example via a rescue environment) so `nixos-anywhere` can provision the system.

## Quick start

```bash
# After "Get started":
nix run .#install
nix run .#health
```

## Modes: install vs switch

Use `deploy.mode = "install"` for a fresh machine install (destructive). For existing NixOS hosts, use `deploy.mode = "switch"` to apply updates without reinstalling. Both modes run through `nix run .#install`.

## Mental model

```
nix run .#install
   |
options.nix -> configuration.nix -> services/<name>.nix -> systemd + firewall
   |
nix run .#health -> tests/<name>.nix (ports + optional log checks)
```

## Repository layout

- `options.nix` — tracked entrypoint that imports `options.local.nix` (or the example when the override is missing).
- `options.local.nix` — ignored user config (copy from `examples/options.example.nix`).
- `keys.nix` — tracked entrypoint that imports `keys.local.nix` (or the example when the override is missing).
- `keys.local.nix` — ignored SSH key list (copy from `examples/keys.example.nix`).
- `configuration.nix` — shared NixOS host base.
- `installer.nix` / `disko.nix` — remote installer + disk layout.
- `services/<service>.nix` — service modules.
- `tests/<service>.nix` — health checks used by `nix run .#health`.
- `server-configs/` — local config files (examples tracked).
- `examples/` — templates you copy into place.

## Included services

Current modules: `enshrouded`, `palworld`, `vrising`. Service modules live in `services/`; add a new module and a matching entry in `nixosConfigurations` to extend.

## Configuration overview

`options.nix` is the single source of truth:

- `deploy` / `ssh`: host, user, mode, and SSH behavior.
- `services.<name>`: per-service settings (ports, config paths, backup paths).
- `serviceDefaults`: shared toggles like `wineDebug`.
- `backup`: toggle + local destination + retention.
- `backup.allowInsideRepoWithoutGit`: whether to permit in-repo backups when `.git` is missing (defaults to `false`).

Local config files go under `server-configs/`. Only examples are tracked, and the overrides (`options.local.nix`, `keys.local.nix`) stay ignored while the lightweight wrappers (`options.nix`, `keys.nix`) remain in the repo.

## Adding a new service

A service is complete when it has:

1) `services/<name>.nix` with the systemd unit and firewall rules.
2) `tests/<name>.nix` with port checks (and optional log checks).
3) A flake entry under `nixosConfigurations` so it can be deployed.

## Tests

Run VM tests with `nix flake check -L` and live health checks with `nix run .#health`. Health check ports support `udp`, `tcp`, plus `udpOptional` and `tcpOptional` for non-fatal listeners.

## Dev / CI parity

Tooling is provided via `nix develop` (includes `alejandra`, `statix`, `deadnix`, `shellcheck`). Run everything locally with:

```bash
nix run .#lint
```

Or individually:

```bash
nix flake check -L
nix develop -c alejandra --check .
nix develop -c statix check .
nix develop -c deadnix .
nix develop -c shellcheck scripts/*.sh checks/*.sh
```

If you use `act`, you can run workflows locally (KVM required for VM tests):

```bash
act -j lint -P ubuntu-latest=catthehacker/ubuntu:act-latest
act -j checks --container-options "--device /dev/kvm" -P ubuntu-latest=catthehacker/ubuntu:act-latest
```

## Troubleshooting

- SSH host keys change after reinstall:
  - `ssh-keygen -R <host-or-ip>`
  - Set `ssh.acceptNewHostKeys = true` in `options.nix` to auto-accept (less secure).
- Local configs (`options.local.nix`, `keys.local.nix`, and `server-configs/`) are intentionally ignored by git while `options.nix`/`keys.nix` remain tracked wrappers.
- If `backup.localDir` lives inside the repo but `.git` is missing, set `backup.allowInsideRepoWithoutGit = true` to allow backups inside the repo; otherwise keep `.git` to satisfy the guard.
- `steamcmd` is unfree; `configuration.nix` enables unfree packages for the host build.

## Examples

Example references: `examples/flake.example.nix`, `examples/options.example.nix`, `examples/keys.example.nix`, `examples/health-check.example.nix`, and `server-configs/server-module.example.nix`.

## Cleanup

Remove unused local build artifacts with `nix store gc`.

## License

MIT.

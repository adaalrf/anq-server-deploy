# Changelog

- Keep this document updated every working session or release so the history stays aligned with what ships.

## Unreleased

## 0.1.5 - 2026-01-29
- Documented the deployment flow in README guidance, created the changelog, and reiterated that this document should be refreshed each session.
- Split the destructive installer and non-destructive switcher into dedicated scripts/apps, registered them as flake apps, and widened README coverage so every command is clear.
- Added tracked sample configs under `server-configs/` and a `test` app plus `tests/service-check.nix` so `nix run .#test`/`nix flake check -L` now include the config-writer smoke test plus linters.
- Taught the smoke test to ensure `/srv/<service>/server` exists and that the service is active, keeping it fast while still covering the service wiring.

## 0.1.0 - Initial release
- Base Nix flake, options/configuration wiring, service modules, installer/switcher scripts, and health-check tooling for the Palworld/Enshrouded/V Rising servers.

# Developing ANQ Server Deploy

This is NixOS module and operations tooling, not a web application. Read
[README](README.md), [v1 scope](docs/V1.md), and [operations](docs/OPERATIONS.md).
You can evaluate and run fixture tests without enabling a game on your host.
Do not run `nixos-rebuild` just to explore this repository.

| Change | Source |
| --- | --- |
| NixOS options, users and systemd services | `modules/default.nix` |
| Fixed game definitions | `lib/` |
| On-host status/update/backup | `scripts/ops.sh` |
| Safe recovery extraction | `scripts/restore-check.py` |
| Runtime preparation and launch | `scripts/` |
| Host configuration and fictional settings | `examples/` |
| Module and lifecycle verification | `tests/`, `flake.nix` |

On an x86_64-linux Nix installation with flakes enabled:

```sh
nix develop
nix flake check --no-build
nix build .#checks.x86_64-linux.module-evaluation .#checks.x86_64-linux.operations .#checks.x86_64-linux.shell-package --no-link -L
nix build .#checks.x86_64-linux.lifecycle-vm --no-link -L
```

The development shell provides formatting, ShellCheck and Python. Use
`nix fmt -- flake.nix lib/*.nix modules/*.nix tests/*.nix examples/*.nix` for changes.
VM tests use fixture game, Steam and Wine executables; they verify lifecycle
mechanics, not game compatibility or player capacity. They do not alter the host's
running NixOS configuration or download real games. Actual game installs and
client/world acceptance require a separate disposable-host trial.

Keep credentials as runtime host strings outside the Nix store. Auto-start,
firewall changes and updates stay explicit. Failed snapshots prevent updates;
failed updates leave the game stopped. Restore checks extract into new directories
and never overwrite live state. Keep private settings and real saves out of Git.

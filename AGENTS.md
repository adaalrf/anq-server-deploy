# Working on Anq Server Deploy

Read README.md, docs/V1.md and docs/OPERATIONS.md. This is a clean NixOS module
and local operations remake; the archived repository has a dirty working tree
and must remain untouched. Never reset/stash it or copy its private settings.

Keep fixed named game services, runtime credentials outside the Nix store,
explicit updates and per-game operation locks. Backups must finish before an
update begins. Failed binary updates stay stopped. Restore checks only extract
into a new directory; never silently overwrite live state. Root-owned snapshots
contain sensitive settings and need explicit off-host protection in deployment.

Run formatter/ShellCheck, Nix module/operations checks and the fixture NixOS VM
for lifecycle changes. Fixture executables prove service mechanics, not real
Steam/Wine/game compatibility. Preserve that distinction in docs and portfolio
claims. No changes to the publishing VPS, workstation activation, GitHub or actual
domain are authorized by tests. Preserve Git signing settings.

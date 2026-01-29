{ pkgs }:
let
  script = pkgs.writeShellApplication {
    name = "switch";
    runtimeInputs = [
      pkgs.openssh
      pkgs.rsync
      pkgs.nix
      pkgs.coreutils
      pkgs.gnutar
      pkgs.gzip
    ];
    text = builtins.readFile ./scripts/switcher.sh;
  };
in
{
  type = "app";
  program = "${script}/bin/switch";
  meta = {
    description = "Sync the repo and run nixos-rebuild switch on the target host.";
  };
}

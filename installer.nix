{ pkgs }:
let
  script = pkgs.writeShellApplication {
    name = "install";
    runtimeInputs = [
      pkgs.openssh
      pkgs.rsync
      pkgs.nix
      pkgs.coreutils
      pkgs.gnutar
      pkgs.gzip
    ];
    text = builtins.readFile ./scripts/installer.sh;
  };
in
{
  type = "app";
  program = "${script}/bin/install";
  meta = {
    description =
      "Bootstraps the server via nixos-anywhere (destructive install)."
      + " Warning: this erases existing data on the target machine.";
  };
}

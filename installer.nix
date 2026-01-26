{pkgs}: let
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
in {
  type = "app";
  program = "${script}/bin/install";
  meta = {
    description = "Install or switch dedicated servers.";
  };
}

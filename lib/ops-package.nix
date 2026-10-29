{ pkgs }:
pkgs.writeShellApplication {
  name = "game-ops";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.gnutar
    pkgs.gzip
    pkgs.util-linux
    pkgs.jq
    pkgs.systemd
    pkgs.iproute2
    pkgs.python3
  ];
  text = ''
    export ANQ_CONFIG_ROOT=/etc/anq-games
    export ANQ_RESTORE_HELPER=${../scripts/restore-check.py}
    ${builtins.readFile ../scripts/ops.sh}
  '';
}

{
  description = "Anq game services — small NixOS deployment modules (v1)";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      ops = import ./lib/ops-package.nix { inherit pkgs; };
    in
    {
      nixosModules.default = import ./modules;
      packages.${system} = {
        default = ops;
        game-ops = ops;
      };
      formatter.${system} = pkgs.nixfmt;
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.nixfmt
          pkgs.shellcheck
          pkgs.python3
          pkgs.jq
        ];
      };
      checks.${system} = {
        module-evaluation = import ./tests/evaluation.nix {
          inherit pkgs nixpkgs;
          module = self.nixosModules.default;
        };
        operations =
          pkgs.runCommand "anq-game-operations-tests"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.python3
                pkgs.coreutils
                pkgs.jq
                pkgs.gnutar
                pkgs.gzip
                pkgs.util-linux
                pkgs.shellcheck
              ];
            }
            ''
              shellcheck -s bash ${./scripts}/*.sh
              export PROJECT_SRC=${self}
              export PYTHONDONTWRITEBYTECODE=1
              python3 -m unittest discover -s ${./tests} -p 'test_*.py' -v
              touch $out
            '';
        shell-package = ops;
        lifecycle-vm = import ./tests/vm.nix {
          inherit pkgs;
          module = self.nixosModules.default;
        };
      };
    };
}

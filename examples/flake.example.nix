{
  description = "Example NixOS flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    disko.url = "github:nix-community/disko";
  };

  outputs =
    {
      nixpkgs,
      disko,
    }:
    {
      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          ./disko.nix
          ./configuration.nix
        ];
      };
    };
}

# Import this alongside your EXISTING hardware/host configuration.
# Do not put secret content in this file or the Nix store.
{ ... }:
{
  imports = [ ../modules ];
  nixpkgs.config.allowUnfree = true;
  services.anqGames.palworld = {
    enable = true;
    settingsFile = "/var/lib/anq-game-secrets/palworld.ini";
    autoStart = false;
    openFirewall = false;
    udpPorts = [ 8211 ];
    cpuCores = 2;
    memoryMax = "8G";
    extraArgs = [ ];
  };
}

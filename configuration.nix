{
  lib,
  serviceName ? null,
  ...
}: let
  optionsPath =
    if builtins.pathExists ./options.nix
    then ./options.nix
    else ./examples/options.example.nix;
  keysPath =
    if builtins.pathExists ./keys.nix
    then ./keys.nix
    else ./examples/keys.example.nix;
  opts = import optionsPath;
  selectedService =
    if serviceName == null
    then opts.service
    else serviceName;
  serviceCfg = opts.services.${selectedService} or (throw "Unknown service '${selectedService}' in options.nix");
  deployUser = let
    user = opts.deploy.user or "";
  in
    if user != ""
    then user
    else throw "deploy.user must be set in options.nix";
in {
  networking = {
    hostName = "anq-server-deploy";
    useDHCP = true;
    firewall = {
      enable = true;
      allowedUDPPorts = serviceCfg.udpPorts or [];
      allowedTCPPorts = serviceCfg.tcpPorts or [];
    };
  };

  boot = {
    # Bootloader (UEFI + systemd-boot)
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;

    # Initrd: keep this minimal but robust for Hetzner/QEMU-style disks.
    # This solved early root discovery issues.
    initrd = {
      systemd.enable = true;
      supportedFilesystems = [
        "ext4"
        "vfat"
      ];
      availableKernelModules = [
        # Virtio stack (common on cloud/VM)
        "virtio_pci"
        "virtio_blk"
        "virtio_scsi"

        # Block device stack
        "sd_mod"

        # Controller fallbacks (safe to keep; small cost)
        "ahci"
        "ata_piix"

        # If the platform exposes disk as NVMe (harmless if not used)
        "nvme"
      ];
    };

    # Hetzner/QEMU: mitigate device enumeration timing in initrd.
    kernelParams = ["rootdelay=10"];
  };

  time.timeZone = "UTC";

  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  programs.nix-ld.enable = true;

  users = {
    # Declarative users (reproducible). No local passwords, SSH keys only.
    mutableUsers = false;

    users.${deployUser} = {
      isNormalUser = true;
      extraGroups = ["wheel"];

      # Lock local password login (SSH key login still works).
      # This enforces "SSH-only" in practice.
      hashedPassword = "!";

      openssh.authorizedKeys.keys = import keysPath;
    };

    users.root = {
      # Lock root password as well.
      hashedPassword = "!";
      # Do NOT allow root SSH keys.
      openssh.authorizedKeys.keys = [];
    };
  };

  # Passwordless sudo for wheel (SSH-key access + sudo escalation, no password).
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = {
      # Key-only SSH
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;

      # No root SSH
      PermitRootLogin = "no";

      # Only allow adaal over SSH
      AllowUsers = [deployUser];
    };
  };

  services = {
    ${serviceCfg.serviceName} =
      {
        enable = true;
        serverConfigFile = serviceCfg.configFile or null;
      }
      // (lib.optionalAttrs (serviceCfg.useWineDebug or false) {
        inherit (opts.serviceDefaults) wineDebug;
      });
  };

  system.stateVersion = "25.11";
}

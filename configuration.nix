{
  lib,
  serviceName ? null,
  ...
}:
let
  opts = import ./options.nix;
  selectedService = if serviceName == null then opts.service else serviceName;
  serviceCfg = opts.services.${selectedService} or (throw "Unknown service '${selectedService}' in options.nix");
  deployUser = opts.deploy.user or "";
  _ = lib.assertMsg (deployUser != "") "deploy.user must be set in options.nix" null;
in
{
  networking.hostName = "anq-server-deploy";
  networking.useDHCP = true;

  # Bootloader (UEFI + systemd-boot)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Initrd: keep this minimal but robust for Hetzner/QEMU-style disks.
  # This solved early root discovery issues.
  boot.initrd.systemd.enable = true;
  boot.initrd.supportedFilesystems = [
    "ext4"
    "vfat"
  ];
  boot.initrd.availableKernelModules = [
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

  # Hetzner/QEMU: mitigate device enumeration timing in initrd.
  boot.kernelParams = [ "rootdelay=10" ];

  time.timeZone = "UTC";

  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  programs.nix-ld.enable = true;

  # Declarative users (reproducible). No local passwords, SSH keys only.
  users.mutableUsers = false;

  users.users.${deployUser} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];

    # Lock local password login (SSH key login still works).
    # This enforces "SSH-only" in practice.
    hashedPassword = "!";

    openssh.authorizedKeys.keys = import ./keys.nix;
  };

  users.users.root = {
    # Lock root password as well.
    hashedPassword = "!";
    # Do NOT allow root SSH keys.
    openssh.authorizedKeys.keys = [ ];
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
      AllowUsers = [ deployUser ];
    };
  };

  networking.firewall = {
    enable = true;
    allowedUDPPorts = serviceCfg.udpPorts or [ ];
    allowedTCPPorts = serviceCfg.tcpPorts or [ ];
  };

  services = {
    ${serviceCfg.serviceName} = {
      enable = true;
      serverConfigFile = serviceCfg.configFile or null;
    }
    // (lib.optionalAttrs (serviceCfg.useWineDebug or false) {
      wineDebug = opts.serviceDefaults.wineDebug;
    });
  };

  system.stateVersion = "25.11";
}

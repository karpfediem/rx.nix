{ ... }: {
  networking.hostName = "demo";

  # Hardware stub config
  boot.loader.grub.devices = [ "/dev/boot-stub" ];
  fileSystems."/".device = "/dev/stub";
  system.stateVersion = "25.05";
}

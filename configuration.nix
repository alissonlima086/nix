{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix

    ./modules/packages
    ./modules/programs.nix
    ./modules/audio.nix
    ./modules/users.nix
    ./modules/network.nix
    ./modules/services.nix
    ./modules/desktop.nix
    ./modules/boot.nix
    ./modules/hyprland.nix
    ./modules/storage.nix
    ./modules/theme.nix
    ./modules/media.nix
  ];

  time.timeZone = "America/Araguaina";

  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "pt_BR.UTF-8";
    LC_IDENTIFICATION = "pt_BR.UTF-8";
    LC_MEASUREMENT = "pt_BR.UTF-8";
    LC_MONETARY = "pt_BR.UTF-8";
    LC_NAME = "pt_BR.UTF-8";
    LC_NUMERIC = "pt_BR.UTF-8";
    LC_PAPER = "pt_BR.UTF-8";
    LC_TELEPHONE = "pt_BR.UTF-8";
    LC_TIME = "pt_BR.UTF-8";
  };

  nixpkgs.config.allowUnfree = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = "26.05";
}

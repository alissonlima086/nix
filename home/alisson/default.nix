{ config, pkgs, ... }:

{
  imports = [
    ./git.nix
    ./theme.nix
    ./mimeapps.nix
    ./dotfiles.nix
    ./editor.nix
    ./services.nix
    ./organize.nix
    ./frame-backup.nix
  ];

  home.username = "alisson";
  home.homeDirectory = "/home/alisson";

  home.stateVersion = "26.05";

  services.frame-backup = {
    enable = true;
    backupDir = "/home/alisson/.system/frame-configs";
    commitDelay = "5m";
  };
}


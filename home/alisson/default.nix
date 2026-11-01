{ config, pkgs, ... }:

{
  imports = [
    ./git.nix
    ./theme.nix
    ./mimeapps.nix
    ./dotfiles.nix
    ./editor.nix
    ./services.nix
  ];

  home.username = "alisson";
  home.homeDirectory = "/home/alisson";

  home.stateVersion = "26.05";
}


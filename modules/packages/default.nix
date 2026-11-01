{ pkgs, ... }:

{
  imports = [
    ./kde.nix
    ./system.nix
    ./workspace-focus.nix
    ./apps.nix
  ];

  fonts.packages = with pkgs; [
    corefonts
    nerd-fonts.jetbrains-mono
  ];
}


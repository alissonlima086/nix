{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    tmux
    nano
    neovim
    tree-sitter
    htop
    lazydocker
    wget
    tree
    curl
    git
    gcc
    libnotify
  ];
}


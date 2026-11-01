{ pkgs, pkgs-unstable, inputs, ... }:

{
  environment.systemPackages = with pkgs; [
    kitty
    starship
    (mpv.override {
      scripts = [ mpvScripts.uosc ];
    })
    quickshell
    mangohud
    loupe
    tumbler
    onlyoffice-desktopeditors
    libreoffice-qt
    _7zz
    unrar
    picard
    obsidian
    discord
    qbittorrent
    python3
    thunar
    qrencode

    krita
    gimp

    playerctl
    sshfs
    glib

    godot_4-mono
    dotnet-sdk_8

    codex

    (pkgs.wrapOBS {
      plugins = with pkgs.obs-studio-plugins; [
        obs-vkcapture
        input-overlay
        obs-vaapi
      ];
    })

    pkgs-unstable.superfile

    inputs.noctalia.packages.${pkgs.system}.default
    inputs.subtui.packages.${pkgs.system}.default
    inputs.antigravity-nix.packages.${pkgs.system}.google-antigravity-cli
  ];
}


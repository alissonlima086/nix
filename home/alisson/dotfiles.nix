{ config, ... }:

{
  home.file = {
    ".config/hypr/hyprland.lua" = {
      source = ../../dotfiles/hypr/hyprland.lua;
      force = true;
    };

    ".config/hypr/scripts" = {
      source = ../../dotfiles/hypr/scripts;
      force = true;
    };

    ".config/kitty" = {
      source = ../../dotfiles/kitty;
      force = true;
    };

    ".config/nvim" = {
      source = ../../dotfiles/nvim;
      force = true;
    };

    ".config/noctalia/colors.json" = {
      source = config.lib.file.mkOutOfStoreSymlink ../../dotfiles/noctalia/colors.json;
    };

    ".config/noctalia/plugins.json" = {
      source = config.lib.file.mkOutOfStoreSymlink ../../dotfiles/noctalia/plugins.json;
    };

    ".config/noctalia/colorschemes" = {
      source = config.lib.file.mkOutOfStoreSymlink ../../dotfiles/noctalia/colorschemes;
    };

    ".config/noctalia/plugins" = {
      source = config.lib.file.mkOutOfStoreSymlink ../../dotfiles/noctalia/plugins;
    };

    ".config/subtui/config.toml" = {
      source = ../../dotfiles/subtui/config.toml;
      force = true;
    };

    ".config/kdeglobals" = {
      source = ../../dotfiles/kde/kdeglobals;
      force = true;
    };

    ".config/plasmarc" = {
      source = ../../dotfiles/kde/plasmarc;
      force = true;
    };

    ".local/share/kio/servicemenus/open-kitty-here.desktop" = {
      source = ../../dotfiles/kde/servicemenus/open-kitty-here.desktop;
      force = true;
    };

    ".zshrc" = {
      source = ../../dotfiles/zsh/.zshrc;
      force = true;
    };

    ".config/starship.toml" = {
      source = ../../dotfiles/starship/starship.toml;
      force = true;
    };

    ".config/superfile" = {
      source = ../../dotfiles/superfile;
      force = true;
    };

    ".config/mpv" = {
      source = ../../dotfiles/mpv;
      force = true;
    };

    ".config/Thunar/uca.xml" = {
      source = ../../dotfiles/thunar/uca.xml;
      force = true;
    };

    ".config/xfce4/helpers.rc".text = ''
      TerminalEmulator=kitty
    '';

    ".local/share/xfce4/helpers/kitty.desktop".text = ''
      [Desktop Entry]
      Version=1.0
      Encoding=UTF-8
      Type=X-XFCE-Helper
      X-XFCE-Category=TerminalEmulator
      Name=Kitty
      Icon=kitty
      X-XFCE-Commands=kitty;
      X-XFCE-CommandsWithParameter=kitty --directory="%s";
    '';
  };
}

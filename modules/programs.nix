{ pkgs, ... }:

{
  programs.firefox.enable = true;
  programs.vscode.enable = true;
  programs.zsh.enable = true;
  programs.nix-ld.enable = true;

  programs.steam = {
  enable = true;

    package = pkgs.steam.override {
      extraProfile = ''
      export MESA_VK_WSI_PRESENT_MODE=immediate
      export MANGOHUD_CONFIG=fps_limit=75,no_display
      export vk_xwayland_wait_ready=false
      export MANGOHUD=1
      '';
    };
  };

  programs.appimage = {
    enable = true;
    binfmt = true;

    package = pkgs.appimage-run.override {
      extraPkgs = pkgs: [
        pkgs.webkitgtk_4_1
      ];
    };
  };
}

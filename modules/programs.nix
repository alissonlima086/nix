{ pkgs, ... }:

{
  programs.firefox.enable = true;
  programs.vscode.enable = true;
  programs.steam.enable = true;
  programs.zsh.enable = true;
  programs.nix-ld.enable = true;

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

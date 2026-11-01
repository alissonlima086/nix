{ ... }:

{
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  home.file.".local/share/applications/nvim-kitty.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Neovim
    Exec=kitty --title neovim -e nvim %F
    Terminal=false
    Icon=nvim
    MimeType=text/plain;text/x-shellscript;text/x-python;text/x-csrc;text/x-chdr;text/x-c++src;text/x-c++hdr;application/json;text/markdown;text/x-log;application/x-yaml;text/x-nix;
    Categories=Utility;TextEditor;
  '';
}

{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    bibata-cursors

    kdePackages.breeze
    kdePackages.breeze-icons
    kdePackages.plasma-integration
  ];

  environment.sessionVariables = {
    XCURSOR_THEME = "Bibata-Modern-Classic";
    XCURSOR_SIZE = "24";
    HYPRCURSOR_THEME = "Bibata-Modern-Classic";
    HYPRCURSOR_SIZE = "24";
    QT_QPA_PLATFORMTHEME = "kde";
  };
}

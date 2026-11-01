{ pkgs, ... }:

{
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  xdg.portal = {
    enable = true;

    extraPortals = [
      pkgs.kdePackages.xdg-desktop-portal-kde
      pkgs.xdg-desktop-portal-gtk
    ];

    config.common = {
      default = [
        "hyprland"
	"kde"
	"gtk"
      ];

      "org.freedesktop.impl.portal.ScreenCast" = "hyprland";
      "org.freedesktop.impl.portal.Screenshot" = "hyprland";
      "org.freedesktop.impl.portal.FileChooser" = "kde";
      "org.freedesktop.impl.portal.Settings" = "gtk";
    };
  };

  services.greetd = {
    enable = true;

    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd start-hyprland";
        user = "greeter";
      };
    };
  };

  environment.systemPackages = with pkgs; [
    hyprshot
    wl-clipboard
    grim
    slurp
  ];
}

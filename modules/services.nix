{ ... }:

{
  services.udisks2.enable = true;
  services.gvfs.enable = true;

  programs.dconf.enable = true;

  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  programs.kdeconnect = {
    enable = true;
  };

  virtualisation.docker.enable = true;
}

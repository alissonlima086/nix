{ pkgs, ... }:

{
  networking.hostName = "nixos";

  networking.networkmanager.enable = true;

  services.openssh.enable = true;

  services.tailscale.enable = true;

  networking.firewall.checkReversePath = false;

  environment.systemPackages = with pkgs; [
    protonvpn-gui
    wireguard-tools
  ];
}

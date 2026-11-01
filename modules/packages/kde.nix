{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    kdePackages.kio-admin
    kdePackages.kio-extras
    kdePackages.ark
    kdePackages.kservice
  ];
}


{ pkgs, ... }:

{
  users.users.alisson = {
    isNormalUser = true;
    description = "Alisson Lima";
    shell = pkgs.zsh;

    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
    ];
  };
}

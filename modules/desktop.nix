{ ... }:

{
  services.xserver.xkb = {
    layout = "br";
    variant = "nodeadkeys";
  };

  console.keyMap = "br-abnt2";

  services.printing.enable = true;
}

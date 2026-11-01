{ pkgs, ... }:

{
  # Dependências do script para silencia jogos ao trocar o foco de workspace
  environment.systemPackages = with pkgs; [
    socat
    jq
    gst_all_1.gst-libav
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
  ];
}


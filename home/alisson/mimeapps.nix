{ ... }:

{
  xdg.mimeApps = {
    enable = true;

    defaultApplications = {
      # Gerenciador de arquivos (Thunar)
      "inode/directory" = "thunar.desktop";
      "x-directory/normal" = "thunar.desktop";

      # LibreOffice Writer
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = "writer.desktop";
      "application/msword" = "writer.desktop";
      "application/vnd.oasis.opendocument.text" = "writer.desktop";

      # LibreOffice Calc
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = "calc.desktop";
      "application/vnd.ms-excel" = "calc.desktop";
      "application/vnd.oasis.opendocument.spreadsheet" = "calc.desktop";

      # LibreOffice Impress
      "application/vnd.openxmlformats-officedocument.presentationml.presentation" = "impress.desktop";
      "application/vnd.ms-powerpoint" = "impress.desktop";
      "application/vnd.oasis.opendocument.presentation" = "impress.desktop";

      # PDF (Firefox)
      "application/pdf" = "firefox.desktop";

      # Editor de texto (Neovim no Kitty)
      "text/plain" = "nvim-kitty.desktop";
      "text/x-shellscript" = "nvim-kitty.desktop";
      "text/x-python" = "nvim-kitty.desktop";
      "text/markdown" = "nvim-kitty.desktop";
      "application/json" = "nvim-kitty.desktop";
      "text/x-nix" = "nvim-kitty.desktop";

      # Imagens (Loupe)
      "image/jpeg" = "org.gnome.Loupe.desktop";
      "image/png" = "org.gnome.Loupe.desktop";
      "image/gif" = "org.gnome.Loupe.desktop";
      "image/webp" = "org.gnome.Loupe.desktop";
      "image/bmp" = "org.gnome.Loupe.desktop";
      "image/tiff" = "org.gnome.Loupe.desktop";
      "image/svg+xml" = "org.gnome.Loupe.desktop";
      "image/heif" = "org.gnome.Loupe.desktop";
      "image/avif" = "org.gnome.Loupe.desktop";
      "image/x-icon" = "org.gnome.Loupe.desktop";

      # Vídeos (MPV)
      "video/mp4" = "mpv.desktop";
      "video/x-matroska" = "mpv.desktop";
      "video/webm" = "mpv.desktop";
      "video/quicktime" = "mpv.desktop";
      "video/x-msvideo" = "mpv.desktop";
      "video/mpeg" = "mpv.desktop";
      "video/ogg" = "mpv.desktop";
      "video/x-flv" = "mpv.desktop";
      "video/3gpp" = "mpv.desktop";

      # Arquivos compactados (Ark)
      "application/zip" = "org.kde.ark.desktop";
      "application/x-7z-compressed" = "org.kde.ark.desktop";
      "application/x-rar" = "org.kde.ark.desktop";
      "application/x-tar" = "org.kde.ark.desktop";
      "application/gzip" = "org.kde.ark.desktop";
      "application/x-bzip2" = "org.kde.ark.desktop";
      "application/x-xz" = "org.kde.ark.desktop";
      "application/x-zstd-compressed-tar" = "org.kde.ark.desktop";
      "application/x-compressed-tar" = "org.kde.ark.desktop";
    };
  };
}

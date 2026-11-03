{ config, lib, pkgs, ... }:

let
  # Mapeamento padrão de categorias e extensões de arquivos
  defaultCategories = {
    "Documents" = [
      "pdf" "doc" "docx" "xls" "xlsx" "ppt" "pptx" "odt" "ods" "odp"
      "txt" "rtf" "epub" "mobi" "azw" "azw3" "csv" "tsv" "md" "tex"
    ];
    "Music" = [
      "mp3" "flac" "m4a" "wav" "ogg" "opus" "aac" "wma" "alac" "aiff"
      "mid" "midi" "lrc" "m3u" "m3u8"
    ];
    "Pictures" = [
      "png" "jpg" "jpeg" "webp" "svg" "gif" "bmp" "tiff" "tif" "avif"
      "ico" "psd" "xcf" "raw" "cr2" "nef"
    ];
    "Videos" = [
      "mp4" "mkv" "webm" "avi" "mov" "wmv" "flv" "m4v" "ts" "3gp"
      "srt" "sbv" "vtt" "ass"
    ];
    "Compressed" = [
      "zip" "rar" "7z" "tar" "gz" "bz2" "xz" "zst" "tgz" "tbz2" "txz"
      "iso" "dmg" "tar.gz" "tar.bz2" "tar.xz" "tar.zst"
    ];
    "Program" = [
      # Linguagens para Web e Estilização
      "html" "htm" "css" "scss" "sass" "less" "js" "jsx" "ts" "tsx" "vue" "svelte"
      # Scripts e Linguagens de Programação
      "py" "ipynb" "java" "class" "jar" "rs" "sh" "bash" "zsh" "fish"
      "c" "cpp" "cc" "cxx" "h" "hpp" "go" "nix" "sql" "lua" "rb" "php" "dart" "gd"
      # Formatos de Dados e Configuração de Desenvolvimento
      "json" "yaml" "yml" "toml" "xml" "patch" "diff"
      # Pacotes e Executáveis de Desenvolvimento / Softwares
      "appimage" "flatpak" "apk" "exe"
    ];
  };

  cfg = config.programs.file-organizer;

  # Geração das declarações Bash a partir das categorias configuradas no Nix
  categoryDeclarations = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (category: extensions: ''
      CATEGORIES+=("${category}")
      ${lib.concatStringsSep "\n" (
        map (ext: ''
          EXT_TO_CATEGORY["${lib.toLower ext}"]="${category}"
        '') extensions
      )}
    '') cfg.categories
  );

  fileOrganizerScript = pkgs.writeShellApplication {
    name = "organize-files";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnused
    ];
    text = ''
      set -Eeuo pipefail

      # Configuração de Cores para Terminal
      if [[ -t 1 ]] && [[ -z "''${NO_COLOR:-}" ]]; then
        C_RESET='\033[0m'
        C_BOLD='\033[1m'
        C_GREEN='\033[32m'
        C_YELLOW='\033[33m'
        C_CYAN='\033[36m'
        C_RED='\033[31m'
        C_DIM='\033[2m'
      else
        C_RESET=""
        C_BOLD=""
        C_GREEN=""
        C_YELLOW=""
        C_CYAN=""
        C_RED=""
        C_DIM=""
      fi

      DRY_RUN=false
      VERBOSE=false
      QUIET=false
      TARGET_DIR=""

      log_info() {
        if [[ "$QUIET" == "false" ]]; then
          printf "%b[INFO]%b %s\n" "$C_CYAN" "$C_RESET" "$*"
        fi
      }

      log_success() {
        if [[ "$QUIET" == "false" ]]; then
          printf "%b[SUCESSO]%b %s\n" "$C_GREEN" "$C_RESET" "$*"
        fi
      }

      log_warn() {
        printf "%b[AVISO]%b %s\n" "$C_YELLOW" "$C_RESET" "$*" >&2
      }

      log_error() {
        printf "%b[ERRO]%b %s\n" "$C_RED" "$C_RESET" "$*" >&2
      }

      log_sim() {
        if [[ "$QUIET" == "false" ]]; then
          printf "%b[SIMULAÇÃO]%b %s\n" "$C_YELLOW" "$C_RESET" "$*"
        fi
      }

      show_help() {
        cat << 'HELP'
Organizador Inteligente de Arquivos por Categoria

USO:
    organize-files [DIRETÓRIO] [OPÇÕES]
    organize [DIRETÓRIO] [OPÇÕES]

ARGUMENTOS:
    DIRETÓRIO               Diretório a ser organizado. Se omitido, utiliza o
                            diretório atual onde o comando foi chamado ($PWD).
                            Pode ser executado em qualquer pasta sem privilégios de sudo.

OPÇÕES:
    -n, --dry-run           Modo de simulação: analisa e exibe o que seria feito,
                            sem criar pastas nem mover nenhum arquivo.
    -v, --verbose           Modo detalhado: exibe cada arquivo processado e movido.
    -q, --quiet             Modo silencioso: suprime mensagens informativas, exibindo
                            apenas o relatório final da operação.
    -d, --dir DIRETÓRIO     Especifica explicitamente o diretório alvo.
    -h, --help              Exibe esta mensagem de ajuda e encerra.
    --version               Exibe a versão do programa.

CATEGORIAS PADRÃO E DESTINOS:
    Documents/              Documentos de texto, planilhas, apresentações, PDFs e e-books
                            (pdf, docx, xlsx, pptx, txt, epub, md, csv, odt, etc.)
    Music/                  Arquivos de áudio, músicas e faixas sonoras
                            (mp3, flac, m4a, wav, ogg, opus, aac, lrc, m3u, etc.)
    Pictures/               Imagens, fotografias, ilustrações e artes
                            (png, jpg, jpeg, webp, svg, gif, bmp, avif, psd, xcf, etc.)
    Videos/                 Filmes, clipes, gravações e legendas de vídeo
                            (mp4, mkv, webm, avi, mov, flv, ts, srt, sbv, etc.)
    Compressed/             Arquivos compactados, pacotes e imagens de disco
                            (zip, rar, 7z, tar, gz, tar.gz, tar.bz2, tar.xz, iso, etc.)
    Program/                Arquivos de código-fonte, scripts, desenvolvimento e binários
                            (html, py, java, rs, sh, c, cpp, js, ts, nix, json, etc.)

REGRAS DE SEGURANÇA:
    • Não move diretórios/pastas (subpastas permanecem intactas no local).
    • Não move arquivos ocultos (iniciados com '.').
    • Mantém arquivos sem extensão ou sem categoria mapeada inalterados.
    • Resolve colisões de nome automaticamente adicionando sufixos (1), (2), etc.
HELP
      }

      # Mapeamento dinâmico gerado pelo Nix
      declare -a CATEGORIES=()
      declare -A EXT_TO_CATEGORY=()

      ${categoryDeclarations}

      get_file_extension() {
        local filename="$1"
        local lower
        lower="$(echo "$filename" | tr '[:upper:]' '[:lower:]')"

        # Testa extensões compostas prioritárias (ex: .tar.gz, .tar.bz2)
        for comp in "tar.gz" "tar.bz2" "tar.xz" "tar.zst"; do
          if [[ "$lower" == *."$comp" ]]; then
            printf '%s\n' "$comp"
            return 0
          fi
        done

        # Extensão simples
        if [[ "$lower" == *.* ]]; then
          printf '%s\n' "''${lower##*.}"
          return 0
        fi

        printf '%s\n' ""
      }

      resolve_destination_path() {
        local target_folder="$1"
        local filename="$2"
        local dest="$target_folder/$filename"

        if [[ ! -e "$dest" ]]; then
          printf '%s\n' "$dest"
          return 0
        fi

        local base="''${filename%.*}"
        local ext=""
        if [[ "$filename" == *.* ]]; then
          ext=".''${filename##*.}"
        fi

        for comp in "tar.gz" "tar.bz2" "tar.xz" "tar.zst"; do
          local lower_filename
          lower_filename="$(echo "$filename" | tr '[:upper:]' '[:lower:]')"
          if [[ "$lower_filename" == *."$comp" ]]; then
            base="''${filename%."$comp"}"
            ext=".''${comp}"
            break
          fi
        done

        local counter=1
        while [[ -e "$target_folder/$base ($counter)$ext" ]]; do
          counter=$(( counter + 1 ))
        done

        printf '%s\n' "$target_folder/$base ($counter)$ext"
      }

      # Processamento de argumentos
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -h|--help)
            show_help
            exit 0
            ;;
          --version)
            printf "file-organizer v1.0.0\n"
            exit 0
            ;;
          -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
          -v|--verbose)
            VERBOSE=true
            shift
            ;;
          -q|--quiet)
            QUIET=true
            shift
            ;;
          -d|--dir)
            if [[ -z "''${2:-}" ]]; then
              log_error "A opção '$1' exige o caminho de um diretório."
              exit 1
            fi
            TARGET_DIR="$2"
            shift 2
            ;;
          -*)
            log_error "Opção desconhecida: $1"
            printf "Use --help para visualizar as instruções de uso.\n"
            exit 1
            ;;
          *)
            if [[ -z "$TARGET_DIR" ]]; then
              TARGET_DIR="$1"
            else
              log_warn "Argumento adicional ignorado: $1"
            fi
            shift
            ;;
        esac
      done

      # Diretório padrão: diretório onde o script foi chamado
      if [[ -z "$TARGET_DIR" ]]; then
        TARGET_DIR="$PWD"
      fi

      if [[ ! -d "$TARGET_DIR" ]]; then
        log_error "Diretório não encontrado: '$TARGET_DIR'"
        exit 1
      fi

      TARGET_DIR="$(cd "$TARGET_DIR" && pwd -P)"

      if [[ ! -w "$TARGET_DIR" ]]; then
        log_error "Sem permissão de escrita em '$TARGET_DIR'. Acesso de gravação necessário."
        exit 1
      fi

      declare -A COUNT_PER_CATEGORY=()
      for cat in "''${CATEGORIES[@]}"; do
        COUNT_PER_CATEGORY["$cat"]=0
      done

      MOVED_TOTAL=0
      SKIPPED_DIRS=0
      SKIPPED_HIDDEN=0
      SKIPPED_UNMATCHED=0

      shopt -s nullglob
      files=("$TARGET_DIR"/*)

      if [[ ''${#files[@]} -eq 0 ]]; then
        log_info "Nenhum arquivo encontrado para organizar em: $TARGET_DIR"
        exit 0
      fi

      log_info "Iniciando verificação de arquivos em: $TARGET_DIR"
      if [[ "$DRY_RUN" == "true" ]]; then
        log_sim "Modo de simulação ativo. Nenhuma alteração real no disco será realizada."
      fi

      for item in "''${files[@]}"; do
        [[ -e "$item" ]] || continue

        # 1. Pastas não devem ser movidas
        if [[ -d "$item" ]]; then
          SKIPPED_DIRS=$(( SKIPPED_DIRS + 1 ))
          continue
        fi

        filename="$(basename "$item")"

        # 2. Arquivos ocultos iniciados com '.' não devem ser movidos
        if [[ "$filename" == .* ]]; then
          SKIPPED_HIDDEN=$(( SKIPPED_HIDDEN + 1 ))
          continue
        fi

        # 3. Protege scripts e arquivos de configuração locais
        if [[ "$filename" == "organize" || "$filename" == "organize-files" || "$filename" == "file-organizer.nix" || "$filename" == "default.nix" || "$filename" == "frame-backup.nix" || "$filename" == "README.md" ]]; then
          continue
        fi

        ext="$(get_file_extension "$filename")"

        # 4. Verifica se a extensão possui categoria definida
        if [[ -z "$ext" ]] || [[ ! -v EXT_TO_CATEGORY["$ext"] ]]; then
          SKIPPED_UNMATCHED=$(( SKIPPED_UNMATCHED + 1 ))
          if [[ "$VERBOSE" == "true" ]]; then
            log_info "Sem categoria mapeada (mantido na raiz): $filename"
          fi
          continue
        fi

        category="''${EXT_TO_CATEGORY["$ext"]}"
        dest_folder="$TARGET_DIR/$category"

        # 5. Verifica se a pasta existe na raiz; se não existir, cria
        if [[ ! -d "$dest_folder" ]]; then
          if [[ "$DRY_RUN" == "true" ]]; then
            log_sim "Criaria pasta de destino: $category/"
          else
            mkdir -p "$dest_folder"
            if [[ "$VERBOSE" == "true" ]]; then
              log_info "Pasta criada: $category/"
            fi
          fi
        fi

        dest_path="$(resolve_destination_path "$dest_folder" "$filename")"
        dest_filename="$(basename "$dest_path")"

        if [[ "$DRY_RUN" == "true" ]]; then
          log_sim "Moveria: '$filename' -> '$category/$dest_filename'"
        else
          mv "$item" "$dest_path"
          if [[ "$VERBOSE" == "true" ]]; then
            log_success "'$filename' -> '$category/$dest_filename'"
          fi
        fi

        COUNT_PER_CATEGORY["$category"]=$(( ''${COUNT_PER_CATEGORY["$category"]} + 1 ))
        MOVED_TOTAL=$(( MOVED_TOTAL + 1 ))
      done

      # Exibição do Relatório Consolidado
      printf "\n%b====================================================%b\n" "$C_BOLD" "$C_RESET"
      printf "%b              RELATÓRIO DE ORGANIZAÇÃO              %b\n" "$C_BOLD" "$C_RESET"
      printf "%b====================================================%b\n" "$C_BOLD" "$C_RESET"
      printf " Diretório:  %b%s%b\n" "$C_CYAN" "$TARGET_DIR" "$C_RESET"
      if [[ "$DRY_RUN" == "true" ]]; then
        printf " Modo:       %bSimulação (Dry-Run - nenhum arquivo movido)%b\n\n" "$C_YELLOW" "$C_RESET"
      else
        printf " Modo:       %bExecução Real%b\n\n" "$C_GREEN" "$C_RESET"
      fi

      printf "%b Arquivos organizados por pasta de destino:%b\n" "$C_BOLD" "$C_RESET"
      for cat in "''${CATEGORIES[@]}"; do
        count="''${COUNT_PER_CATEGORY["$cat"]}"
        if [[ $count -gt 0 ]]; then
          printf "   • %-14s %b%4d arquivo(s)%b\n" "$cat:" "$C_GREEN" "$count" "$C_RESET"
        else
          printf "   • %-14s %b%4d arquivo(s)%b\n" "$cat:" "$C_DIM" "$count" "$C_RESET"
        fi
      done

      printf "\n%b Resumo do processamento:%b\n" "$C_BOLD" "$C_RESET"
      printf "   ✓ Total de arquivos movidos:      %b%d%b\n" "$C_BOLD" "$MOVED_TOTAL" "$C_RESET"
      printf "   ℹ Pastas mantidas intactas:       %d\n" "$SKIPPED_DIRS"
      printf "   ℹ Arquivos ocultos ignorados:     %d\n" "$SKIPPED_HIDDEN"
      printf "   ℹ Arquivos sem categoria mapeada: %d\n" "$SKIPPED_UNMATCHED"
      printf "%b====================================================%b\n" "$C_BOLD" "$C_RESET"
    '';
  };

  # Pacote principal com symlink 'organize' adicional
  fileOrganizerPkg = pkgs.runCommand "file-organizer" {
    meta = with lib; {
      description = "Utilitário CLI para organização automática e inteligente de arquivos por extensão";
      license = licenses.mit;
      platforms = platforms.all;
      mainProgram = "organize-files";
    };
  } ''
    mkdir -p "$out/bin"
    cp "${fileOrganizerScript}/bin/organize-files" "$out/bin/organize-files"
    ln -s "$out/bin/organize-files" "$out/bin/organize"
  '';
in
{
  options.programs.file-organizer = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Habilita o utilitário de automação para organização inteligente de arquivos.";
    };

    categories = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = defaultCategories;
      description = "Mapeamento das pastas de destino e suas respectivas extensões de arquivo.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ fileOrganizerPkg ];
  };
}

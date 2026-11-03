{ config, lib, pkgs, ... }:

let
  cfg = config.services.frame-backup;

  enabledGames = lib.filterAttrs (_: g: g.enable) cfg.games;

  # Coleta de todos os arquivos de origem para monitoramento no systemd.path
  allWatchedPaths = lib.flatten (lib.mapAttrsToList (_: game:
    lib.mapAttrsToList (_: src: "${game.configDir}/${src}") game.files
  ) enabledGames);

  # Geração das declarações Bash dos jogos e seus arquivos mapeados
  gameDeclarations = lib.concatStringsSep "\n" (lib.mapAttrsToList (gameName: game: ''
    GAMES+=("${gameName}")
    GAME_CONFIG_DIR["${gameName}"]="${game.configDir}"
    GAME_PROCESS["${gameName}"]="${game.processName}"
    GAME_FILES["${gameName}"]=""
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (dest: src: ''
      GAME_FILES["${gameName}"]+=" ${dest}"
      GAME_FILE_SRC["${gameName}:${dest}"]="${src}"
    '') game.files)}
  '') enabledGames);

  frameConfigPkg = pkgs.writeShellApplication {
    name = "frame-config";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.util-linux
      pkgs.systemd
      pkgs.procps
      pkgs.gnused
      pkgs.diffutils
      pkgs.gawk
    ];
    text = ''
      set -Eeuo pipefail

      BACKUP_DIR="${cfg.backupDir}"
      LOG_MAX_LINES="${toString cfg.logMaxLines}"
      DEFER_WHILE_RUNNING="${lib.boolToString cfg.deferWhileRunning}"

      parse_delay_seconds() {
        local delay="$1"
        if [[ "$delay" =~ ^([0-9]+)m$ ]]; then
          echo $(( BASH_REMATCH[1] * 60 ))
        elif [[ "$delay" =~ ^([0-9]+)s$ ]]; then
          echo "''${BASH_REMATCH[1]}"
        elif [[ "$delay" =~ ^([0-9]+)h$ ]]; then
          echo $(( BASH_REMATCH[1] * 3600 ))
        elif [[ "$delay" =~ ^[0-9]+$ ]]; then
          echo "$delay"
        else
          echo 120
        fi
      }

      COMMIT_DELAY_SEC="$(parse_delay_seconds "${cfg.commitDelay}")"

      RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/frame-config-backup"
      STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/frame-config-backup"
      mkdir -p "$RUNTIME_DIR" "$STATE_DIR"

      LOG_FILE="$STATE_DIR/backup.log"
      COMMIT_LOCK="$RUNTIME_DIR/commit.lock"
      HAS_DEFERRED=false

      declare -A GAME_CONFIG_DIR=() GAME_PROCESS=() GAME_FILES=() GAME_FILE_SRC=()
      GAMES=()

      # Carrega os jogos configurados no módulo Nix
      ${gameDeclarations}

      log() {
        local msg
        msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
        echo "$msg"
        echo "$msg" >> "$LOG_FILE"
      }

      trim_log() {
        if [[ -f "$LOG_FILE" ]] && [[ "$(wc -l <"$LOG_FILE")" -gt "$LOG_MAX_LINES" ]]; then
          tail -n "$LOG_MAX_LINES" "$LOG_FILE" >"$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
        fi
      }

      game_is_configured() {
        local g="$1"
        for item in "''${GAMES[@]}"; do
          if [[ "$item" == "$g" ]]; then
            return 0
          fi
        done
        return 1
      }

      # Função reutilizável para checar se o jogo está em execução
      # Retorna:
      #   0 = processo encontrado (em execução)
      #   1 = processo não encontrado (fechado)
      #   2 = erro inesperado na detecção
      check_game_running() {
        local g="$1"
        local proc="''${GAME_PROCESS[$g]:-}"
        if [[ -z "$proc" ]]; then
          return 1
        fi

        local escaped_proc
        # shellcheck disable=SC2016
        escaped_proc="$(printf '%s\n' "$proc" | sed 's/[.[\*^$()+?{|]/\\&/g')"
        local pattern="(^|[/\\])''${escaped_proc}([[:space:]]|$)"

        local exit_code=0
        pgrep -f "$pattern" >/dev/null 2>&1 || exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
          return 0
        elif [[ $exit_code -eq 1 ]]; then
          return 1
        else
          log "[$g] ERRO: Falha inesperada ao executar pgrep para '$proc' (código de saída $exit_code)."
          return 2
        fi
      }

      # Determina se há alterações pendentes comparando arquivos de origem com backup/git
      game_has_pending_changes() {
        local g="$1"
        local cfg_dir="''${GAME_CONFIG_DIR[$g]:-}"

        if [[ -d "$cfg_dir" ]]; then
          # shellcheck disable=SC2086
          for dest in ''${GAME_FILES[$g]}; do
            local src="''${GAME_FILE_SRC["$g:$dest"]}"
            local src_path="$cfg_dir/$src"
            local dest_path="$BACKUP_DIR/$g/$dest"

            if [[ -f "$src_path" && -r "$src_path" && -s "$src_path" ]]; then
              if [[ ! -f "$dest_path" ]]; then
                return 0
              fi
              if ! cmp -s "$src_path" "$dest_path"; then
                return 0
              fi
            fi
          done
        fi

        if [[ -d "$BACKUP_DIR/.git" ]]; then
          if [[ -n "$(git -C "$BACKUP_DIR" status --porcelain -- "$g" 2>/dev/null)" ]]; then
            return 0
          fi
        fi

        return 1
      }

      # Verifica se o debounce (ex: 2m) já transcorreu desde a última modificação dos arquivos
      game_debounce_elapsed() {
        local g="$1"
        local cfg_dir="''${GAME_CONFIG_DIR[$g]:-}"
        local now
        now="$(date +%s)"

        if [[ -d "$cfg_dir" ]]; then
          # shellcheck disable=SC2086
          for dest in ''${GAME_FILES[$g]}; do
            local src="''${GAME_FILE_SRC["$g:$dest"]}"
            local src_path="$cfg_dir/$src"
            if [[ -f "$src_path" ]]; then
              local mtime
              mtime="$(stat -c %Y "$src_path" 2>/dev/null || echo 0)"
              local age=$(( now - mtime ))
              if (( age < COMMIT_DELAY_SEC )); then
                return 1 # Ainda dentro da janela de debounce
              fi
            fi
          done
        fi

        return 0 # Debounce decorrido
      }

      cleanup() {
        if [[ "''${HAS_DEFERRED:-false}" == "true" ]]; then
          systemctl --user restart frame-backup-delayed.timer >/dev/null 2>&1 || true
        fi
        trim_log
      }
      trap cleanup EXIT

      do_sync() {
        local target_game="all"
        local is_auto=false
        HAS_DEFERRED=false

        while [[ $# -gt 0 ]]; do
          case "$1" in
            --auto)
              is_auto=true
              shift
              ;;
            --force)
              is_auto=false
              shift
              ;;
            *)
              if game_is_configured "$1" || [[ "$1" == "all" ]]; then
                target_game="$1"
              else
                log "[sync] ERRO: Jogo '$1' não está configurado ou habilitado."
                exit 1
              fi
              shift
              ;;
          esac
        done

        exec {commit_fd}>"$COMMIT_LOCK"
        if ! flock -n "$commit_fd"; then
          log "[lock] AVISO: Outro processo de sincronização já está em execução. Encerrando."
          exit 0
        fi

        if [[ ! -d "$BACKUP_DIR" ]]; then
          log "[git] ERRO: Diretório de backup não encontrado em $BACKUP_DIR."
          exit 1
        fi

        if ! git -C "$BACKUP_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
          log "[git] ERRO: $BACKUP_DIR não é um repositório Git válido."
          exit 1
        fi

        local active_games=()
        if [[ "$target_game" == "all" ]]; then
          active_games=("''${GAMES[@]}")
        else
          active_games=("$target_game")
        fi

        local games_to_sync=()

        for g in "''${active_games[@]}"; do
          # Se for execução manual ou se deferWhileRunning estiver desabilitado:
          if [[ "$is_auto" != "true" ]] || [[ "$DEFER_WHILE_RUNNING" != "true" ]]; then
            local run_state=0
            check_game_running "$g" || run_state=$?
            if [[ $run_state -eq 0 ]]; then
              log "[$g] AVISO: Sincronização manual executada com o jogo em execução. Os arquivos podem estar em estado intermediário."
            fi
            rm -f "$STATE_DIR/defer_$g.state"
            games_to_sync+=("$g")
            continue
          fi

          # Modo automático com deferWhileRunning=true
          # 1. Identificar se o jogo possui alterações pendentes
          if ! game_has_pending_changes "$g"; then
            rm -f "$STATE_DIR/defer_$g.state"
            continue
          fi

          # 2. Verificar individualmente o processo
          local run_code=0
          check_game_running "$g" || run_code=$?

          if [[ $run_code -eq 0 ]] || [[ $run_code -eq 2 ]]; then
            # Jogo em execução ou erro de detecção: adiar sincronização
            HAS_DEFERRED=true
            if [[ ! -f "$STATE_DIR/defer_$g.state" ]]; then
              log "[$g] Processo detectado; backup automático adiado."
              log "[$g] Alterações pendentes; nova verificação agendada."
              echo "deferred" > "$STATE_DIR/defer_$g.state"
            fi
          else
            # Jogo encerrado e com alterações pendentes:
            # Respeitar o debounce (2m) para evitar que reavaliações antecipem o backup
            if ! game_debounce_elapsed "$g"; then
              HAS_DEFERRED=true
              continue
            fi

            if [[ -f "$STATE_DIR/defer_$g.state" ]]; then
              log "[$g] Jogo encerrado; sincronização permitida."
              rm -f "$STATE_DIR/defer_$g.state"
            fi
            games_to_sync+=("$g")
          fi
        done

        local modified_games=()
        local paths_to_commit=()

        if (( ''${#games_to_sync[@]} > 0 )); then
          for g in "''${games_to_sync[@]}"; do
            local cfg_dir="''${GAME_CONFIG_DIR[$g]}"
            if [[ ! -d "$cfg_dir" ]]; then
              log "[$g] AVISO: Diretório de configurações não encontrado em $cfg_dir. Pulando."
              continue
            fi

            mkdir -p "$BACKUP_DIR/$g"
            local game_has_file=false

            # shellcheck disable=SC2086
            for dest in ''${GAME_FILES[$g]}; do
              local src="''${GAME_FILE_SRC["$g:$dest"]}"
              local src_path="$cfg_dir/$src"
              local dest_path="$BACKUP_DIR/$g/$dest"

              if [[ ! -f "$src_path" ]] || [[ ! -r "$src_path" ]] || [[ ! -s "$src_path" ]]; then
                log "[$g] AVISO: Arquivo '$src' não encontrado, inacessível ou vazio em $src_path. Backup prévio mantido."
                continue
              fi

              mkdir -p "$(dirname "$dest_path")"
              local tmp_dest="$BACKUP_DIR/$g/.$dest.tmp.$$"

              cp -f "$src_path" "$tmp_dest"

              if [[ ! -s "$tmp_dest" ]]; then
                rm -f "$tmp_dest"
                log "[$g] ERRO: Cópia temporária falhou para '$dest'. Backup preservado."
                continue
              fi

              mv -f "$tmp_dest" "$dest_path"
              git -C "$BACKUP_DIR" add "$g/$dest"
              paths_to_commit+=("$g/$dest")
              game_has_file=true
            done

            if [[ "$game_has_file" == "true" ]]; then
              if ! git -C "$BACKUP_DIR" diff --cached --quiet -- "$g"; then
                modified_games+=("$g")
                log "[$g] Configurações sincronizadas."
              fi
            fi
          done

          if (( ''${#modified_games[@]} > 0 )); then
            local game_list
            game_list=$(IFS=,; echo "''${modified_games[*]}")
            local commit_msg
            commit_msg="config($game_list): $(date '+%Y-%m-%d %H:%M:%S')"
            if commit_out="$(git -C "$BACKUP_DIR" commit -m "$commit_msg" -- "''${paths_to_commit[@]}" 2>&1)"; then
              log "[git] Commit criado: $commit_msg"
            else
              log "[git] ERRO ao criar commit: $commit_out"
              exit 1
            fi
          else
            log "[git] Nenhuma alteração real identificada nos arquivos."
          fi
        else
          if [[ "$HAS_DEFERRED" != "true" ]] && [[ "$is_auto" != "true" ]]; then
            log "[git] Nenhuma alteração real identificada nos arquivos."
          fi
        fi

        local current_branch
        current_branch="$(git -C "$BACKUP_DIR" rev-parse --abbrev-ref HEAD)"
        local has_upstream=false
        if git -C "$BACKUP_DIR" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
          has_upstream=true
        fi

        local needs_push=false
        local push_cmd=()

        if [[ "$has_upstream" == "true" ]]; then
          local unpushed_count
          unpushed_count="$(git -C "$BACKUP_DIR" rev-list '@{u}..HEAD' --count 2>/dev/null || echo 0)"
          if (( unpushed_count > 0 )); then
            needs_push=true
            log "[git] Identificado(s) $unpushed_count commit(s) local(is) pendente(s) de push."
            if ! pull_out="$(git -C "$BACKUP_DIR" pull --rebase --autostash 2>&1)"; then
              git -C "$BACKUP_DIR" rebase --abort 2>/dev/null || true
              log "[git] ERRO: git pull --rebase falhou. Rebase abortado para manter integridade local. Detalhes: $pull_out"
              exit 1
            fi
            push_cmd=(git -C "$BACKUP_DIR" push)
          fi
        else
          needs_push=true
          log "[git] Branch '$current_branch' sem upstream configurado. Configurando upstream no push."
          push_cmd=(git -C "$BACKUP_DIR" push -u origin "$current_branch")
        fi

        if [[ "$needs_push" == "true" ]]; then
          local push_success=false
          local max_attempts=3
          for ((attempt=1; attempt<=max_attempts; attempt++)); do
            if "''${push_cmd[@]}" 2>&1; then
              push_success=true
              log "[git] Push enviado com sucesso ao remoto."
              break
            else
              log "[git] Tentativa $attempt/$max_attempts de git push falhou."
              if (( attempt < max_attempts )); then
                sleep 5
              fi
            fi
          done

          if [[ "$push_success" == "false" ]]; then
            log "[git] AVISO: Falha no git push após $max_attempts tentativas. Commits mantidos localmente."
            exit 1
          fi
        else
          if (( ''${#modified_games[@]} > 0 )) || [[ "$is_auto" != "true" ]]; then
            log "[git] Repositório local já está sincronizado com o remoto."
          fi
        fi
      }

      do_status() {
        echo "=== Status das Sessões de Jogo ==="
        for g in "''${GAMES[@]}"; do
          local g_display
          g_display="$(tr '[:lower:]' '[:upper:]' <<< "''${g:0:1}")''${g:1}"

          local run_code=0
          check_game_running "$g" || run_code=$?

          local proc_status="Encerrado"
          if [[ $run_code -eq 0 ]]; then
            proc_status="Em execução"
          elif [[ $run_code -eq 2 ]]; then
            proc_status="Erro na detecção"
          fi

          local backup_status="Sincronizado"
          if game_has_pending_changes "$g"; then
            if [[ $run_code -eq 0 ]] || [[ -f "$STATE_DIR/defer_$g.state" ]]; then
              backup_status="Pendente (adiado)"
            elif ! game_debounce_elapsed "$g"; then
              backup_status="Pendente (debounce)"
            else
              backup_status="Pendente"
            fi
          fi

          echo "$g_display"
          echo "  Processo: $proc_status (''${GAME_PROCESS[$g]})"
          echo "  Backup: $backup_status"
          echo ""
        done

        echo "=== Timer de Debounce ==="
        local timer_left="Inativo (aguardando alterações)"
        if systemctl --user is-active --quiet frame-backup-delayed.timer 2>/dev/null; then
          local substate
          substate="$(systemctl --user show frame-backup-delayed.timer --property=SubState --value 2>/dev/null || true)"
          if [[ "$substate" == "waiting" ]]; then
            local left
            left="$(systemctl --user list-timers frame-backup-delayed.timer --no-legend 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /left$/) print $(i-1), $i}')"
            if [[ -n "$left" ]]; then
              timer_left="$left"
            else
              timer_left="Ativo (aguardando disparo)"
            fi
          elif [[ "$substate" == "elapsed" ]]; then
            timer_left="Disparado (concluído)"
          else
            timer_left="$substate"
          fi
        fi
        echo "  Próxima verificação: $timer_left"
        echo ""

        echo "=== Repositório Git de Backup ($BACKUP_DIR) ==="
        if [[ -d "$BACKUP_DIR/.git" ]]; then
          local unpushed=0
          if git -C "$BACKUP_DIR" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
            unpushed="$(git -C "$BACKUP_DIR" rev-list '@{u}..HEAD' --count 2>/dev/null || echo 0)"
          fi
          echo "  Commits pendentes de push: $unpushed"
          echo "  Último commit:"
          git -C "$BACKUP_DIR" log -1 --format="    %h - %s (%cr)" 2>/dev/null || echo "    (nenhum commit)"
          echo "  Status:"
          git -C "$BACKUP_DIR" status -sb 2>/dev/null | sed 's/^/    /' || true
        else
          echo "  Repositório Git não encontrado em $BACKUP_DIR"
        fi
        echo ""

        echo "=== Detalhes dos Arquivos Monitorados ==="
        for g in "''${GAMES[@]}"; do
          local cfg_dir="''${GAME_CONFIG_DIR[$g]}"
          echo "Jogo: $g"
          echo "  Diretório Proton: $cfg_dir"
          # shellcheck disable=SC2086
          for dest in ''${GAME_FILES[$g]}; do
            local src="''${GAME_FILE_SRC["$g:$dest"]}"
            local src_path="$cfg_dir/$src"
            local backup_path="$BACKUP_DIR/$g/$dest"
            local src_status="Ausente"
            local bkp_status="Ausente"
            local diff_status="Sincronizado"

            if [[ -f "$src_path" ]]; then
              src_status="Presente ($(wc -c <"$src_path") bytes)"
            fi
            if [[ -f "$backup_path" ]]; then
              bkp_status="Presente ($(wc -c <"$backup_path") bytes)"
            fi

            if [[ -f "$src_path" && -f "$backup_path" ]]; then
              if ! cmp -s "$src_path" "$backup_path"; then
                diff_status="Modificado (origem difere do backup)"
              fi
            elif [[ -f "$src_path" && ! -f "$backup_path" ]]; then
              diff_status="Novo (ainda não salvo no backup)"
            fi

            echo "  Arquivo '$dest':"
            echo "    Origem ($src): $src_status"
            echo "    Backup ($g/$dest): $bkp_status"
            echo "    Estado: $diff_status"
          done
          echo ""
        done

        echo "=== Status dos Serviços Systemd ==="
        echo "systemd.path:"
        systemctl --user status frame-backup-watch.path --no-pager 2>&1 | sed 's/^/  /' || true
        echo "systemd.timer:"
        systemctl --user list-timers frame-backup-delayed.timer --no-pager 2>&1 | sed 's/^/  /' || true
        echo ""

        echo "=== Últimos Logs de Sincronização ==="
        if [[ -f "$LOG_FILE" ]]; then
          tail -n 10 "$LOG_FILE" | sed 's/^/  /'
        else
          echo "  Nenhum log encontrado em $LOG_FILE"
        fi
      }

      do_restore() {
        local target_game="''${1:-}"
        if [[ -z "$target_game" ]]; then
          echo "ERRO: É obrigatório informar o jogo para restaurar."
          echo "Uso: frame-config restore <warframe|soulframe>"
          exit 1
        fi

        if ! game_is_configured "$target_game"; then
          echo "ERRO: Jogo '$target_game' não está configurado."
          echo "Jogos disponíveis: ''${GAMES[*]}"
          exit 1
        fi

        local cfg_dir="''${GAME_CONFIG_DIR[$target_game]}"
        local proc="''${GAME_PROCESS[$target_game]}"

        echo "=== Restauração de Configurações: $target_game ==="
        echo "Origem (Backup):  $BACKUP_DIR/$target_game"
        echo "Destino (Proton): $cfg_dir"
        echo ""

        # Valida existência de backups
        local found_backup=false
        # shellcheck disable=SC2086
        for dest in ''${GAME_FILES[$target_game]}; do
          if [[ -f "$BACKUP_DIR/$target_game/$dest" ]]; then
            found_backup=true
          fi
        done

        if [[ "$found_backup" != "true" ]]; then
          echo "ERRO: Nenhum arquivo de backup encontrado para o jogo '$target_game' em $BACKUP_DIR/$target_game."
          exit 1
        fi

        # Bloqueia restauração caso o jogo esteja aberto ou erro na detecção
        local run_code=0
        check_game_running "$target_game" || run_code=$?
        if [[ $run_code -eq 0 ]] || [[ $run_code -eq 2 ]]; then
          echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
          if [[ $run_code -eq 0 ]]; then
            echo "ERRO: O processo '$proc' está em execução neste momento!"
          else
            echo "ERRO: Não foi possível verificar o estado do processo '$proc' com segurança!"
          fi
          echo "A restauração foi bloqueada para evitar que o jogo sobrescreva os arquivos."
          echo "Feche o $target_game completamente antes de tentar restaurar."
          echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
          exit 1
        fi

        read -r -p "Confirma a restauração das configurações de '$target_game'? [s/N] " answer
        if [[ "$answer" != "s" ]] && [[ "$answer" != "S" ]]; then
          echo "Operação cancelada pelo usuário."
          exit 0
        fi

        local ts
        ts="$(date +%Y%m%d_%H%M%S)"

        # shellcheck disable=SC2086
        for dest in ''${GAME_FILES[$target_game]}; do
          local src="''${GAME_FILE_SRC["$target_game:$dest"]}"
          local src_path="$cfg_dir/$src"
          local backup_path="$BACKUP_DIR/$target_game/$dest"

          if [[ ! -f "$backup_path" ]]; then
            echo "Aviso: Arquivo de backup '$dest' não existe no repositório. Ignorando."
            continue
          fi

          mkdir -p "$(dirname "$src_path")"

          if [[ -f "$src_path" ]]; then
            cp -f "$src_path" "$src_path.pre-restore.$ts"
            echo "Backup pré-restauração salvo em: $src_path.pre-restore.$ts"
          fi

          cp -f "$backup_path" "$src_path"
          echo "Arquivo '$dest' restaurado com sucesso para $src_path."
        done

        echo ""
        echo "Restauração de '$target_game' finalizada com sucesso!"
      }

      action="''${1:-status}"
      case "$action" in
        sync|--sync)
          shift || true
          do_sync "$@"
          ;;
        status|--status)
          do_status
          ;;
        restore|--restore)
          shift || true
          do_restore "''${1:-}"
          ;;
        help|--help|-h)
          echo "Uso: frame-config <comando> [argumentos]"
          echo "Comandos:"
          echo "  status                  Exibe status dos jogos, systemd, git e logs"
          echo "  sync [jogo] [--force]   Executa sincronização (todos os jogos ou específico)"
          echo "  restore <jogo>          Restaura interativamente configurações de um jogo específico"
          echo "  help                    Exibe esta ajuda"
          echo ""
          echo "Exemplos:"
          echo "  frame-config status"
          echo "  frame-config sync"
          echo "  frame-config sync warframe"
          echo "  frame-config sync soulframe"
          echo "  frame-config restore warframe"
          echo "  frame-config restore soulframe"
          ;;
        *)
          echo "Comando desconhecido: $action"
          echo "Execute 'frame-config help' para ver as opções disponíveis."
          exit 1
          ;;
      esac
    '';
  };
in
{
  options.services.frame-backup = {
    enable = lib.mkEnableOption "Backup automático e versionamento das configurações de Warframe e Soulframe";

    backupDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.system/warframe-save";
      description = "Diretório local do repositório Git onde os arquivos são versionados.";
    };

    commitDelay = lib.mkOption {
      type = lib.types.str;
      default = "2m";
      description = "Intervalo de inatividade (debounce) compartilhado antes de efetuar o commit.";
    };

    deferWhileRunning = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Se habilitado, adia o backup automático de configurações de jogos em execução até o seu encerramento.";
    };

    logMaxLines = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Quantidade máxima de linhas mantidas no arquivo de log.";
    };

    games = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Habilita o backup para este jogo.";
          };

          configDir = lib.mkOption {
            type = lib.types.str;
            description = "Diretório base de configurações do jogo no prefixo Proton.";
          };

          processName = lib.mkOption {
            type = lib.types.str;
            default = "${name}.x64.exe";
            description = "Nome do processo executável para verificar se o jogo está rodando durante sync e restore.";
          };

          files = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            description = "Mapeamento { destinationRelPath = sourceRelPath; } relativo ao configDir e backupDir/<game>.";
          };
        };
      }));
      default = {
        warframe = {
          enable = true;
          configDir = "${config.home.homeDirectory}/.local/share/Steam/steamapps/compatdata/230410/pfx/drive_c/users/steamuser/AppData/Local/Warframe";
          processName = "Warframe.x64.exe";
          files = {
            "EE.cfg" = "EE.cfg";
            "settings" = "04D8C3E3BDAE51F4A83AAE46F6808090/settings";
          };
        };
        soulframe = {
          enable = true;
          configDir = "${config.home.homeDirectory}/.local/share/Steam/steamapps/compatdata/4281307271/pfx/drive_c/users/steamuser/AppData/Local/Soulframe";
          processName = "Soulframe.x64.exe";
          files = {
            "EE.cfg" = "EE.cfg";
            "settings" = "04D8C3E3BDAE51F4A83AAE46F6808090/settings";
          };
        };
      };
      description = "Configuração dos jogos gerenciados pelo frame-backup.";
    };
  };

  config = lib.mkIf (cfg.enable && enabledGames != {}) {
    home.packages = [ frameConfigPkg ];

    # 1. Unidade de monitoramento inotify compartilhada para todos os jogos
    systemd.user.paths.frame-backup-watch = {
      Unit = {
        Description = "Monitora alterações nas configurações de Warframe e Soulframe";
      };
      Path = {
        PathModified = allWatchedPaths;
        Unit = "frame-backup-reschedule.service";
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    # 2. Serviço de reagendamento compartilhado (reinicia o timer com debounce)
    systemd.user.services.frame-backup-reschedule = {
      Unit = {
        Description = "Reinicia timer de debounce do Frame Backup";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl --user restart frame-backup-delayed.timer";
      };
    };

    # 3. Timer de debounce compartilhado
    systemd.user.timers.frame-backup-delayed = {
      Unit = {
        Description = "Timer de debounce compartilhado para backup de Warframe e Soulframe";
      };
      Timer = {
        OnActiveSec = cfg.commitDelay;
        AccuracySec = "1s";
        Unit = "frame-backup-commit.service";
      };
      Install = {
        WantedBy = [ "timers.target" ];
      };
    };

    # 4. Serviço final de sincronização Git
    systemd.user.services.frame-backup-commit = {
      Unit = {
        Description = "Sincroniza configurações dos jogos com o Git";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${frameConfigPkg}/bin/frame-config sync --auto";
      };
    };
  };
}

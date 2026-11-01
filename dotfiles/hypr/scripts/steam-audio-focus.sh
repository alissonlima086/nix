#!/usr/bin/env bash

set -u

TICK=2 # intervalo máximo até convergir sem eventos

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_PREFIX="$SCRIPT_DIR/steam-audio-focus"
LOG_MAX=$((10 * 1024 * 1024))
LOG_FILE=""
LOG_DAY=""

# Log diário: apaga os dias anteriores, recomeça a partir de LOG_MAX
log() {
  local ts day f
  printf -v ts '%(%F %T)T' -1
  day="${ts%% *}"
  if [[ "$day" != "$LOG_DAY" ]]; then
    LOG_DAY="$day"
    LOG_FILE="$LOG_PREFIX-$day.log"
    for f in "$LOG_PREFIX"-*.log "$LOG_PREFIX"-*.txt; do
      [[ "$f" == "$LOG_FILE" ]] || rm -f "$f"
    done
  elif [[ -f "$LOG_FILE" ]] && (($(wc -c <"$LOG_FILE") > LOG_MAX)); then
    rm -f "$LOG_FILE"
  fi
  echo "[steam-audio-focus] $*" >&2
  { echo "$ts $*" >>"$LOG_FILE"; } 2>/dev/null
  return 0
}

for cmd in socat jq pw-dump wpctl hyprctl; do
  command -v "$cmd" &>/dev/null || {
    log "ERRO: comando ausente: $cmd"
    exit 1
  }
done
[[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || {
  log "ERRO: fora de uma sessão Hyprland"
  exit 1
}

HYPR_SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

ppid_of() { # $1=pid -> PPID_OUT
  local stat
  IFS= read -r stat 2>/dev/null <"/proc/$1/stat" || return 1
  read -r _ PPID_OUT _ <<<"${stat##*) }"
  [[ "$PPID_OUT" =~ ^[0-9]+$ ]]
}

declare -A WIN_PIDS=() FOCUS_TREE=()
FOCUS_PID=""
read_focus() {
  local out pid depth
  WIN_PIDS=()
  FOCUS_TREE=()
  FOCUS_PID=""

  out="$(hyprctl clients -j 2>/dev/null)" || return 1
  while read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] && WIN_PIDS["$pid"]=1
  done < <(jq -r '.[].pid' <<<"$out" 2>/dev/null)

  out="$(hyprctl activewindow -j 2>/dev/null)" || return 1
  if pid="$(jq -er '.pid // empty' <<<"$out" 2>/dev/null)"; then
    [[ "$pid" =~ ^[0-9]+$ ]] && ((pid > 1)) || return 1
    FOCUS_PID="$pid"
    for ((depth = 0; depth < 32; depth++)); do
      ((pid > 1)) || break
      FOCUS_TREE["$pid"]=1
      ppid_of "$pid" || break
      pid="$PPID_OUT"
    done
  fi
  return 0
}

window_of() {
  local pid="$1" depth
  for ((depth = 0; depth < 32; depth++)); do
    ((pid > 1)) || return 1
    [[ -n "${WIN_PIDS[$pid]:-}" ]] && {
      OWNER="$pid"
      return 0
    }
    ppid_of "$pid" || return 1
    pid="$PPID_OUT"
  done
  return 1
}

audio_streams() {
  pw-dump 2>/dev/null | jq -r '
        INDEX(.[]; "\(.id)") as $idx |
        .[] |
        select(.info.props."media.class" // "" | contains("Stream/Output/Audio")) |
        (
          .info.props."pipewire.sec.pid" //
          .info.props."application.process.id" //
          ($idx["\(.info.props."client.id")"].info.props."pipewire.sec.pid") //
          ($idx["\(.info.props."client.id")"].info.props."application.process.id") //
          0
        ) as $pid |
        "\(.id) \([.info.params.Props[]? | select(has("mute"))][0].mute // false) \($pid)"
    ' 2>/dev/null
}

classify() {
  local pid="$1" comm depth
  if grep -zqsE '^(SteamAppId=|HEROIC_|EOS_|GOG_|LUTRIS_)' "/proc/$pid/environ"; then
    echo 1
    return
  fi
  for ((depth = 0; depth < 32; depth++)); do
    ppid_of "$pid" && pid="$PPID_OUT" && ((pid > 1)) || break
    IFS= read -r comm 2>/dev/null <"/proc/$pid/comm" || break
    case "$comm" in
    heroic | legendary | gogdl | nile | lutris)
      echo 1
      return
      ;;
    esac
  done
  echo 0
}

declare -A GAME_CACHE=()
is_game_stream() { # $1=pid
  local pid="$1" line key v f
  IFS= read -r line 2>/dev/null <"/proc/$pid/stat" || return 1
  read -ra f <<<"${line##*) }"
  key="$pid:${f[19]:-0}"
  v="${GAME_CACHE[$key]:-}"
  if [[ -z "$v" ]]; then
    v="$(classify "$pid")"
    GAME_CACHE["$key"]="$v"
    ((${#GAME_CACHE[@]} > 512)) && GAME_CACHE=(["$key"]="$v")
  fi
  [[ "$v" == 1 ]]
}

CHANGED=0
LAST_RECONCILE=0
reconcile() {
  CHANGED=0
  LAST_RECONCILE=$EPOCHSECONDS
  local id mute pid want mval

  if ! read_focus; then
    log "estado de foco não confiável — reconciliação adiada"
    return
  fi

  while read -r id mute pid; do
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    [[ "$mute" == true || "$mute" == false ]] || continue
    [[ "$pid" =~ ^[0-9]+$ ]] && ((pid > 1)) || continue

    is_game_stream "$pid" || continue
    window_of "$pid" || continue

    if [[ -n "${FOCUS_TREE[$OWNER]:-}" ]]; then want=false mval=0; else want=true mval=1; fi
    [[ "$mute" != "$want" ]] || continue
    wpctl set-mute "$id" "$mval" 2>/dev/null && CHANGED=$((CHANGED + 1))
  done < <(audio_streams)

  ((CHANGED > 0)) && log "reconciliado: $CHANGED stream(s) de jogo ajustado(s) (foco: pid ${FOCUS_PID:-nenhum})"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

cleanup() {
  trap - EXIT TERM INT
  pkill -TERM -P $$ 2>/dev/null # socat
  local id mute pid n=0
  # o WirePlumber persiste mute por aplicação, então desmuta sem depender do Hyprland
  while read -r id mute pid; do
    [[ "$id" =~ ^[0-9]+$ && "$mute" == true ]] || continue
    [[ "$pid" =~ ^[0-9]+$ ]] && ((pid > 1)) || continue
    [[ "$(classify "$pid")" == 1 ]] || continue
    wpctl set-mute "$id" 0 2>/dev/null && n=$((n + 1))
  done < <(audio_streams)
  log "encerrado ($n stream(s) desmutado(s))"
  exit 0
}
trap cleanup EXIT TERM INT

log "iniciado"

while :; do
  if [[ ! -S "$HYPR_SOCKET" ]]; then
    log "socket2 não existe — sessão Hyprland encerrada"
    exit 0
  fi

  reconcile

  while :; do
    if IFS= read -r -t "$TICK" line; then
      if [[ "$line" == activewindow'>>'* ]]; then
        while IFS= read -r -t 0.05 _; do :; done # drena a rajada
        reconcile
      elif ((EPOCHSECONDS - LAST_RECONCILE >= TICK)); then
        # eventos irrelevantes contínuos não podem adiar o tick
        reconcile
      fi
    else
      rc=$?
      ((rc > 128)) || break # EOF: conexão com o socket2 caiu
      reconcile
    fi
  done < <(exec socat -U - UNIX-CONNECT:"$HYPR_SOCKET" 2>/dev/null)

  log "conexão com socket2 perdida — reconectando em 1s"
  sleep 1
done

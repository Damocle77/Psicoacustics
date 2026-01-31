#!/usr/bin/env bash
# stereo251_psico_reactive.sh — Stereo → 5.1 REACTIVE (PAN + SURROUND)
# Stanza 4x5 m, soffitto 4.2 m, YPAO ON, NO chorus
# Fix: pick_audio_stream a 1 riga, heredoc robusto (no read -d '' che rompe su MINGW)

set -Eeuo pipefail
trap '' PIPE

log() { printf '%s\n' "$*" >&2 || true; }

on_err() {
  local rc=$?
  printf '💥 ERRORE: riga %s: %s (rc=%s)\n' "${BASH_LINENO[0]:-?}" "${BASH_COMMAND:-?}" "$rc" >&2 || true
  exit "$rc"
}
trap on_err ERR

usage() {
cat >&2 <<'EOF'
USO:
  ./stereo251_psico.sh pan|surround [codec] [bitrate] file1.mkv [file2.mkv ...]

MODALITÀ:
  pan      - Restauro / vecchi film (spazio stabile)
  surround - Film e serie moderne (spazio reattivo)

CODEC:
  ac3      - Dolby Digital (compatibilità massima, max 640k)
  eac3     - Dolby Digital Plus (default, qualità superiore, fino 1536k)

NOTE:
- Seleziona automaticamente la traccia stereo (ITA se presente)
- Output: *_5.1_<mode>.mkv
EOF
}

[[ $# -ge 2 ]] || { usage; exit 2; }

MODE="${1,,}"; shift
case "$MODE" in
  pan|surround) ;;
  *) log "❌ Mode non valido: '$MODE' (usa pan|surround)"; usage; exit 2 ;;
esac

DEFAULT_CODEC="eac3"
CODEC="$DEFAULT_CODEC"
DEFAULT_BR="448k"
BITRATE="$DEFAULT_BR"

# codec opzionale
if [[ $# -ge 2 ]]; then
  if [[ "${1,,}" == "ac3" || "${1,,}" == "eac3" ]]; then
    CODEC="${1,,}"; shift
  fi
fi

# bitrate opzionale
if [[ $# -ge 2 ]]; then
  if [[ "${1:-}" =~ ^[0-9]+k$ ]]; then
    BITRATE="$1"; shift
  elif [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    BITRATE="${1}k"; shift
  fi
fi

# valida bitrate
if [[ ! "$BITRATE" =~ ^[0-9]+k$ && ! "$BITRATE" =~ ^[0-9]+M$ ]]; then
  log "❌ Bitrate non valido: '$BITRATE' (es: 448k, 640k, 768k, 1M)"
  exit 2
fi

# valida bitrate per AC3 (max 640k)
if [[ "$CODEC" == "ac3" ]]; then
  br_num="${BITRATE%k}"
  if [[ "$br_num" -gt 640 ]]; then
    log "❌ AC3 supporta max 640k, richiesto: $BITRATE"
    log "   Usa 'eac3' per bitrate superiori"
    exit 2
  fi
fi

# calcola fattore lineare da dB (es: 0.6 dB -> ~1.072)
db2lin() {
  local db="${1:-0}"
  awk -v d="$db" 'BEGIN{ printf "%.6f", (10^(d/20.0)) }'
}

# Ritorna SEMPRE una sola riga: indice traccia audio stereo (ITA preferita), fallback 0
pick_audio_stream() {
  local in="$1"
  local probe_output
  local idx=0
  local first_stereo=""
  
  # Ottieni output ffprobe
  probe_output=$(ffprobe -v error -select_streams a -show_entries stream=index,channels:stream_tags=language -of csv=p=0 "$in" 2>/dev/null) || { echo "0"; return 0; }
  
  # Processa riga per riga
  while IFS=',' read -r stream_idx channels lang || [[ -n "$stream_idx" ]]; do
    # Salta se non è stereo
    [[ "$channels" == "2" ]] || continue
    
    # Salva il primo stereo trovato
    if [[ -z "$first_stereo" ]]; then
      first_stereo="$stream_idx"
    fi
    
    # Se è italiano, usalo subito
    lang_lower=$(echo "$lang" | tr '[:upper:]' '[:lower:]')
    if [[ "$lang_lower" == "ita" || "$lang_lower" == "it" ]]; then
      echo "$stream_idx"
      return 0
    fi
  done <<< "$probe_output"
  
  # Fallback: primo stereo o 0
  echo "${first_stereo:-0}"
}

ASK_OVERWRITE_ALL="ask"
should_overwrite() {
  local out="$1"
  [[ ! -e "$out" ]] && return 0

  case "$ASK_OVERWRITE_ALL" in
    yes) return 0 ;;
    no)  return 1 ;;
  esac

  log "⚠️  Output già presente: $out"
  while true; do
    printf "Sovrascrivere? [s]ì / [n]o / [t]utti sì / [a] tutti no: " >&2 || true
    read -r ans || true
    ans="${ans,,}"
    case "$ans" in
      s|si|y|yes) return 0 ;;
      n|no)       return 1 ;;
      t)          ASK_OVERWRITE_ALL="yes"; return 0 ;;
      a)          ASK_OVERWRITE_ALL="no";  return 1 ;;
      *)          log "Risposta non valida. Usa s/n/t/a." ;;
    esac
  done
}

for IN in "$@"; do
  [[ -f "$IN" ]] || { log "⚠️  File non trovato: $IN"; continue; }

  base="${IN##*/}"
  name="${base%.*}"
  ext="${base##*.}"
  outdir="$(dirname "$IN")"
  OUT="$outdir/${name}_5.1_${MODE}.${ext}"

  if ! should_overwrite "$OUT"; then
    log "⏭️  Skip: $OUT"
    continue
  fi

  aidx="$(pick_audio_stream "$IN")"

  log "──────────────────────────────────────────────"
  log "Input:  $IN"
  log "Mode:   ${MODE^^}"
  log "Audio:  a:$aidx"
  log "Codec:  ${CODEC^^}"
  log "Bitrate:$BITRATE"
  log "Output: $OUT"
  log "──────────────────────────────────────────────"

  if [[ "$MODE" == "pan" ]]; then
    ENV_VOL=0.11
    ENV_RATIO=1.18
    ENV_ATTACK=420
    ENV_RELEASE=1250
    ENV_THR=0.18
    SUR_VOL=0.65
    DELAY_L=10
    DELAY_R=14
    APH_SPEED=0.28
    APH_DELAY=2.2
    HP_S=160
    LP_S=6200
    XFEED=0.02
    SUR_TRIM_DB=0.2
  else
    ENV_VOL=0.17
    ENV_RATIO=1.38
    ENV_ATTACK=220
    ENV_RELEASE=780
    ENV_THR=0.16
    SUR_VOL=0.70
    DELAY_L=12
    DELAY_R=16
    APH_SPEED=0.32
    APH_DELAY=2.3
    HP_S=160
    LP_S=6200
    XFEED=0.02
    SUR_TRIM_DB=0.3
  fi

  SUR_TRIM="$(db2lin "$SUR_TRIM_DB")"

  # Heredoc robusto: evita read -d '' che su MINGW può fallire con rc=1
  FILTER="$(cat <<EOF
[0:${aidx}]aresample=48000,asplit=4[aLR][aC][aLFE][aS];

[aLR]asplit=2[aLRf][aLRenv];

[aLRf]pan=stereo|c0=1.0*c0+${XFEED}*c1|c1=1.0*c1+${XFEED}*c0,
       channelsplit=channel_layout=stereo[FL][FR];

[aLRenv]pan=mono|c0=0.5*c0+0.5*c1,
        lowpass=300,
        compand=attacks=0.45:decays=0.90:points=-60/-60|-32/-23|0/-12,
        volume=${ENV_VOL}[env];

[aC]pan=mono|c0=0.5*c0+0.5*c1,
    highpass=100,lowpass=7500,volume=1.08[FC];

[aLFE]pan=mono|c0=0.5*c0+0.5*c1,
      lowpass=140,volume=1.50[LFE];

[aS]highpass=f=${HP_S},lowpass=f=${LP_S},asplit=2[sL0][sR0];

[sL0]pan=mono|c0=0.75*c0-0.75*c1,
      aphaser=speed=${APH_SPEED}:delay=${APH_DELAY},
      adelay=${DELAY_L}|${DELAY_L},
      volume=${SUR_VOL}[sL1];

[sR0]pan=mono|c0=0.75*c1-0.75*c0,
      aphaser=speed=${APH_SPEED}:delay=${APH_DELAY},
      adelay=${DELAY_R}|${DELAY_R},
      volume=${SUR_VOL}[sR1];

[sL1][env]sidechaincompress=mode=upward:threshold=${ENV_THR}:ratio=${ENV_RATIO}:attack=${ENV_ATTACK}:release=${ENV_RELEASE}[sL2];
[sR1][env]sidechaincompress=mode=upward:threshold=${ENV_THR}:ratio=${ENV_RATIO}:attack=${ENV_ATTACK}:release=${ENV_RELEASE}[sR2];

[sL2]volume=${SUR_TRIM}[SL];
[sR2]volume=${SUR_TRIM}[SR];

[FL][FR][FC][LFE][SL][SR]join=inputs=6:channel_layout=5.1[aout]
EOF
)"

  ffmpeg -hide_banner -avoid_negative_ts 1 -loglevel warning -stats -y \
    -i "$IN" \
    -map 0:v? -map 0:s? -map_metadata 0 -map_chapters 0 \
    -filter_complex "$FILTER" -map "[aout]" \
    -c:a "$CODEC" -b:a "$BITRATE" \
    -c:v copy \
    "$OUT"

  log "✅ OK: $OUT"
done

log ""
log "🎬 Elaborazione completata!"

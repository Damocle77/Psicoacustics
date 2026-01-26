#!/usr/bin/env bash
# stereo251_psico_enhanced.sh — Stereo → 5.1 MIGLIORATO
# USO: ./stereo251_psico_enhanced.sh pan|surround|cinema [bitrate] file1.mkv [file2.mkv ...]
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
  ./stereo251_psico_enhanced.sh <mode> [bitrate] <file1.mkv> [file2.mkv ...]

MODALITÀ:
  pan      - Distribuzione semplice (compatibilità massima)
  surround - Upmix psicoacustico avanzato (bilanciato)
  cinema   - Massima spazialità e immersione (film/concerti)

ESEMPI:
  ./stereo251_psico_enhanced.sh surround 448k "episodio.mkv"
  ./stereo251_psico_enhanced.sh cinema 640k "film.mkv"
  ./stereo251_psico_enhanced.sh pan "episodio.mkv"  (bitrate a prompt)

MIGLIORAMENTI:
✓ LFE ottimizzato (80Hz invece di 120Hz)
✓ Crossfeed realistico (0.05 invece di 0.10)
✓ Surround con decorrelazione avanzata
✓ Center con presenza vocale migliorata
✓ Delay calcolati per massima spazialità
✓ Modalità CINEMA per contenuti cinematografici

NOTE:
- Bitrate consigliato: 448k (serie TV), 640k (film), 768k+ (musica)
- Output: <nome>_5.1_<mode>.mkv
EOF
}

[[ $# -ge 2 ]] || { usage; exit 2; }

MODE="${1,,}"; shift
case "$MODE" in
  pan|surround|cinema) ;;
  *) log "❌ Mode non valido: '$MODE' (usa pan|surround|cinema)"; usage; exit 2 ;;
esac

DEFAULT_BR="448k"
BITRATE="$DEFAULT_BR"

# bitrate opzionale
if [[ $# -ge 2 ]]; then
  if [[ "${1:-}" =~ ^[0-9]+k$ ]]; then
    BITRATE="$1"; shift
  elif [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    BITRATE="${1}k"; shift
  fi
fi

# se non passato, chiedi a prompt
if [[ "$BITRATE" == "$DEFAULT_BR" ]]; then
  read -r -p "Bitrate audio E-AC3? [${DEFAULT_BR}] " ans || true
  ans="${ans:-$DEFAULT_BR}"
  [[ "$ans" =~ ^[0-9]+$ ]] && ans="${ans}k"
  BITRATE="$ans"
fi

# valida bitrate
if [[ ! "$BITRATE" =~ ^[0-9]+k$ && ! "$BITRATE" =~ ^[0-9]+M$ ]]; then
  log "❌ Bitrate non valido: '$BITRATE' (es: 448k, 640k, 768k, 1M)"
  exit 2
fi

pick_audio_stream() {
  local in="$1"
  local best="-1"
  local best_2ch="-1"

  while IFS='|' read -r idx ch lang; do
    [[ -n "$idx" ]] || continue
    lang="${lang,,}"
    if [[ "$ch" == "2" ]]; then
      if [[ "$lang" == "ita" || "$lang" == "it" ]]; then
        best="$idx"; break
      fi
      [[ "$best_2ch" == "-1" ]] && best_2ch="$idx"
    fi
  done < <(
    ffprobe -v error -select_streams a \
      -show_entries stream=index,channels:stream_tags=language \
      -of default=nw=1:nk=1 "$in" \
    | awk 'BEGIN{idx="";ch="";lang=""}
           NR%3==1{idx=$0}
           NR%3==2{ch=$0}
           NR%3==0{lang=$0; print idx "|" ch "|" lang }'
  )

  if [[ "$best" != "-1" ]]; then echo "$best"
  elif [[ "$best_2ch" != "-1" ]]; then echo "$best_2ch"
  else echo "0"
  fi
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
  log "Audio:  a:$aidx (stereo selezionato)"
  log "Bitrate:$BITRATE"
  log "Output: $OUT"
  log "──────────────────────────────────────────────"

  if [[ "$MODE" == "pan" ]]; then
    # MODALITÀ PAN - Semplice ma migliorata
    read -r -d '' FILTER <<'EOF' || true
[0:a]aresample=48000,asplit=3[aLR][aC][aS];
[aLR]channelsplit=channel_layout=stereo[FL][FR];
[aC]pan=mono|c0=0.5*c0+0.5*c1,highpass=f=90,lowpass=f=8000[FC];
[aC]pan=mono|c0=0.5*c0+0.5*c1,lowpass=f=80[LFE];
[aS]asplit=2[sL][sR];
[sL]pan=mono|c0=0.5*c0-0.5*c1,highpass=f=180[SL];
[sR]pan=mono|c0=0.5*c1-0.5*c0,highpass=f=180[SR];
[FL][FR][FC][LFE][SL][SR]join=inputs=6:channel_layout=5.1[aout]
EOF

  elif [[ "$MODE" == "surround" ]]; then
    # MODALITÀ SURROUND - Bilanciata e psicoacustica
    read -r -d '' FILTER <<'EOF' || true
[0:a]aresample=48000,asplit=4[aLR][aC][aLFE][aS];
[aLR]pan=stereo|c0=1.00*c0+0.05*c1|c1=1.00*c1+0.05*c0,channelsplit=channel_layout=stereo[FL][FR];
[aC]pan=mono|c0=0.5*c0+0.5*c1,highpass=f=100,lowpass=f=7500,volume=1.05[FC];
[aLFE]pan=mono|c0=0.5*c0+0.5*c1,lowpass=f=80,volume=1.3[LFE];
[aS]highpass=f=250,lowpass=f=6500,asplit=2[sL][sR];
[sL]pan=mono|c0=0.70*c0-0.70*c1,aphaser=speed=0.5:delay=2.0,adelay=15|15,volume=0.75[SL];
[sR]pan=mono|c0=0.70*c1-0.70*c0,aphaser=speed=0.5:delay=2.0,adelay=15|15,volume=0.75[SR];
[FL][FR][FC][LFE][SL][SR]join=inputs=6:channel_layout=5.1[aout]
EOF

  else  # cinema
    # MODALITÀ CINEMA - Massima spazialità
    read -r -d '' FILTER <<'EOF' || true
[0:a]aresample=48000,asplit=4[aLR][aC][aLFE][aS];
[aLR]pan=stereo|c0=1.00*c0+0.03*c1|c1=1.00*c1+0.03*c0,channelsplit=channel_layout=stereo[FL][FR];
[aC]pan=mono|c0=0.5*c0+0.5*c1,highpass=f=110,lowpass=f=7000,volume=1.1,compand=attacks=0.1:decays=0.3:points=-40/-40|-20/-15|-10/-10|0/-7[FC];
[aLFE]pan=mono|c0=0.5*c0+0.5*c1,lowpass=f=80,volume=1.5[LFE];
[aS]highpass=f=280,lowpass=f=6000,asplit=2[sL0][sR0];
[sL0]pan=mono|c0=0.75*c0-0.75*c1,aphaser=speed=0.4:delay=2.5,chorus=0.5:0.9:50:0.4:0.25:2,adelay=20|20,volume=0.7[SL];
[sR0]pan=mono|c0=0.75*c1-0.75*c0,aphaser=speed=0.4:delay=2.5,chorus=0.5:0.9:55:0.4:0.25:2,adelay=20|20,volume=0.7[SR];
[FL][FR][FC][LFE][SL][SR]join=inputs=6:channel_layout=5.1[aout]
EOF
  fi

  ffmpeg -hide_banner -avoid_negative_ts 1 -loglevel warning -stats -y \
    -i "$IN" \
    -map 0:v? -map 0:s? -map_metadata 0 -map_chapters 0 \
    -filter_complex "$FILTER" -map "[aout]" \
    -c:a eac3 -b:a "$BITRATE" \
    -c:v copy \
    "$OUT"

  log "✅ OK: $OUT"
done

log ""
log "🎬 Elaborazione completata!"

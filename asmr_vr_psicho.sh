#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────────────────────
# VR Close Presence 40–80cm — Stereo → pseudo-binaurale frontale naturale (2026 rev)
#
# Miglioramenti rispetto alla v1:
# • Loudnorm per volume consistente (ASMR-friendly)
# • Crossfeed + stereotools più aggressivi per "davanti al viso"
# • EQ ottimizzata per vicinanza / sussurri intimi
# • Piccolo ITD + IID asimmetrico
# • Pseudo-LFO width (effetto respirante lento) opzionale con chorus + pan mod
# • Solo un aresample finale
# • Opzione -l per attivare LFO-like
#
# Uso:
#   ./asmr_vr_whisper_close_v2.sh file1.mp4 file2.mkv ...
#   ./asmr_vr_whisper_close_v2.sh -o OUTDIR *.mp4
#   ./asmr_vr_whisper_close_v2.sh -k -l input.mkv
# ────────────────────────────────────────────────────────────────────────────────

OUTDIR=""
KEEP_ORIG=0
OVERWRITE=0
USE_LFO=0

die()  { echo "ERRORE: $*" >&2; exit 1; }
log()  { echo "• $*" >&2; }
warn() { echo "⚠ $*" >&2; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Comando mancante: $1"; }
need_cmd ffmpeg
need_cmd ffprobe

show_help() {
  cat >&2 <<'EOF'
VR Close Presence 40–80cm — Stereo → pseudo-binaurale frontale naturale (rev 2026)

Uso:
  asmr_vr_whisper_close_v2.sh [opzioni] <file1> [file2 ...]

Opzioni:
  -o <dir>   Cartella di output (default: stessa del file)
  -k         Mantieni traccia audio originale come seconda traccia
  -f         Forza overwrite
  -l         Attiva pseudo-LFO width (effetto "respirante" lento)
  -h         Questo help

Note:
  • Progettato per sorgenti stereo
  • Ottimizzato per cuffie / VR / ascolto ravvicinato ASMR / intimate
  • Pseudo-LFO: simula modulazione lenta della larghezza stereo (ipnotico)
EOF
}

# ── Parse args ────────────────────────────────────────────────────────────────
while getopts ":o:kfhl" opt; do
  case "$opt" in
    o) OUTDIR="$OPTARG" ;;
    k) KEEP_ORIG=1 ;;
    f) OVERWRITE=1 ;;
    l) USE_LFO=1 ;;
    h) show_help; exit 0 ;;
    \?) die "Opzione non valida: -$OPTARG (usa -h)" ;;
    :) die "Opzione -$OPTARG richiede argomento (usa -h)" ;;
  esac
done
shift $((OPTIND-1))

[[ $# -ge 1 ]] || { show_help; exit 1; }

# ── ffprobe per trovare la traccia audio migliore ─────────────────────────────
probe_audio() {
  local f="$1" line best=""
  mapfile -t _A_LINES < <(
    ffprobe -v error -select_streams a \
      -show_entries stream=index,channels,channel_layout:stream_disposition=default:stream_tags=language \
      -of csv=p=0 "$f" 2>/dev/null || true
  )

  [[ ${#_A_LINES[@]} -gt 0 ]] || return 1

  for line in "${_A_LINES[@]}"; do
    IFS=',' read -r idx ch layout def lang <<<"$line"
  # priorità: stereo default
    [[ "$ch" -eq 2 && "$def" == "1" ]] && { best="$line"; break; }
  # fallback: stereo non-default
    [[ "$ch" -eq 2 && -z "$best" ]] && best="$line"
  done
  
  [[ -z "$best" ]] && return 1
  IFS=',' read -r AIDX ACH ALAYOUT ADEF ALANG <<<"$best"
  ACH="${ACH:-0}"
  ALAYOUT="${ALAYOUT:-unknown}"
  ALANG="${ALANG:-}"
}

# ── Filtro audio principale ───────────────────────────────────────────────────
BASE_FILTER=$(cat <<'EOF'
highpass=f=80:order=2,
lowpass=f=14000,
loudnorm=I=-18:TP=-1.5:LRA=11,
aresample=48000,
crossfeed=strength=0.65:range=0.55:level_in=0.92:level_out=0.92,
stereotools=balance_in=0:slev=0.68:mlev=1.05:phase=0,
pan=stereo|c0=1.12*c0 + 0.12*c1|c1=0.12*c0 + 1.12*c1,
adelay=0|280,
equalizer=f=120:t=q:w=1.4:g=1.4,
equalizer=f=280:t=q:w=1.2:g=-0.9,
equalizer=f=3200:t=q:w=1.8:g=1.1,
equalizer=f=6200:t=q:w=2.2:g=-1.5,
equalizer=f=9500:t=q:w=1.5:g=1.0,
alimiter=limit=0.97:attack=3:release=50:asc=1
EOF
)

# ── Pseudo-LFO width (respirante lento) ───────────────────────────────────────
# chorus lento + leggera modulazione pan per simulare width pulsante
# Frequenza ~0.12–0.18 Hz → ciclo ogni 5–8 secondi circa
LFO_PART=$(cat <<'EOF'
chorus=0.7:0.9:45|60:0.35|0.28:0.22|0.38:decay=0.6,
pan=stereo|c0=1.0*c0 + 0.08*c1*sin(2*PI*0.14*t)|c1=1.0*c1 + 0.08*c0*sin(2*PI*0.14*t + PI/2)
EOF
)

# ── Main loop ─────────────────────────────────────────────────────────────────
for IN in "$@"; do
  [[ -f "$IN" ]] || { warn "File non trovato: $IN"; continue; }

  base="$(basename "$IN")"
  dir="$(dirname "$IN")"
  name="${base%.*}"

  OUT="${name}_VRClose40-80cm.mkv"
  [[ -n "$OUTDIR" ]] && { mkdir -p "$OUTDIR"; OUT="$OUTDIR/$OUT"; } || OUT="$dir/$OUT"

  [[ -f "$OUT" && "$OVERWRITE" -eq 0 ]] && {
    warn "Output già esistente, salto: $OUT (usa -f per forzare)"
    continue
  }

  probe_audio "$IN" || { warn "Nessuna traccia audio valida, salto"; continue; }

  log "Input:  $IN"
  log "Audio:  stream #$AIDX • ${ACH}ch • layout=$ALAYOUT${ALANG:+ • lang=$ALANG}"
  log "Output: $OUT"

  [[ "$ACH" -ne 2 ]] && {
    warn "Audio non stereo (${ACH}ch). Preset progettato per stereo. Salto."
    continue
  }

  TMP="${OUT%.mkv}.part.$$.mkv"

  FILTER="$BASE_FILTER"
  [[ "$USE_LFO" -eq 1 ]] && FILTER="$FILTER,$LFO_PART"

  cmd=(
    ffmpeg
    -hide_banner
    -fflags +genpts
    -i "$IN"
    -map 0:v?
    -map 0:"$AIDX"
    -map 0:s?
    -c:v copy
    -c:s copy
    -af "$FILTER"
    -c:a aac -b:a 256k -ac 2
  )

  if [[ "$KEEP_ORIG" -eq 1 ]]; then
    cmd+=(
      -map 0:"$AIDX"?          # seconda traccia = originale
      -c:a:1 copy
      -metadata:s:a:1 title="Original Stereo (unedited)"
      -disposition:a:1 0
    )
    [[ -n "$ALANG" && "${ALANG,,}" != "und" ]] && cmd+=(-metadata:s:a:1 language="$ALANG")
  fi

  [[ -n "$ALANG" && "${ALANG,,}" != "und" ]] && cmd+=(-metadata:s:a:0 language="$ALANG")
  cmd+=(
    -metadata:s:a:0 title="VR Close Presence 40–80cm (2026 tuned)"
    -disposition:a:0 default
    -y "$TMP"
  )

  log "Filtro applicato:${USE_LFO:+ con pseudo-LFO width}"
  if "${cmd[@]}"; then
      mv -f "$TMP" "$OUT"
    else
      warn "ffmpeg fallito, file temporaneo lasciato per debug: $TMP"
    continue
  fi

  log "OK: $OUT"
  echo >&2
done

log "Fine elaborazione."
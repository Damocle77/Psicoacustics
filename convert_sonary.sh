#!/usr/bin/env bash
set -euo pipefail

# ╭──────────────────────────────────────────────────────────────────────────────╮
# │ convert_sonary.sh                                                            │
# │                                                                              │
# │ • Converte una traccia 5.1 (AC3/EAC3/DTS/TrueHD...) in AC3/EAC3              │
# │ • Applica DSP sui surround (modalità Sonar o Clean)                          │
# │ • Applica EQ Voce universale sul canale Centrale (FC)                        │
# │ • Mantiene video e sottotitoli in copia                                      │
# │ • Compatibile con Yamaha RX-V4A in modalità STRAIGHT                         │
# ╰──────────────────────────────────────────────────────────────────────────────╯
#
# NOTE:
#   - La EQ Voce (FC) è sempre attiva per garantire uniformità timbrica.
#   - I surround variano in base alla modalità: Sonar (upfiring) o Clean (lineare).
#   - L'LFE non viene alterato.
#   - FL/FR restano neutri.
#
# USO:
#   ./convert_sonary.sh <ac3|eac3> <si|no> [file] [bitrate] [sonar|clean]
#
# ARGOMENTI:
#   1) Codec output: ac3 | eac3
#   2) Mantieni traccia originale: si | no
#   3) File singolo o "" per elaborazione batch
#   4) Bitrate es: 640k, 768k, 896k (default: 640k AC3 / 768k EAC3)
#   5) Modalità surround:
#        sonar → Surround con Sonary upfiring
#        clean → Surround con boost e high-shelf
# ────────────────────────────────────────────────────────────────────────────────


# ────────────────────────────────────────────────────────────────────────────────
# Colorazione messaggi terminale
# ────────────────────────────────────────────────────────────────────────────────
C_INFO="\033[0;36m[INFO]\033[0m"
C_WARN="\033[0;33m[WARNING]\033[0m"
C_ERR="\033[0;31m[ERROR]\033[0m"
C_OK="\033[0;32m[OK]\033[0m"

info(){ echo -e "${C_INFO} $*"; }
warn(){ echo -e "${C_WARN} $*"; }
err(){  echo -e "${C_ERR}  $*"; }
ok(){   echo -e "${C_OK}  $*"; }


# ────────────────────────────────────────────────────────────────────────────────
# Help
# ────────────────────────────────────────────────────────────────────────────────
show_help(){ cat <<'USAGE'
───────────────────────────────────────────────────────────────────────────────
UTILIZZO:
  ./convert_sonary.sh <ac3|eac3> <si|no> [file] [bitrate] [sonar|clean]

DSP:
  • EQ Voce UNIVERSALE applicata al canale Centrale (FC)
  • Sonar: DSP Surround Sonary upfiring su SL/SR
  • Clean: Surround "puliti" con leggero boost + limiter

ESEMPI:
  ./convert_sonary.sh ac3 no "film.mkv" 640k sonar
  ./convert_sonary.sh eac3 si "" 768k clean
───────────────────────────────────────────────────────────────────────────────
USAGE
}


# ────────────────────────────────────────────────────────────────────────────────
# Parsing argomenti
# ────────────────────────────────────────────────────────────────────────────────
OUT_CODEC="${1:-}"
KEEP_ORIG="${2:-}"
INPUT_FILE="${3:-}"
BITRATE="${4:-}"
SUR_MODE="${5:-sonar}"

[[ $# -lt 2 ]] && { show_help; exit 1; }

case "$OUT_CODEC" in
  ac3|eac3) ;;
  *) err "Codec non valido"; exit 1 ;;
esac

[[ "$KEEP_ORIG" =~ ^(si|no)$ ]] || { err "Parametro 2 deve essere si|no"; exit 1; }

# Bitrate di default
if [[ -z "$BITRATE" ]]; then
  if [[ "$OUT_CODEC" = "ac3" ]]; then
    BITRATE="640k"
  else
    BITRATE="768k"
  fi
fi

[[ "$BITRATE" =~ ^[0-9]+k$ ]] || { err "Bitrate non valido"; exit 1; }

[[ "$SUR_MODE" =~ ^(sonar|clean)$ ]] || { err "Modalità surround invalida"; exit 1; }

info "Codec output:  $OUT_CODEC"
info "Mantieni orig: $KEEP_ORIG"
info "Bitrate:       $BITRATE"
info "Surround mode: $SUR_MODE"


# ────────────────────────────────────────────────────────────────────────────────
# Raccolta file
# ────────────────────────────────────────────────────────────────────────────────
declare -a FILES=()

if [[ -n "$INPUT_FILE" ]]; then
  [[ -f "$INPUT_FILE" ]] || { err "File non esistente"; exit 1; }
  FILES+=("$INPUT_FILE")
else
  shopt -s nullglob
  FILES+=( *.mkv *.MKV *.mp4 *.MP4 *.m2ts *.M2TS )
  shopt -u nullglob
fi

[[ ${#FILES[@]} -gt 0 ]] || { err "Nessun file trovato"; exit 1; }

info "Trovati ${#FILES[@]} file da processare."
info "EQ Voce universale attiva. Surround = $SUR_MODE"


# ────────────────────────────────────────────────────────────────────────────────
# Blocchi DSP per surround (clean-sonar)
# ────────────────────────────────────────────────────────────────────────────────

# SONAR → DSP upfiring + ritardi + mix multilivello + limiter
read -r -d '' SUR_FILTERS_SONAR <<'EOF' || true
[SL]asplit=3[SLm][SLv_in][SLlate_in];
[SLv_in]adelay=34,highpass=f=1600,equalizer=f=6500:t=q:w=1.2:g=3.5,equalizer=f=11000:t=q:w=1.0:g=-1.0[SLv];
[SLlate_in]adelay=78,lowpass=f=1500,volume=0.79[SLlate];
[SLm][SLv][SLlate]amix=inputs=3:weights='1 0.70 0.40':normalize=0,alimiter=limit=0.99,volume=1.45[SL_out];
[SR]asplit=3[SRm][SRv_in][SRlate_in];
[SRv_in]adelay=34,highpass=f=1600,equalizer=f=6500:t=q:w=1.2:g=3.5,equalizer=f=11000:t=q:w=1.0:g=-1.0[SRv];
[SRlate_in]adelay=78,lowpass=f=1500,volume=0.79[SRlate];
[SRm][SRv][SRlate]amix=inputs=3:weights='1 0.70 0.40':normalize=0,alimiter=limit=0.99,volume=1.45[SR_out];
EOF

# CLEAN → high-shelf + widening + Boost + limiter
read -r -d '' SUR_FILTERS_CLEAN <<'EOF' || true
[SL]adelay=3,highshelf=f=3500:g=0.8:t=q:w=0.8,volume=1.26,alimiter=limit=0.97[SL_out];
[SR]adelay=0.003,highshelf=f=3500:g=0.8:t=q:w=0.8,volume=1.26,alimiter=limit=0.97[SR_out];
EOF


# ────────────────────────────────────────────────────────────────────────────────
# EQ Voce UNIVERSALE (FC) - VERSIONE CORRETTA SENZA volume=
# ────────────────────────────────────────────────────────────────────────────────
read -r -d '' VOICE_EQ_STANDARD <<'EOF' || true
[FC]equalizer=f=1000:t=q:w=1.0:g=2.5,equalizer=f=2500:t=q:w=1.0:g=3.5,equalizer=f=6300:t=q:w=1.0:g=1.0[FCv];
EOF


# ────────────────────────────────────────────────────────────────────────────────
# Ciclo elaborazione file
# ────────────────────────────────────────────────────────────────────────────────
for CUR_FILE in "${FILES[@]}"; do
  echo "───────────────────────────────────────────────────────────────────────────────"
  info "Input: $CUR_FILE"

  BASENAME="${CUR_FILE%.*}"
  SUF_CODEC="${OUT_CODEC^^}"

  if [[ "$SUR_MODE" = "sonar" ]]; then
    OUT_FILE="${BASENAME}_${SUF_CODEC}_Sonar.mkv"
  else
    OUT_FILE="${BASENAME}_${SUF_CODEC}_Clean.mkv"
  fi

  info "Output: $OUT_FILE"

  if [[ -f "$OUT_FILE" ]]; then
    warn "Il file esiste già. Sovrascrivere? [s/N] "
    read -r ans
    [[ "$ans" =~ ^[sS]$ ]] || continue
  fi

  # Selezione blocco surround DSP
  if [[ "$SUR_MODE" = "sonar" ]]; then
    SUR_BLOCK="$SUR_FILTERS_SONAR"
  else
    SUR_BLOCK="$SUR_FILTERS_CLEAN"
  fi

  # EQ Voce sempre attiva
  VOICE_BLOCK="$VOICE_EQ_STANDARD"

FILTER_COMPLEX="
[0:a:0]aformat=channel_layouts=5.1:sample_rates=48000:sample_fmts=fltp[base];
[base]channelsplit=channel_layout=5.1[FL][FR][FC][LFE][SL][SR];
${VOICE_BLOCK}
[FL]aformat=channel_layouts=FL[FLf];
[FR]aformat=channel_layouts=FR[FRf];
[FCv]aformat=channel_layouts=FC[FCf];
[LFE]aformat=channel_layouts=LFE[LFEf];
${SUR_BLOCK}
[SL_out]aformat=channel_layouts=SL[SLf];
[SR_out]aformat=channel_layouts=SR[SRf];
[FLf][FRf][FCf][LFEf][SLf][SRf]amerge=inputs=6,channelmap=channel_layout=5.1,volume=0.94,alimiter=limit=0.97,aresample=resampler=soxr:precision=28[aout]
"

  # Comando finale FFmpeg
  CMD=(ffmpeg -y -hide_banner -nostdin -stats -loglevel warning \
       -i "$CUR_FILE" \
       -filter_complex "$FILTER_COMPLEX" \
       -map 0:v:0 -c:v copy \
       -map "[aout]" -c:a:0 "$OUT_CODEC" -b:a:0 "$BITRATE" -ar:a:0 48000 -ac:a:0 6 \
       -metadata:s:a:0 title="${SUF_CODEC} ${SUR_MODE^} 5.1" \
       -disposition:a:0 default)

  # Copia sottotitoli
  if ffprobe -v quiet -select_streams s -show_entries stream=index -of csv=p=0 "$CUR_FILE" | grep -q .; then
    CMD+=(-map 0:s -c:s copy)
  fi

  # Mantieni traccia originale
  if [[ "$KEEP_ORIG" = "si" ]]; then
    ORIG_TITLE=$(ffprobe -v quiet -select_streams a:0 -show_entries stream_tags=title -of csv=p=0 "$CUR_FILE" || true)
    [[ -z "$ORIG_TITLE" ]] && ORIG_TITLE="Original Audio"
    CMD+=(-map 0:a:0 -c:a:1 copy -metadata:s:a:1 title="$ORIG_TITLE" -disposition:a:1 0)
  fi

  CMD+=("$OUT_FILE")

  info "Esecuzione FFmpeg…"
  echo "───────────────────────────────────────────────────────────────────────────────"

  if ! "${CMD[@]}"; then
    err "Errore durante l'elaborazione"
    continue
  fi

  ok "Completato: $OUT_FILE"
done
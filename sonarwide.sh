#!/usr/bin/env bash
set -euo pipefail

# ╭──────────────────────────────────────────────────────────────────────────────╮
# │ sonarwide.sh                                                                 │
# │                                                                              │
# │ • Converte una traccia 5.1 (AC3/EAC3/DTS/TrueHD...) in AC3/EAC3              │
# │ • Applica DSP sui surround (modalità Sonar o Wide)                           │
# │ • Applica EQ Voce Sartoriale sul canale Centrale (FC)                        │
# │ • Mantiene video e sottotitoli in copia                                      │
# │ • Compatibile con qualsiasi AVR in modalità STRAIGHT/pure/direct             │
# ╰──────────────────────────────────────────────────────────────────────────────╯
#
# NOTE:
#   - La EQ Voce (FC) è sempre attiva per garantire uniformità timbrica.
#   - I surround variano in base alla modalità: Sonar (upfiring) o Wide (lineare).
#   - L'LFE non viene alterato.
#   - FL/FR restano neutri.
#
# USO:
#   ./sonarwide.sh <ac3|eac3> <si|no> [file] [bitrate] [sonar|wide]
#
# ARGOMENTI:
#   1) Codec output: ac3 | eac3
#   2) Mantieni traccia originale: si | no
#   3) File singolo o "" per elaborazione batch
#   4) Bitrate es: 256k, 320k, 384k, 448k, 512k, 640k, 768k (default: 640k AC3 / 768k EAC3)
#   5) Modalità surround:
#        sonar → Surround con upfiring psicoacustico (virtual 5.1.2)
#         wide → Surround widening psicoacustico (virtual 7.1)
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
  ./convert_sonary.sh <ac3|eac3> <si|no> [file] [bitrate] [sonar|wide]

DSP:
  • EQ Voce Sartoriale applicata al canale Centrale (FC)
  • Sonar: Surround upfiring (virtual 5.1.2) 
  • Wide: Surround widening (virtual 7.1) 

BITRATE:
  • 256k, 320k, 384k, 448k, 512k, 640k, 768k (default: 640k AC3 / 768k EAC3)

ESEMPI:
  ./sonarwide.sh ac3 no "film.mkv" 640k sonar
  ./sonarwide.sh eac3 si "" 384k wide
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

[[ "$SUR_MODE" =~ ^(sonar|wide)$ ]] || { err "Modalità surround invalida"; exit 1; }

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
info "EQ Voce Sartoriale attiva. Surround = $SUR_MODE"


# ────────────────────────────────────────────────────────────────────────────────
# Blocchi DSP per surround (clean-sonar)
# ────────────────────────────────────────────────────────────────────────────────

# SONAR → upfiring + ritardi + mix multilivello + limiter (SAFE)
read -r -d '' SUR_FILTERS_SONAR <<'EOF' || true
[SL]asplit=4[SLd_in][SLp_in][SLh_in][SLlate_in];
[SLd_in]adelay=0,volume=0.95[SLd];
[SLp_in]adelay=14,highpass=f=1500,equalizer=f=6500:t=q:w=1.2:g=2.0,equalizer=f=11000:t=q:w=1.0:g=-1.2,volume=1.00[SLp];
[SLh_in]adelay=28,highpass=f=2500,lowpass=f=14000,allpass=f=900:t=q:w=0.70,allpass=f=2200:t=q:w=0.70,equalizer=f=8000:t=q:w=3.0:g=-3.0,equalizer=f=11000:t=q:w=1.2:g=1.0,volume=0.60[SLh];
[SLlate_in]adelay=85,lowpass=f=1500,volume=0.65[SLlate];
[SLd][SLp][SLh][SLlate]amix=inputs=4:weights='1.10 0.85 0.80 0.55':normalize=0,volume=1.35,alimiter=limit=0.99[SL_out];
[SR]asplit=4[SRd_in][SRp_in][SRh_in][SRlate_in];
[SRd_in]adelay=0,volume=0.95[SRd];
[SRp_in]adelay=14,highpass=f=1500,equalizer=f=6500:t=q:w=1.2:g=2.0,equalizer=f=11000:t=q:w=1.0:g=-1.2,volume=1.00[SRp];
[SRh_in]adelay=28,highpass=f=2500,lowpass=f=14000,allpass=f=1050:t=q:w=0.70,allpass=f=2400:t=q:w=0.70,equalizer=f=8000:t=q:w=3.0:g=-3.0,equalizer=f=11000:t=q:w=1.2:g=1.0,volume=0.60[SRh];
[SRlate_in]adelay=85,lowpass=f=1500,volume=0.65[SRlate];
[SRd][SRp][SRh][SRlate]amix=inputs=4:weights='1.10 0.85 0.80 0.55':normalize=0,volume=1.35,alimiter=limit=0.99[SR_out];
EOF

# CLEAN → widening + early + diffuse + limiter (SAFE)
read -r -d '' SUR_FILTERS_WIDE <<'EOF' || true
[SL]asplit=3[SLd_in][SLe_in][SLx_in];
[SLd_in]adelay=0,volume=1.00[SLd];
[SLe_in]adelay=9,highpass=f=300,lowpass=f=7000,allpass=f=1200:t=q:w=0.65,volume=0.42[SLe];
[SLx_in]adelay=22,highpass=f=600,lowpass=f=5000,allpass=f=700:t=q:w=0.70,allpass=f=2600:t=q:w=0.70,volume=0.17[SLx];
[SLd][SLe][SLx]amix=inputs=3:weights='1.00 0.90 0.80':normalize=0,lowshelf=f=180:g=0.6:t=q:w=0.7,highshelf=f=3500:g=0.1:t=q:w=0.8,volume=1.30,alimiter=limit=0.99[SL_out];
[SR]asplit=3[SRd_in][SRe_in][SRx_in];
[SRd_in]adelay=0,volume=1.00[SRd];
[SRe_in]adelay=10,highpass=f=300,lowpass=f=7000,allpass=f=1350:t=q:w=0.65,volume=0.42[SRe];
[SRx_in]adelay=24,highpass=f=600,lowpass=f=5000,allpass=f=820:t=q:w=0.70,allpass=f=2400:t=q:w=0.70,volume=0.17[SRx];
[SRd][SRe][SRx]amix=inputs=3:weights='1.00 0.90 0.80':normalize=0,lowshelf=f=180:g=0.6:t=q:w=0.7,highshelf=f=3500:g=0.1:t=q:w=0.8,volume=1.30,alimiter=limit=0.99[SR_out];
EOF


# ────────────────────────────────────────────────────────────────────────────────
# EQ Voce sartoriale (FC)
# ────────────────────────────────────────────────────────────────────────────────
read -r -d '' VOICE_EQ_STANDARD <<'EOF' || true
[FC]equalizer=f=350:t=q:w=1.0:g=-1.2,equalizer=f=1000:t=q:w=1.0:g=2.2,equalizer=f=2500:t=q:w=1.0:g=2.6,equalizer=f=7200:t=q:w=1.1:g=-0.6,volume=0.9dB,alimiter=limit=0.99[FCv];
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
    OUT_FILE="${BASENAME}_${SUF_CODEC}_Wide.mkv"

  fi

  info "Output: $OUT_FILE"

  if [[ -f "$OUT_FILE" ]]; then
    printf "%b" "${C_WARN} Il file esiste già. Sovrascrivere? [s/N] "
    read -r ans
    [[ "$ans" =~ ^[sS]$ ]] || continue
  fi

  # Selezione blocco surround DSP
  if [[ "$SUR_MODE" = "sonar" ]]; then
    SUR_BLOCK="$SUR_FILTERS_SONAR"
  else
    SUR_BLOCK="$SUR_FILTERS_WIDE"
  fi

  # EQ Voce sempre attiva
  VOICE_BLOCK="$VOICE_EQ_STANDARD"

FILTER_COMPLEX="
[0:a:0]aformat=channel_layouts=5.1(side):sample_rates=48000:sample_fmts=fltp[base];
[base]channelsplit=channel_layout=5.1(side)[FL][FR][FC][LFE][SL][SR];
${VOICE_BLOCK}
[FL]aformat=channel_layouts=mono[FLf];
[FR]aformat=channel_layouts=mono[FRf];
[FCv]aformat=channel_layouts=mono[FCf];
[LFE]aformat=channel_layouts=mono[LFEf];
${SUR_BLOCK}
[SL_out]aformat=channel_layouts=mono[SLf];
[SR_out]aformat=channel_layouts=mono[SRf];
[FLf][FRf][FCf][LFEf][SLf][SRf]join=inputs=6:channel_layout=5.1(side):map=0.0-FL|1.0-FR|2.0-FC|3.0-LFE|4.0-SL|5.0-SR,aformat=channel_layouts=5.1(side):sample_rates=48000:sample_fmts=fltp,aresample=resampler=soxr:precision=28[aout]
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
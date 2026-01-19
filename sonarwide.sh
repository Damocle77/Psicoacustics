#!/usr/bin/env bash
set -euo pipefail

# ╭──────────────────────────────────────────────────────────────────────────────╮
# │ sonarwide.sh Gennaio (2026)                                                  │
# │                                                                              │
# │ • Converte una traccia 5.1 in AC3/EAC3                                       │
# │ • DSP surround Sonar / Wide (psicoacustico)                                  │
# │ • EQ Voce Sartoriale sempre attiva sul Centrale (FC)                         │
# │ • Supporto hwaccel opzionale (SOLO decodifica)                               │
# │ • Mantiene video, sottotitoli e traccia originale opzionale                  │
# │                                                                              │
# │ Fisica non negoziabile:                                                      │
# │ • AC3 / E-AC3 → encoding SEMPRE CPU                                          │
# │ • hwaccel accelera solo la DECODIFICA di sorgenti pesanti                    │
# ╰──────────────────────────────────────────────────────────────────────────────╯

# ────────────────────────────────────────────────────────────────────────────────
# Colori terminale
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
# Parsing argomenti
# ────────────────────────────────────────────────────────────────────────────────
OUT_CODEC="${1:-}"
KEEP_ORIG="${2:-}"
INPUT_FILE="${3:-}"
BITRATE="${4:-}"
SUR_MODE="${5:-sonar}"
HWACCEL="${6:-none}"

[[ $# -lt 2 ]] && {
cat <<'USAGE'
──────────────────────────────────────────────────────────────────────────────────────────────
UTILIZZO:
  ./sonarwide.sh <ac3|eac3> <si|no> [file|""] [bitrate] [sonar|wide] [hwaccel]

PARAMETRI:
  1) codec      ac3 | eac3
  2) keep_orig  si  | no          (mantieni anche la traccia audio originale)
  3) file       "film.mkv" | ""   ("" = elabora tutti i file video nella cartella)
  4) bitrate    es. 448k, 640k, 768k
               • default: ac3=640k, eac3=768k
               • nota: ac3 max 640k
  5) mode       sonar | wide
               • sonar = più coerenza e “altezza” psicoacustica (dialoghi stabili, scena profonda)
               • wide  = più ampiezza e aria surround (più “cinema”, meno verticale)
  6) hwaccel    none | auto | amd | nvidia | intel | qsv | cuda | d3d11va | dxva2 | vaapi
               • accelera SOLO la DECODIFICA (l’encoding AC3/E-AC3 resta CPU)

ESEMPI (singolo file):
  ./sonarwide.sh eac3 no  "film.mkv" 768k sonar nvidia
  ./sonarwide.sh ac3  si  "film.mkv" 640k wide  amd
  ./sonarwide.sh eac3 no  "film.mkv" 448k wide  auto
  ./sonarwide.sh eac3 no  "film.mkv" ""   sonar none (bitrate default)

ESEMPI (batch cartella: file=""):
  ./sonarwide.sh eac3 no "" 448k wide  amd
  ./sonarwide.sh ac3  si "" 640k sonar none
──────────────────────────────────────────────────────────────────────────────────────────────
USAGE

exit 1
}

case "$OUT_CODEC" in ac3|eac3) ;; *) err "Codec deve essere ac3 o eac3"; exit 1;; esac
[[ "$KEEP_ORIG" =~ ^(si|no)$ ]] || { err "Parametro 2: si|no"; exit 1; }
[[ "$SUR_MODE" =~ ^(sonar|wide)$ ]] || { err "Modalità: sonar|wide"; exit 1; }

[[ -z "$BITRATE" ]] && {
  [[ "$OUT_CODEC" = "ac3" ]] && BITRATE="640k" || BITRATE="768k"
}
[[ "$BITRATE" =~ ^[0-9]+k$ ]] || { err "Bitrate non valido"; exit 1; }

# Vincolo AC3: max 640k
if [[ "$OUT_CODEC" == "ac3" ]]; then
  b="${BITRATE%k}"
  (( b <= 640 )) || { err "AC3 non supporta bitrate > 640k (richiesto: $BITRATE)"; exit 1; }
fi

# ────────────────────────────────────────────────────────────────────────────────
# Configurazione hwaccel (solo DECODIFICA)
# ────────────────────────────────────────────────────────────────────────────────
case "$HWACCEL" in
  nvidia|nvenc|cuda)
    HW_INIT="-hwaccel cuda -hwaccel_output_format cuda"
    HW_NAME="NVIDIA CUDA"
    ;;
  intel|qsv)
    HW_INIT="-hwaccel qsv -hwaccel_output_format qsv"
    HW_NAME="Intel Quick Sync"
    ;;
  amd|vcn|amf)
    HW_INIT="-hwaccel auto"
    HW_NAME="AMD (auto)"
    ;;
  vaapi)
    HW_INIT="-hwaccel vaapi"
    HW_NAME="VAAPI"
    ;;
  d3d11va)
    HW_INIT="-hwaccel d3d11va"
    HW_NAME="D3D11VA"
    ;;
  dxva2)
    HW_INIT="-hwaccel dxva2"
    HW_NAME="DXVA2"
    ;;
  auto)
    HW_INIT="-hwaccel auto"
    HW_NAME="AUTO"
    ;;
  none|"")
    HW_INIT=""
    HW_NAME="CPU"
    ;;
  *)
    warn "Hwaccel '$HWACCEL' non riconosciuto → CPU"
    HW_INIT=""
    HW_NAME="CPU"
    ;;
esac

# AMF non è un hwaccel decode affidabile in tutte le build: usa auto come scelta pragmatica
info "Codec output:   $OUT_CODEC"
info "Mantieni orig:  $KEEP_ORIG"
info "Bitrate:        $BITRATE"
info "Surround mode:  $SUR_MODE"
info "Hwaccel:        $HW_NAME (decodifica)"

# ────────────────────────────────────────────────────────────────────────────────
# Funzioni probe audio
# ────────────────────────────────────────────────────────────────────────────────
probe_audio_stream() {
  local f="$1" line best=""
  mapfile -t _A_LINES < <(ffprobe -v error -select_streams a \
    -show_entries stream=index,channels,channel_layout:stream_disposition=default:stream_tags=language \
    -of csv=p=0 "$f" 2>/dev/null || true)
  [[ ${#_A_LINES[@]} -eq 0 ]] && return 1
  for line in "${_A_LINES[@]}"; do
    IFS=',' read -r idx ch layout def lang <<<"$line"
    [[ "$def" = "1" ]] && { best="$line"; break; }
    [[ -z "$best" ]] && best="$line"
  done
  IFS=',' read -r A_STREAM_INDEX A_CHANNELS A_LAYOUT A_IS_DEFAULT A_LANG <<<"$best"
  A_LANG="${A_LANG:-}"
}

get_audio_title_by_index() {
  ffprobe -v error -select_streams a \
    -show_entries stream=index:stream_tags=title \
    -of default=nw=1 "$1" 2>/dev/null | awk -v idx="$2" '
    $0=="index="idx{f=1;next} f&&/^TAG:title=/{sub(/^TAG:title=/,"");print;exit} f&&/^index=/{exit}'
}

# ────────────────────────────────────────────────────────────────────────────────
# Raccolta file (robusta)
# ────────────────────────────────────────────────────────────────────────────────
FILES=()
if [[ -n "$INPUT_FILE" ]]; then
  [[ -f "$INPUT_FILE" ]] || { err "File '$INPUT_FILE' non esiste"; exit 1; }
  FILES+=("$INPUT_FILE")
else
  shopt -s nullglob
  FILES+=( *.mkv *.MKV *.mp4 *.MP4 *.m2ts *.M2TS )
  shopt -u nullglob
fi

(( ${#FILES[@]} == 0 )) && { err "Nessun file da elaborare"; exit 1; }

# ────────────────────────────────────────────────────────────────────────────────
# DSP – BLOCCO SURROUND SONAR
# ────────────────────────────────────────────────────────────────────────────────
read -r -d '' SUR_FILTERS_SONAR <<'EOF' || true
[SL]asplit=4[SLd_in][SLp_in][SLh_in][SLlate_in];
[SLd_in]adelay=0,volume=0.95[SLd];
[SLp_in]adelay=14,highpass=f=1500,equalizer=f=6500:t=q:w=1.2:g=2.0,equalizer=f=11000:t=q:w=1.0:g=-1.2,volume=1.00[SLp];
[SLh_in]adelay=28,highpass=f=2500,lowpass=f=14000,allpass=f=900:t=q:w=0.70,allpass=f=2200:t=q:w=0.70,equalizer=f=8000:t=q:w=3.0:g=-3.0,equalizer=f=11000:t=q:w=1.2:g=1.0,volume=0.60[SLh];
[SLlate_in]adelay=85,lowpass=f=1500,volume=0.65[SLlate];
[SLd][SLp][SLh][SLlate]amix=inputs=4:weights='1.10 0.85 0.80 0.55':normalize=0,volume=1.35[SL_out];
[SR]asplit=4[SRd_in][SRp_in][SRh_in][SRlate_in];
[SRd_in]adelay=0,volume=0.95[SRd];
[SRp_in]adelay=14,highpass=f=1500,equalizer=f=6500:t=q:w=1.2:g=2.0,equalizer=f=11000:t=q:w=1.0:g=-1.2,volume=1.00[SRp];
[SRh_in]adelay=28,highpass=f=2500,lowpass=f=14000,allpass=f=1050:t=q:w=0.70,allpass=f=2400:t=q:w=0.70,equalizer=f=8000:t=q:w=3.0:g=-3.0,equalizer=f=11000:t=q:w=1.2:g=1.0,volume=0.60[SRh];
[SRlate_in]adelay=85,lowpass=f=1500,volume=0.65[SRlate];
[SRd][SRp][SRh][SRlate]amix=inputs=4:weights='1.10 0.85 0.80 0.55':normalize=0,volume=1.35[SR_out];
EOF

# ────────────────────────────────────────────────────────────────────────────────
# DSP – BLOCCO SURROUND WIDE
# ────────────────────────────────────────────────────────────────────────────────
read -r -d '' SUR_FILTERS_WIDE <<'EOF' || true
[SL]asplit=3[SLd_in][SLe_in][SLx_in];
[SLd_in]adelay=1,volume=1.00[SLd];
[SLe_in]adelay=9,highpass=f=300,lowpass=f=7000,allpass=f=1200:t=q:w=0.65,volume=0.42[SLe];
[SLx_in]adelay=22,highpass=f=600,lowpass=f=5000,allpass=f=700:t=q:w=0.70,allpass=f=2600:t=q:w=0.70,volume=0.17[SLx];
[SLd][SLe][SLx]amix=inputs=3:weights='1.00 0.90 0.80':normalize=0,lowshelf=f=180:g=0.3:t=q:w=0.7,highshelf=f=3500:g=0.1:t=q:w=0.8,volume=1.30[SL_out];
[SR]asplit=3[SRd_in][SRe_in][SRx_in];
[SRd_in]adelay=1,volume=1.00[SRd];
[SRe_in]adelay=10,highpass=f=300,lowpass=f=7000,allpass=f=1350:t=q:w=0.65,volume=0.42[SRe];
[SRx_in]adelay=24,highpass=f=600,lowpass=f=5000,allpass=f=820:t=q:w=0.70,allpass=f=2400:t=q:w=0.70,volume=0.17[SRx];
[SRd][SRe][SRx]amix=inputs=3:weights='1.00 0.90 0.80':normalize=0,lowshelf=f=180:g=0.3:t=q:w=0.7,highshelf=f=3500:g=0.1:t=q:w=0.8,volume=1.30[SR_out];
EOF

# ────────────────────────────────────────────────────────────────────────────────
# EQ VOCE SARTORIALE (FC)
# ────────────────────────────────────────────────────────────────────────────────
read -r -d '' VOICE_EQ_BASE <<'EOF' || true
[FC]
equalizer=f=230:t=q:w=1.4:g=-1.0,
equalizer=f=350:t=q:w=1.0:g=-1.0,
equalizer=f=900:t=q:w=3.0:g=-0.5,
equalizer=f=1000:t=q:w=1.2:g=1.6,
equalizer=f=1800:t=q:w=3.0:g=0.4,
equalizer=f=2500:t=q:w=1.0:g=2.3,
equalizer=f=3200:t=q:w=1.0:g=0.35,
equalizer=f=7200:t=q:w=2.5:g=-1.0,
EOF

read -r -d '' VOICE_DELTA_SONAR <<'EOF' || true
volume=0.54dB[FCv];
EOF

read -r -d '' VOICE_DELTA_WIDE <<'EOF' || true
volume=0.58dB,equalizer=f=2500:t=q:w=1.2:g=0.25[FCv];
EOF

# ────────────────────────────────────────────────────────────────────────────────
# CICLO ELABORAZIONE
# ────────────────────────────────────────────────────────────────────────────────
for CUR_FILE in "${FILES[@]}"; do
  info "Input: $CUR_FILE"

  probe_audio_stream "$CUR_FILE" || { warn "Nessuna traccia audio valida"; continue; }
    # Detect input channel layout (side/back) + canali surround corretti
  A_LAYOUT=$(ffprobe -v error -select_streams a:${A_STREAM_INDEX} \
    -show_entries stream=channel_layout -of default=nk=1:nw=1 "$CUR_FILE" | tr -d '\r')

  case "$A_LAYOUT" in
    "5.1(side)")
      IN_LAYOUT="5.1(side)"
      SUR_L_CH="SL"; SUR_R_CH="SR"
      ;;
    "5.1"|"5.1(back)")
      IN_LAYOUT="5.1(back)"
      SUR_L_CH="BL"; SUR_R_CH="BR"
      ;;
    *)
      warn "Layout '$A_LAYOUT' non standard → assumo 5.1(side)"
      IN_LAYOUT="5.1(side)"
      SUR_L_CH="SL"; SUR_R_CH="SR"
      ;;
  esac

  if [[ "$A_CHANNELS" -ne 6 ]]; then
    warn "Non 5.1 (trovati $A_CHANNELS canali) → salto"
    continue
  fi

  BASENAME="${CUR_FILE%.*}"
  OUT_FILE="${BASENAME}_${OUT_CODEC^^}_${SUR_MODE^}.mkv"

  [[ -f "$OUT_FILE" ]] && {
    read -p "Sovrascrivere $OUT_FILE? [s/N] " ans
    [[ ! "$ans" =~ ^[sS]$ ]] && continue
  }

  if [[ "$SUR_MODE" = "sonar" ]]; then
    SUR_BLOCK="$SUR_FILTERS_SONAR"
    VOICE_BLOCK="${VOICE_EQ_BASE}${VOICE_DELTA_SONAR}"
  else
    SUR_BLOCK="$SUR_FILTERS_WIDE"
    VOICE_BLOCK="${VOICE_EQ_BASE}${VOICE_DELTA_WIDE}"
  fi

FILTER_COMPLEX="
[0:${A_STREAM_INDEX}]aformat=sample_rates=48000:sample_fmts=fltp,
pan=5.1(side)|FL=FL|FR=FR|FC=FC|LFE=LFE|SL=${SUR_L_CH}|SR=${SUR_R_CH}[base];
[base]channelsplit=channel_layout=5.1(side)[FL][FR][FC][LFE][SL][SR];
${VOICE_BLOCK}
[FL]aformat=channel_layouts=mono[FLf];
[FR]aformat=channel_layouts=mono[FRf];
[FCv]aformat=channel_layouts=mono[FCf];
[LFE]aformat=channel_layouts=mono[LFEf];
${SUR_BLOCK}
[SL_out]aformat=channel_layouts=mono[SLf];
[SR_out]aformat=channel_layouts=mono[SRf];
[FLf][FRf][FCf][LFEf][SLf][SRf]join=inputs=6:channel_layout=5.1(side):map=0.0-FL|1.0-FR|2.0-FC|3.0-LFE|4.0-SL|5.0-SR,
alimiter=limit=0.97:attack=1.5:release=25:asc=1:level=1[aout]
"
  CMD=(ffmpeg -y -hide_banner -nostdin -stats -loglevel warning
       $HW_INIT
       -i "$CUR_FILE"
       -map_metadata 0
       -map_chapters 0
       -filter_complex "$FILTER_COMPLEX"
       -map 0:v -c:v copy
       -map "[aout]" -c:a:0 "$OUT_CODEC" -b:a:0 "$BITRATE" -ar:a:0 48000 -ac:a:0 6
       -metadata:s:a:0 title="${OUT_CODEC^^} 5.1 – ${SUR_MODE^} (EQ Voce + DSP Surround)"
       -disposition:a:0 default)

  [[ -n "$A_LANG" && "${A_LANG,,}" != "und" ]] && CMD+=( -metadata:s:a:0 language="$A_LANG" )

  if ffprobe -v quiet -select_streams s -show_entries stream=index -of csv=p=0 "$CUR_FILE" | grep -q .; then
    CMD+=( -map 0:s -c:s copy )
  fi

  if [[ "$KEEP_ORIG" = "si" ]]; then
    ORIG_TITLE=$(get_audio_title_by_index "$CUR_FILE" "$A_STREAM_INDEX" || echo "Original Audio")
    CMD+=( -map 0:"$A_STREAM_INDEX" -c:a:1 copy -metadata:s:a:1 title="$ORIG_TITLE" -disposition:a:1 0 )
  fi

  CMD+=( "$OUT_FILE" )

  info "Esecuzione [hwaccel: $HW_NAME]"
  if "${CMD[@]}"; then
    ok "Creato: $OUT_FILE"
  else
    warn "Errore su: $CUR_FILE"
  fi
done

ok "Elaborazione completata"

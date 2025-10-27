#!/usr/bin/env bash
set -euo pipefail

#───────────────────────────────────────────────────────────────────────────────
# convert_2AC3_sonar.sh (Copilot Version)
# EQ voce (solo EQ) | LFE moderato | Upfiring surround "neuro:x" deciso ma controllato
# Uso:
#   ./convert_2AC3_sonar.sh <sonar|clean> <si|no> <file.mkv> <preset> [bitrate]
# Esempio:
#   ./convert_2AC3_sonar.sh sonar no "Film.mkv" eac36 640k
#───────────────────────────────────────────────────────────────────────────────

# -------------------------
# Colori e helper per output
# -------------------------
C_INFO="\033[0;36m[INFO]\033[0m"
C_WARN="\033[0;33m[WARNING]\033[0m"
C_ERR="\033[0;31m[ERROR]\033[0m"
C_OK="\033[0;32m[OK]\033[0m"

info(){ echo -e "${C_INFO} $*"; }
warn(){ echo -e "${C_WARN} $*"; }
err(){  echo -e "${C_ERR}  $*"; }
ok(){   echo -e "${C_OK}  $*"; }

# -------------------------
# Guida
# -------------------------
show_help(){ cat <<'USAGE'
───────────────────────────────────────────────────────────────────────────────
UTILIZZO:
  ./convert_2AC3_sonar.sh <sonar|clean> <si|no> <file.mkv> <preset> [bitrate]

PARAMETRI:
  1) Modalità  : sonar | clean
     - sonar → EQ voce + Upfiring surround "neuro:x" (deciso ma controllato)
     - clean → EQ voce + surround pulito (conservativo)
  
  2) Originale : si | no
     - si  → Mantiene la traccia audio originale come seconda traccia
     - no  → Solo AC3 riallavorato
  
  3) File      : percorso al file .mkv (obbligatorio)
  4) Preset    : atmos | dts | eac37 | eac36 | ac3
  5) Bitrate   : 320k | 448k | 640k (default: 640k)
───────────────────────────────────────────────────────────────────────────────
USAGE
}

## Mostra la guida e termina lo script.
if [[ $# -eq 0 || "${1:-}" =~ ^(-h|--help|help|guida|/\?)$ ]]; then
  show_help
  exit 0
fi

# -------------------------
# Argomenti
# -------------------------
SONAR_MODE="${1:-}"
KEEP_ORIG="${2:-}"
INPUT_FILE="${3:-}"
PRESET="${4:-}"
BITRATE="${5:-640k}"

# -------------------------
# Validazione input
# -------------------------
if [[ $# -lt 4 ]]; then
  err "Parametri insufficienti."
  show_help
  exit 2
fi

[[ "$SONAR_MODE" =~ ^(sonar|clean)$ ]] || { err "Modalità non valida: $SONAR_MODE"; show_help; exit 2; }
[[ "$KEEP_ORIG"  =~ ^(si|no)$     ]]   || { err "Parametro 2 (si|no) non valido: $KEEP_ORIG"; show_help; exit 2; }
[[ -f "$INPUT_FILE" ]]              || { err "File non trovato: $INPUT_FILE"; exit 2; }

case "$PRESET" in atmos|dts|eac37|eac36|ac3) ;; 
  *) err "Preset non valido: $PRESET (ammessi: atmos|dts|eac37|eac36|ac3)"; show_help; exit 2;;
esac

case "$BITRATE" in 320k|448k|640k) ;; 
  *) err "Bitrate non valido: $BITRATE (ammessi: 320k, 448k, 640k)"; exit 2;;
esac

command -v ffmpeg >/dev/null || { err "ffmpeg non trovato nel PATH"; exit 3; }
command -v ffprobe >/dev/null || { err "ffprobe non trovato nel PATH"; exit 3; }

# -------------------------
# Funzioni DSP
# -------------------------
get_dynamic_values() {
  local preset="$1"
  case "$preset" in
    atmos) echo "0.6,-1.2" ;;
    dts)   echo "0.6,-1.5" ;;
    eac37) echo "0.4,-0.5" ;;
    eac36) echo "0.2,0.0" ;;
    ac3)   echo "0.2,0.0" ;;
  esac
}

get_voice_filter() {
  local voce_boost_db="$1"
  awk -v vb="$voce_boost_db" 'BEGIN{
    fc=vb; fr=vb/2;
    printf("[FC]equalizer=f=2400:t=q:w=1.0:g=%0.2f[FC_eq];", fc);
    printf("[FL]equalizer=f=2400:t=q:w=1.0:g=%0.2f[FL_eq];", fr);
    printf("[FR]equalizer=f=2400:t=q:w=1.0:g=%0.2f[FR_eq];", fr);
  }'
}

get_lfe_filter() {
  local lfe_db="$1"
  if [[ "$lfe_db" != "0.0" ]]; then
    echo "[LFE]highpass=f=22,volume=${lfe_db}dB[LFE_clean];"
  else
    echo "[LFE]highpass=f=22[LFE_clean];"
  fi
}

get_sonar_surround(){
cat <<'EOF'
[SL]equalizer=f=3200:t=q:w=1.2:g=1.0, equalizer=f=5500:t=q:w=1.6:g=0.8[SL_hf];
[SL_hf]adelay=9,volume=-3dB[SL_t1];
[SL_t1]highpass=f=1600,bandpass=f=4200:t=q:w=1.6,volume=-6dB[SL_t1f];
[SL_t1f]adelay=21,volume=-9dB,lowpass=f=6500[SL_t2];
[SL_t2]highpass=f=1600,bandpass=f=5200:t=q:w=1.8,volume=-12dB[SL_t2f];
[SL_t2f]adelay=37,volume=-14dB,lowpass=f=5200[SL_er];
[SL_er]aecho=0.12:0.07:16:0.030[SL_boost];
[SL_boost]volume=+3.5dB[SL_out];

[SR]equalizer=f=3400:t=q:w=1.2:g=1.0, equalizer=f=5600:t=q:w=1.6:g=0.8[SR_hf];
[SR_hf]adelay=11,volume=-3dB[SR_t1];
[SR_t1]highpass=f=1600,bandpass=f=4400:t=q:w=1.6,volume=-6dB[SR_t1f];
[SR_t1f]adelay=23,volume=-9dB,lowpass=f=6300[SR_t2];
[SR_t2]highpass=f=1600,bandpass=f=5400:t=q:w=1.8,volume=-12dB[SR_t2f];
[SR_t2f]adelay=39,volume=-14dB,lowpass=f=5100[SR_er];
[SR_er]aecho=0.12:0.07:18:0.030[SR_boost];
[SR_boost]volume=+3.5dB[SR_out];
EOF
}

get_clean_surround(){
  echo "[SL]equalizer=f=5200:t=q:w=1.2:g=0.4[SL_boost];[SL_boost]volume=+3.0dB[SL_out];[SR]equalizer=f=5200:t=q:w=1.2:g=0.4[SR_boost];[SR_boost]volume=+3.0dB[SR_out];"
}

# -------------------------
# Preparazione I/O e costruzione filtri
# -------------------------
BASENAME=$(basename "$INPUT_FILE" .mkv)
OUT_SUFFIX=$([ "$SONAR_MODE" = "sonar" ] && echo "sonar" || echo "CleanRoom")
OUT_FILE="${BASENAME}_AC3_${OUT_SUFFIX}.mkv"

if [[ -f "$OUT_FILE" ]]; then
  printf "%b Il file '%s' esiste. Sovrascrivere? [s/N] " "$C_WARN" "$OUT_FILE"
  read -r a
  [[ "$a" =~ ^[sS]$ ]] || { warn "Skip '$OUT_FILE'"; exit 0; }
fi

IFS=',' read -r VOICE_BOOST LFE_VOL <<< "$(get_dynamic_values "$PRESET")"
VOICE_FILTER="$(get_voice_filter "$VOICE_BOOST")"
LFE_FILTER="$(get_lfe_filter "$LFE_VOL")"
if [[ "$SONAR_MODE" = "sonar" ]]; then
  SUR_FILTERS="$(get_sonar_surround)"
else
  SUR_FILTERS="$(get_clean_surround)"
fi

# Info a schermo
info "─────────────────────────────────────────────────────────────"
info "File di input : $INPUT_FILE"
info "File di output: $OUT_FILE"
info "Modalità      : $SONAR_MODE"
info "Preset        : $PRESET"
info "Bitrate       : $BITRATE"
info "EQ voce       : ${VOICE_BOOST} dB @2.4 kHz (FC), metà su FL/FR"
info "LFE adj       : ${LFE_VOL} dB (highpass 22 Hz)"
info "Surround      : Neuro:X Virtual Upfiring (delay + HF)"
info "─────────────────────────────────────────────────────────────"
info "Avvio conversione → AC3 ${BITRATE} ..."

# -------------------------
# Costruzione del filter_complex (robusta)
# -------------------------
read -r -d '' FILTER_COMPLEX <<EOF || true
[0:a:0]channelsplit=channel_layout=5.1[FL][FR][FC][LFE][SL][SR];
${VOICE_FILTER}
${LFE_FILTER}
${SUR_FILTERS}
[FL_eq]aformat=channel_layouts=mono[FLf];
[FR_eq]aformat=channel_layouts=mono[FRf];
[FC_eq]aformat=channel_layouts=mono[FCf];
[LFE_clean]aformat=channel_layouts=mono[LFEf];
[SL_out]aformat=channel_layouts=mono[SLf];
[SR_out]aformat=channel_layouts=mono[SRf];
[FLf][FRf][FCf][LFEf][SLf][SRf]amerge=inputs=6[a_merged];
[a_merged]channelmap=channel_layout=5.1:map=0-0|1-1|2-2|3-3|4-4|5-5[a_mapped];
[a_mapped]aresample=resampler=soxr:precision=28:dither_method=triangular[aout]
EOF

# -------------------------
# Comando ffmpeg e mappe
# -------------------------
CMD=(ffmpeg -y -hide_banner -nostdin -stats -loglevel error \
     -i "$INPUT_FILE" -filter_complex "$FILTER_COMPLEX" \
     -map 0:v:0 -c:v copy \
     -map "[aout]" -c:a ac3 -b:a "$BITRATE" -ar 48000 -ac 6)

# Copia sottotitoli se presenti
if ffprobe -v quiet -select_streams s -show_entries stream=index -of csv=p=0 "$INPUT_FILE" | grep -q .; then
  info "Sottotitoli rilevati: saranno copiati nel file di output."
  CMD+=(-map 0:s -c:s copy)
fi

# Mantieni traccia originale se richiesto
if [[ "$KEEP_ORIG" = "si" ]]; then
  info "Mantieni traccia audio originale: verrà aggiunta come traccia aggiuntiva."
  ORIG_TITLE="$(ffprobe -v quiet -select_streams a:0 -show_entries stream_tags=title -of csv=p=0 "$INPUT_FILE" 2>/dev/null || true)"
  [[ -z "$ORIG_TITLE" ]] && ORIG_TITLE="Original Audio"
  CMD+=(-map 0:a:0 -c:a:1 copy -metadata:s:a:1 title="$ORIG_TITLE" -disposition:a:1 none)
fi

# Metadati per la traccia AC3 prodotta
CMD+=(-metadata:s:a:0 title="AC3 5.1 ${OUT_SUFFIX}" -disposition:a:0 default "$OUT_FILE")

# -------------------------
# Esecuzione con feedback
# -------------------------
info "Esecuzione ffmpeg: questa fase può impiegare diversi minuti..."
set +e
"${CMD[@]}"
RET=$?
set -e

# -------------------------
# Risultato e suggerimenti post-process
# -------------------------
if [[ $RET -eq 0 || $RET -eq 1 ]]; then
  info "────────────────────────────────────────────────────────"
  ok "Completato: $OUT_FILE"
  info "────────────────────────────────────────────────────────"
  exit 0
else
  info "────────────────────────────────────────────────────────"
  err "Errore durante la conversione: codice di uscita $RET"
  err "Controlla l'output di ffmpeg per dettagli su errori."
  info "────────────────────────────────────────────────────────"
  exit "$RET"
fi
#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════════════╗
# ║  converti_2AC3_sonar_v5.sh                                             ║
# ║  Edizione Nerd: Voce “sartoriale” ITA + LFE pulito + Surround tunable  ║
# ╚════════════════════════════════════════════════════════════════════════╝
# • Voce: EQ minimale a 4.2 kHz (Q 1.4, +1.2 dB) + boost preset-specifico.
#   Niente compressori sulla voce → addio metallicità/gracchi.
# • LFE: SOLO high-pass 25 Hz + (facoltativo) attenuazione volume + limiter.
#   Niente EQ sul sub per coerenza col crossover dell’AVR.
# • Surround: modalità "sonar" (upfiring psicoacustico) o "clean" (neutro)
#   con boost di default: sonar +0.9 dB, clean +0.6 dB (override: SUR_DB).
# • Merge 5.1 robusto: aformat per i 6 ingressi + channelmap=5.1.
# • Batch intelligente (se non passi il file) + copia video/sub + AC3 out.

set -euo pipefail

# ──────────────────────────────────────────────
# 🎨 Colori
# ──────────────────────────────────────────────
C_INFO="\033[0;36m[INFO]\033[0m"; C_OK="\033[1;32m[OK]\033[0m"; C_ERR="\033[1;31m[ERROR]\033[0m"; C_WARN="\033[1;33m[WARNING]\033[0m"
info(){ echo -e "$C_INFO $*"; } ; ok(){ echo -e "$C_OK $*"; } ; err(){ echo -e "$C_ERR $*"; } ; warn(){ echo -e "$C_WARN $*"; }

# ──────────────────────────────────────────────
# 📜 Guida
# ──────────────────────────────────────────────
show_help(){ cat <<'USAGE'
============================================================================================
UTILIZZO:
  ./converti_2AC3_sonar.sh <sonar|clean> <si|no> [file.mkv] [preset] [bitrate]

Parametri:
  - Primo:   "sonar"    → EQ Voce Sartoriale + Filtro Upfiring Surround (+0.9 dB surround)
             "clean"    → EQ Voce Sartoriale + Surround Pulito (+0.6 dB surround)
  - Secondo: "si"       → Mantiene audio originale | "no" → Solo AC3
  - Terzo:   [file.mkv] → Singolo o lascia vuoto per Batch.
  - Quarto:  [preset]   → "atmos" | "dts" | "eac37" | "eac36" | "ac3" | "auto" (default)
  - Quinto:  [bitrate]  → "448k", "640k" (default), ecc.

Preset audio (boost voce / LFE):
  atmos → +1.1 dB / -2.0 dB
  dts   → +1.0 dB / -2.3 dB
  eac37 → +0.9 dB / -1.2 dB
  eac36 → +0.8 dB /  0.0 dB
  ac3   → +0.7 dB /  0.0 dB
  auto  → rilevamento dal nome file ("atmos", "dts", "768", "640")

Note:
  - Surround boost di default: +0.9 dB (sonar) | +0.6 dB (clean)
  - Puoi forzare il boost surround con SUR_DB, es.: SUR_DB=1.2 ./converti_2AC3_sonar.sh ...
============================================================================================
USAGE
exit 0 ; }

# ──────────────────────────────────────────────
# 📥 Parametri + validazioni
# ──────────────────────────────────────────────
if [ "$#" -lt 2 ]; then show_help; fi
SONAR_MODE=$(echo "${1}" | tr '[:upper:]' '[:lower:]')   # sonar | clean
KEEP_ORIG=$(echo "${2}" | tr '[:upper:]' '[:lower:]')     # si | no
INPUT_FILE="${3:-}"                                      # opzionale → batch
PRESET=$(echo "${4:-auto}" | tr '[:upper:]' '[:lower:]')  # atmos|dts|eac37|eac36|ac3|auto
BITRATE="${5:-640k}"
case "$SONAR_MODE" in sonar|clean) ;; *) err "Modalità non valida: $SONAR_MODE"; exit 1;; esac
case "$KEEP_ORIG" in si|no) ;; *) err "Parametro (si|no) non valido: $KEEP_ORIG"; exit 1;; esac
case "$PRESET" in atmos|dts|eac37|eac36|ac3|auto) ;; *) err "Preset non valido: $PRESET"; exit 1;; esac
case "$BITRATE" in *k) ;; *) err "Bitrate non valido (es. 448k, 640k): $BITRATE"; exit 1;; esac

# Lista file
if [ -n "$INPUT_FILE" ]; then
  FILES=("$INPUT_FILE")
else
  mapfile -d $'\0' -t FILES < <(find . -maxdepth 1 -type f -iname "*.mkv" ! -iname "*_AC3_*.mkv" -print0)
  [ ${#FILES[@]} -eq 0 ] && { info "Nessun MKV da processare"; exit 0; }
  info "Batch: trovati ${#FILES[@]} file"
fi

# ──────────────────────────────────────────────
# 🔧 Opzioni globali
# ──────────────────────────────────────────────
: "${SUR_DB:=auto}"
if [ "$SUR_DB" = "auto" ]; then
  if [ "$SONAR_MODE" = "sonar" ]; then SUR_GAIN="+0.9dB"; else SUR_GAIN="+0.6dB"; fi
else
  SUR_GAIN="$(printf '%+0.1fdB' "$SUR_DB")"
fi

# ──────────────────────────────────────────────
# 🧠 Preset voce/LFE normalizzati
# ──────────────────────────────────────────────
get_dynamic_values(){
  local preset="$1"; local boost_voce lfe_vol
  case "$preset" in
    atmos) boost_voce="1.1"; lfe_vol="-2.0" ;;
    dts)   boost_voce="1.0"; lfe_vol="-2.3" ;;
    eac37) boost_voce="0.9"; lfe_vol="-1.2" ;;
    eac36) boost_voce="0.8"; lfe_vol="0.0"  ;;
    ac3)   boost_voce="0.7"; lfe_vol="0.0"  ;;
    auto|*)
      if   [[ "$CUR_FILE" == *"atmos"* ]] ; then boost_voce="1.1"; lfe_vol="-2.0"
      elif [[ "$CUR_FILE" == *"dts"*   ]] ; then boost_voce="1.0"; lfe_vol="-2.3"
      elif [[ "$CUR_FILE" == *"768"*   ]] ; then boost_voce="0.9"; lfe_vol="-1.2"
      elif [[ "$CUR_FILE" == *"640"*   ]] ; then boost_voce="0.8"; lfe_vol="0.0"
      else                                       boost_voce="0.7"; lfe_vol="0.0"; fi ;;
  esac
  echo "${boost_voce},${lfe_vol}"
}

# ──────────────────────────────────────────────
# 🗣️ Voice filter — EQ sartoriale ITA
# ──────────────────────────────────────────────
get_voice_filter(){
  local voce_boost="$1"
  echo "[FC]equalizer=f=4200:t=q:w=1.4:g=1.2,volume=${voce_boost}dB[FC_plus];"
}

# ──────────────────────────────────────────────
# 🌀 LFE filter
# ──────────────────────────────────────────────
get_lfe_filter(){
  local lfe_vol_db="$1"
  local f="[LFE]highpass=f=25"
  [ "$lfe_vol_db" != "0.0" ] && f+=",volume=${lfe_vol_db}dB"
  f+=",alimiter=limit=0.90[LFE_clean];"
  echo "$f"
}

# ──────────────────────────────────────────────
# 🛰️ Surround sonar (upfiring psicoacustico)
# ──────────────────────────────────────────────
# 🛰️ Surround sonar (one-liner, senza here-doc)
get_sonar_surround(){
  echo "[SL]equalizer=f=2400:t=q:w=1.4:g=2.1, equalizer=f=6000:t=q:w=1.6:g=1.7, aecho=0.78:0.86:18:0.28, aecho=0.70:0.88:22:0.24, aecho=0.60:0.90:90:0.20, aecho=0.60:0.90:16:0.35, volume=${SUR_GAIN},alimiter=limit=0.97[SL_boost];[SR]equalizer=f=2400:t=q:w=1.4:g=2.1, equalizer=f=6000:t=q:w=1.6:g=1.7, aecho=0.78:0.86:20:0.28, aecho=0.70:0.88:24:0.24, aecho=0.60:0.90:92:0.20, aecho=0.60:0.90:18:0.32, volume=${SUR_GAIN},alimiter=limit=0.97[SR_boost];"
}


# ──────────────────────────────────────────────
# 🧼 Surround clean (neutro, solo gain)
# ──────────────────────────────────────────────
get_clean_surround(){
  echo "[SL]volume=${SUR_GAIN}[SL_boost];[SR]volume=${SUR_GAIN}[SR_boost];"
}

# ──────────────────────────────────────────────
# 📝 Controllo esistenza file output
# ──────────────────────────────────────────────
should_overwrite() {
  local f="$1"
  OVERWRITE_FLAG=""

  if [[ -f "$f" ]]; then
    echo -e "${C_WARN} Il file di destinazione \033[1;33m'$f'\033[0m esiste già."
    read -p "Sovrascrivere? [s/N] " answer
    if [[ "$answer" =~ ^([sS]|[yY])$ ]]; then
      OVERWRITE_FLAG="-y"
      info "➡  Sovrascrittura abilitata."
    else
      warn "Skip: $f"
      return 1
    fi
  fi
  return 0
}

# ──────────────────────────────────────────────
# 🔁 Loop file
# ──────────────────────────────────────────────
for CUR_FILE in "${FILES[@]}"; do
  BASENAME=$(basename "$CUR_FILE" .mkv)
  OUT_SUFFIX=$([ "$SONAR_MODE" = sonar ] && echo "Sonar" || echo "Clean")
  OUT_FILE="${BASENAME}_AC3_${OUT_SUFFIX}.mkv"

  IFS=',' read -r VOICE_BOOST LFE_VOL <<< "$(get_dynamic_values "$PRESET")"
  VOICE_FILTER="$(get_voice_filter "$VOICE_BOOST")"
  LFE_FILTER="$(get_lfe_filter "$LFE_VOL")"
  if [ "$SONAR_MODE" = sonar ]; then
    SUR_FILTERS="$(get_sonar_surround)"
  else
    SUR_FILTERS="$(get_clean_surround)"
  fi

  info "============================================================================"
  info "➡  Input:  $CUR_FILE"
  info "➡  Output: $OUT_FILE"
  info "➡  Preset: $PRESET  |  Boost voce: ${VOICE_BOOST} dB  |  LFE: ${LFE_VOL} dB"
  info "➡  Surround gain: ${SUR_GAIN}  |  Modalità: ${SONAR_MODE}"
  info "============================================================================"

  FILTER_COMPLEX="[0:a:0]aformat=channel_layouts=5.1,channelsplit=channel_layout=5.1[FL][FR][FC][LFE][SL][SR];\
  ${VOICE_FILTER}${LFE_FILTER}${SUR_FILTERS}\
  [FL]aformat=channel_layouts=FL[FLf];[FR]aformat=channel_layouts=FR[FRf];\
  [FC_plus]aformat=channel_layouts=FC[FCf];[LFE_clean]aformat=channel_layouts=LFE[LFEf];\
  [SL_boost]aformat=channel_layouts=SL[SLf];[SR_boost]aformat=channel_layouts=SR[SRf];\
  [FLf][FRf][FCf][LFEf][SLf][SRf]amerge=inputs=6,channelmap=channel_layout=5.1,\
  aresample=resampler=soxr:precision=28:dither_method=triangular,alimiter=limit=0.96[aout]"

  # Prompt overwrite + run
  if ! should_overwrite "$OUT_FILE"; then
    continue
  fi

  CMD=(ffmpeg $OVERWRITE_FLAG -hide_banner -nostdin -stats -loglevel warning \
       -i "$CUR_FILE" -filter_complex "$FILTER_COMPLEX" \
       -map 0:v:0 -c:v copy -map "[aout]" -c:a ac3 -b:a "$BITRATE" -ar 48000 -ac 6)

  # Mantieni sottotitoli se presenti
  if ffprobe -v quiet -select_streams s -show_entries stream=index -of csv=p=0 "$CUR_FILE" | grep -q .; then
    CMD+=(-map 0:s -c:s copy)
  fi

  # Mantieni audio originale?
  if [ "$KEEP_ORIG" = "si" ]; then
    CMD+=(-map 0:a:0 -c:a:1 copy -metadata:s:a:1 title="Original Audio" -disposition:a:1 0)
  fi

  CMD+=(-metadata:s:a:0 title="AC3 5.1 ${OUT_SUFFIX}" -disposition:a:0 default "$OUT_FILE")

  info "➡  Avvio conversione → AC3 $BITRATE"
  "${CMD[@]}" && ok "Completato: $OUT_FILE" || err "Error: $OUT_FILE"

done

ok "Batch concluso — AC3 ottimizzato per Kenwood RV6000 + KS1-300HT + SW40HT"


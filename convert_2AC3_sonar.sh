#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────────────────────────────────────
# 🛠️ converti_2AC3_sonar.sh — Encoder AC3 5.1 con EQ vocale e Upfiring psicoacustico
# ────────────────────────────────────────────────────────────────────────────────────────────
# Questo script automatizza la conversione di tracce audio multicanale in formato AC3 5.1,
# applicando una catena DSP personalizzata per migliorare l’intelligibilità della voce
# e la spazialità dei canali surround, con particolare attenzione alla resa in home theatre.
#
# ✨ Caratteristiche principali:
# • Voce — EQ “sartoriale”:
#   - Boost mirato a 2.5 kHz (presenza vocale) e 4.2 kHz (chiarezza sibilanti).
#   - Volume dinamico per adattarsi a formati e mix diversi.
#
# • LFE — Subwoofer:
#   - High-pass fisso a 25 Hz per eliminare l’infrasuono inutile.
#   - Attenuazione opzionale (preset-specifica) e limiter finale.
#
# • Surround — due modalità:
#   - “sonar” → filtro psicoacustico upfiring (simulazione Atmos / Neural:X).
#   - “clean” → surround neutro, solo gain controllato.
#
# • Merge 5.1 robusto:
#   - channelsplit → processing per canale → amerge + channelmap coerente.
#
# • Funzionalità pratiche:
#   - Conversione singola o batch automatica.
#   - Preservazione sottotitoli e (opzionale) traccia audio originale.
#   - Overwrite interattivo.
#   - Preset automatici per voce/LFE in base al formato sorgente.
# ────────────────────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ────────────────────────────────────────────────────────────────────────────────────────────
# 🎨 Colori — gestione output testuale
# ────────────────────────────────────────────────────────────────────────────────────────────
# • Definisce le sequenze ANSI per colorare i messaggi a terminale:
#   - INFO  → ciano, per messaggi informativi.
#   - OK    → verde, per operazioni completate con successo.
#   - ERROR → rosso, per errori critici o interruzioni.
#   - WARNING → giallo, per avvisi non bloccanti.
# ────────────────────────────────────────────────────────────────────────────────────────────
C_INFO="\033[0;36m[INFO]\033[0m"
C_OK="\033[1;32m[OK]\033[0m"
C_ERR="\033[1;31m[ERROR]\033[0m"
C_WARN="\033[1;33m[WARNING]\033[0m"

info()  { echo -e "$C_INFO $*"; }
ok()    { echo -e "$C_OK $*"; }
err()   { echo -e "$C_ERR $*"; }
warn()  { echo -e "$C_WARN $*"; }

# ────────────────────────────────────────────────────────────────────────────────────────────
# 📝 Gestione Segnali — SIGINT
# ────────────────────────────────────────────────────────────────────────────────────────────
# • Intercetta la pressione di CTRL+C durante l’esecuzione (SIGINT).
# • Termina con exit code 130 (standard POSIX per interruzione manuale).
# ────────────────────────────────────────────────────────────────────────────────────────────
cleanup_on_interrupt() {
    warn "Interrotto manualmente — conversione parziale."
    exit 130   # codice di uscita standard per SIGINT
}
trap cleanup_on_interrupt INT

# ────────────────────────────────────────────────────────────────────────────────────────────
# 📜 Guida — Help CLI
# ────────────────────────────────────────────────────────────────────────────────────────────
# • Mostra l’help contestuale dello script:
#   - Spiega sintassi e parametri di invocazione.
#   - Elenca i preset audio disponibili e il comportamento di default.
#   - Evidenzia le opzioni di boost surround automatiche o manuali (SUR_DB).
# ────────────────────────────────────────────────────────────────────────────────────────────
show_help(){ cat <<'USAGE'
────────────────────────────────────────────────────────────────────────────────────────────
UTILIZZO:
./converti_2AC3_sonar.sh <sonar|clean> <si|no> [file.mkv] [preset] [bitrate]

Parametri:
- Primo: "sonar" → EQ Voce Sartoriale + Filtro Upfiring Surround (+0.9 dB surround)
"clean" → EQ Voce Sartoriale + Surround Pulito (+0.6 dB surround)
- Secondo: "si" → Mantiene audio originale | "no" → Solo AC3
- Terzo: [file.mkv] → Singolo o lascia vuoto per Batch.
- Quarto: [preset] → "atmos" | "dts" | "eac37" | "eac36" | "ac3" | "auto" (default)
- Quinto: [bitrate] → "448k", "640k" (default), ecc.

Preset audio (boost voce / LFE):
atmos → +0.7 dB / -2.0 dB
dts → +0.7 dB / -2.3 dB
eac37 → +0.5 dB / -1.2 dB
eac36 → +0.5 dB / 0.0 dB
ac3 → +0.5 dB / 0.0 dB
auto → rilevamento dal nome file ("atmos", "dts", "768", "640")

Note:
- Surround boost di default: +0.9 dB (sonar) | +0.6 dB (clean)
- Puoi forzare il boost surround con SUR_DB, es.: SUR_DB=1.2 ./converti_2AC3_sonar.sh...
────────────────────────────────────────────────────────────────────────────────────────────
USAGE
exit 0 ; }

# ────────────────────────────────────────────────────────────────────────────────────────────
# 📥 Parametri + validazioni
# ────────────────────────────────────────────────────────────────────────────────────────────
# • Riceve e valida i parametri CLI passati allo script:
#   1. Modalità (sonar|clean) → determina tipo di surround.
#   2. Flag mantenimento audio originale (si|no).
#   3. File input (opzionale) → se assente, attiva batch.
#   4. Preset audio (atmos|dts|eac37|eac36|ac3|auto).
#   5. Bitrate target AC3.
# ────────────────────────────────────────────────────────────────────────────────────────────
if [ "$#" -lt 2 ]; then show_help; fi
SONAR_MODE=$(echo "${1}" | tr '[:upper:]' '[:lower:]')
KEEP_ORIG=$(echo "${2}" | tr '[:upper:]' '[:lower:]')
INPUT_FILE="${3:-}"
PRESET=$(echo "${4:-auto}" | tr '[:upper:]' '[:lower:]')
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

# ────────────────────────────────────────────────────────────────────────────────────────────
# 🔧 Opzioni globali — gestione gain surround
# ────────────────────────────────────────────────────────────────────────────────────────────
# • Se SUR_DB non è definito a mano imposta automaticamente:
#   - +0.9 dB per modalità “sonar”
#   - +0.6 dB per modalità “clean”
# • Se SUR_DB è definito manualmente, formatta il valore come dB espliciti.
# ────────────────────────────────────────────────────────────────────────────────────────────
: "${SUR_DB:=auto}"
if [ "$SUR_DB" = "auto" ]; then
  if [ "$SONAR_MODE" = "sonar" ]; then SUR_GAIN="+0.9dB"; else SUR_GAIN="+0.6dB"; fi
else
  SUR_GAIN="$(printf '%+0.1fdB' "$SUR_DB")"
fi

# ────────────────────────────────────────────────────────────────────────────────────────────
# 🧠 Preset voce/LFE normalizzati — post EQ vocale
# ────────────────────────────────────────────────────────────────────────────────────────────
# • Definisce i valori predefiniti di boost voce e attenuazione LFE
#   in base al tipo di sorgente audio (Atmos, DTS, EAC3, AC3).
# • Permette rilevamento automatico da nome file (auto) per adattarsi dinamicamente.
# ────────────────────────────────────────────────────────────────────────────────────────────
get_dynamic_values(){
  local preset="$1"; local boost_voce lfe_vol
  case "$preset" in
    atmos) boost_voce="0.7"; lfe_vol="-2.0" ;;
    dts)   boost_voce="0.7"; lfe_vol="-2.3" ;;
    eac37) boost_voce="0.5"; lfe_vol="-1.2" ;;
    eac36) boost_voce="0.5"; lfe_vol="0.0"  ;;
    ac3)   boost_voce="0.5"; lfe_vol="0.0"  ;;
    auto|*)
      if   [[ "$CUR_FILE" == *"atmos"* ]] ; then boost_voce="0.7"; lfe_vol="-2.0"
      elif [[ "$CUR_FILE" == *"dts"*   ]] ; then boost_voce="0.7"; lfe_vol="-2.3"
      elif [[ "$CUR_FILE" == *"768"*   ]] ; then boost_voce="0.5"; lfe_vol="-1.2"
      elif [[ "$CUR_FILE" == *"640"*   ]] ; then boost_voce="0.5"; lfe_vol="0.0"
      else                                       boost_voce="0.5"; lfe_vol="0.0"
      fi
    ;;
  esac
  echo "${boost_voce},${lfe_vol}"
}

# ────────────────────────────────────────────────────────────────────────────────────────────
# 🗣️ Voice filter — EQ sartoriale ITA
# ────────────────────────────────────────────────────────────────────────────────────────────
# • EQ mirato per migliorare intelligibilità della lingua italiana:
#   - 2500 Hz → boost presenza (formanti vocali)
#   - 4200 Hz → boost chiarezza (sibilanti e definizione)
# ────────────────────────────────────────────────────────────────────────────────────────────
get_voice_filter(){
  local voce_boost="$1"
  echo "[FC]equalizer=f=2500:t=q:w=2.0:g=0.5,equalizer=f=4200:t=q:w=1.4:g=1.2,volume=${voce_boost}dB,alimiter=limit=0.9[FC_plus];"
}

# ────────────────────────────────────────────────────────────────────────────────────────────
# 🌀 LFE filter — gestione subwoofer
# ────────────────────────────────────────────────────────────────────────────────────────────
# • Applica un filtro high-pass a 25 Hz per eliminare l’infrasuono inutile,
#   lasciando al crossover dell’AVR la gestione della curva di risposta.
# ────────────────────────────────────────────────────────────────────────────────────────────
get_lfe_filter(){
  local lfe_vol_db="$1"
  local f="[LFE]highpass=f=25"
  [ "$lfe_vol_db" != "0.0" ] && f+=",volume=${lfe_vol_db}dB"
  f+=",alimiter=limit=0.90[LFE_clean];"
  echo "$f"
}

# ────────────────────────────────────────────────────────────────────────────────────────────
# 🛰️ Surround sonar — simulazione upfiring Atmos / Neural:X
# ────────────────────────────────────────────────────────────────────────────────────────────
# • Filtri psicoacustici per simulare riflessioni verticali tipiche dei diffusori upfiring:
#   - Delay corti e medi (14–92 ms) per "rimbalzo dal soffitto" realistico.
#   - Boost medi-alti + highshelf per dare “aria” e direzionalità verticale.
#   - Micro-asimmetria L/R per effetto HRTF (percezione altezza).
# ────────────────────────────────────────────────────────────────────────────────────────────
get_sonar_surround(){
  echo "[SL]equalizer=f=2400:t=q:w=1.4:g=1.7, equalizer=f=6000:t=q:w=1.8:g=2.0, highshelf=f=8000:g=1.0, \
  aecho=0.78:0.88:14:0.35, aecho=0.72:0.86:24:0.28, aecho=0.66:0.88:60:0.20, aecho=0.60:0.90:90:0.18, \
  volume=${SUR_GAIN}, alimiter=limit=0.96[SL_boost]; \
  [SR]equalizer=f=2400:t=q:w=1.4:g=1.7, equalizer=f=6000:t=q:w=1.8:g=2.0, highshelf=f=8000:g=1.0, \
  aecho=0.78:0.88:16:0.35, aecho=0.72:0.86:26:0.28, aecho=0.66:0.88:62:0.20, aecho=0.60:0.90:92:0.18, \
  volume=${SUR_GAIN}, alimiter=limit=0.96[SR_boost];"
}

# ────────────────────────────────────────────────────────────────────────────────────────────
# 🧼 Surround clean — fallback neutro
# ────────────────────────────────────────────────────────────────────────────────────────────
# • Nessun EQ o echo sui canali surround.
# • Solo gain controllato tramite SUR_GAIN.
# ────────────────────────────────────────────────────────────────────────────────────────────
get_clean_surround(){
  echo "[SL]volume=${SUR_GAIN}[SL_boost];[SR]volume=${SUR_GAIN}[SR_boost];"
}

# ────────────────────────────────────────────────────────────────────────────────────────────
# 📝 Controllo esistenza file output
# ────────────────────────────────────────────────────────────────────────────────────────────
# • Se il file di destinazione esiste, chiede conferma per la sovrascrittura.
# • Se il file non esiste → procede normalmente.
# ────────────────────────────────────────────────────────────────────────────────────────────
should_overwrite() {
  local f="$1"
  OVERWRITE_FLAG=""

  # File esistente (prompt interattivo)
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

# ────────────────────────────────────────────────────────────────────────────────────────────
# 🔁 Loop file — Motore di conversione batch/singolo file
# ────────────────────────────────────────────────────────────────────────────────────────────
# Questo ciclo rappresenta il “cuore pulsante” dello script:
# • Itera su tutti i file MKV selezionati (singolo o batch automatico).
# • Calcola i preset dinamici per voce e LFE in base al formato sorgente o parametro manuale.
# • Applica l’EQ vocale “sartoriale” e, a scelta, il filtro surround psicoacustico (sonar)
# • Mantiene sottotitoli e, se richiesto, anche la traccia audio originale.
# • Gestisce interattivamente la sovrascrittura dei file di output.
# • Al termine, stampa un messaggio di riepilogo per l’intero batch.
# ───────────────────────────────────────────────────────────────────────────────────────────
for CUR_FILE in "${FILES[@]}"; do
  BASENAME=$(basename "$CUR_FILE" .mkv)
  OUT_SUFFIX=$([ "$SONAR_MODE" = sonar ] && echo "Sonar" || echo "Clean")
  OUT_FILE="${BASENAME}_AC3_${OUT_SUFFIX}.mkv"
  
  # Calcolo preset dinamici
  IFS=',' read -r VOICE_BOOST LFE_VOL <<< "$(get_dynamic_values "$PRESET")"
  VOICE_FILTER="$(get_voice_filter "$VOICE_BOOST")"
  LFE_FILTER="$(get_lfe_filter "$LFE_VOL")"
  if [ "$SONAR_MODE" = sonar ]; then
    SUR_FILTERS="$(get_sonar_surround)"
  else
    SUR_FILTERS="$(get_clean_surround)"
  fi

  # Logging intestazione
  info "────────────────────────────────────────────────────────────────────────────"
  info "➡  Input:  $CUR_FILE"
  info "➡  Output: $OUT_FILE"
  info "➡  Preset: $PRESET  |  Boost voce: ${VOICE_BOOST} dB  |  LFE: ${LFE_VOL} dB"
  info "➡  Surround gain: ${SUR_GAIN}  |  Modalità: ${SONAR_MODE}"
  info "────────────────────────────────────────────────────────────────────────────"

  # Costruzione catena filtri FFmpeg
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

  # Costruzione comando FFmpeg
  CMD=(ffmpeg $OVERWRITE_FLAG -hide_banner -nostdin -stats -loglevel warning \
       -i "$CUR_FILE" -filter_complex "$FILTER_COMPLEX" \
       -map 0:v:0 -c:v copy -map "[aout]" -c:a ac3 -b:a "$BITRATE" -ar 48000 -ac 6)

  # Mantieni sottotitoli (se presenti)
  if ffprobe -v quiet -select_streams s -show_entries stream=index -of csv=p=0 "$CUR_FILE" | grep -q .; then
    CMD+=(-map 0:s -c:s copy)
  fi

  # Mantieni audio originale (se richiesto)
  if [ "$KEEP_ORIG" = "si" ]; then
    CMD+=(-map 0:a:0 -c:a:1 copy -metadata:s:a:1 title="Original Audio" -disposition:a:1 0)
  fi

  # Metadata e output finale
  CMD+=(-metadata:s:a:0 title="AC3 5.1 ${OUT_SUFFIX}" -disposition:a:0 default "$OUT_FILE")

  info "➡  Avvio conversione → AC3 $BITRATE"
  "${CMD[@]}" && ok "Completato: $OUT_FILE" || err "Error: $OUT_FILE"

done

# Output finale batch
info "────────────────────────────────────────────────────────────────────────────"
ok   "Batch concluso [AC3 ottimizzato per AVR Kenwood RV6000 + KS1-300HT + SW40HT]"
info "────────────────────────────────────────────────────────────────────────────"


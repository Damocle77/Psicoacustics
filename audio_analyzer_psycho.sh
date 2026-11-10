#!/usr/bin/env bash
set -uo pipefail

# ╭─────────────────────────────────────────────────────────────────────────────────╮
# │   audio_analyzer_psycho.sh - (Stabile) Novembre 2026                            │
# │   By Sandro (D@mocle77) Sabbioni                                                │
# │                                                                                 │
# │   Sonda euristica per l'analisi offline di container multimediali 5.1.          │
# │   Misura il bilanciamento surround/centro e genera run_processing.sh            │
# │   per il processore aegis_sonar_wide_aura_voice_psycho.sh.                      │
# │                                                                                 │
# │   CLASSIFIER (RMS full-duration + banda voce, stesso passaggio):                │
# │     - DeltaSur = RMS(SL/SR) - RMS(FL/FR/FC)                                     │
# │     - DeltaFC  = RMS full-band(FC) - RMS full-band(FL/FR)                       │
# │     - VoiceDelta = RMS 250-5000 Hz(FC) - RMS 250-5000 Hz(FL/FR)                 │
# │     - VoiceMask  = RMS 250-5000 Hz(SL/SR) - RMS 250-5000 Hz(FC)                 │
# │     - Balance  = differenza assoluta SL/SR                                      │
# │     - Width    = RMS(SIDE) - RMS(MID)                                           │
# │                                                                                 │
# │   sicurezza -> evidenza temporale -> SONAR -> WIDE -> AURA -> AEGIS.            │
# │   Campione insufficiente/contraddittorio -> INCONCLUSIVE, nessun comando.       │
# │   Voce debole/mascherata e provenienza Atmos restano diagnostiche.              │
# │   Le misure RMS dei canali vengono raccolte in un solo passaggio FFmpeg.        │
# │   Decodifica AC3/EAC3 con DRC Dolby disattivata, come nel processore.           │
# │                                                                                 │
# │   VERDETTO STAGIONALE:                                                          │
# │   Verdetto: servono almeno 2/3 di consenso; parita'/spread > 4 dB -> MIXED.     │
# ╰─────────────────────────────────────────────────────────────────────────────────╯
# Note:
C_INFO="\033[0;36m[INFO]\033[0m"
C_WARN="\033[0;33m[WARNING]\033[0m"
C_MAPPING="\033[0;33m[MAPPING]\033[0m"
C_ERR="\033[0;31m[ERROR]\033[0m"
C_OK="\033[0;32m[OK]\033[0m"
C_PROGRESS="\033[1;35m[AVANZAMENTO]\033[0m"
C_ATMOS_FOUND="\033[0;38;5;208m[ATMOS]"
C_ATMOS_UNKNOWN="\033[0;38;5;208m[ATMOS]"

# Funzioni di log con colori: info, warn, err, ok. Usate per output coerente e facilmente distinguibile.
info(){ echo -e "${C_INFO} $*"; }
mapping(){ echo -e "${C_MAPPING} $*"; }
warn(){ echo -e "${C_WARN} $*"; }
err(){  echo -e "${C_ERR}  $*"; }
ok(){   echo -e "${C_OK}  $*"; }

# Controllo binari essenziali: ffmpeg, ffprobe, awk. Se uno manca, esco con errore. Importante per evitare errori a cascata quando si tenta di analizzare i file.
for _bin in ffmpeg ffprobe awk sha256sum stat realpath mktemp; do
  command -v "$_bin" &>/dev/null || { err "$_bin non trovato nel PATH"; exit 1; }
done

# Il PID resta nella shell principale, anche durante la misura audio.
ANALYZER_TMPDIR="$(mktemp -d)" || { err "Impossibile creare i temporanei"; exit 1; }
ANALYZER_FFMPEG_PID=""
BATCH_TMP=""
cleanup_analyzer() {
  if [[ -n "$ANALYZER_FFMPEG_PID" ]]; then
    kill "$ANALYZER_FFMPEG_PID" 2>/dev/null || true
    wait "$ANALYZER_FFMPEG_PID" 2>/dev/null || true
  fi
  [[ -z "$BATCH_TMP" ]] || rm -f -- "$BATCH_TMP"
  rm -rf -- "$ANALYZER_TMPDIR"
}
trap cleanup_analyzer EXIT
trap 'warn "Analisi interrotta; batch non aggiornato."; exit 130' INT
trap 'warn "Analisi terminata; batch non aggiornato."; exit 143' TERM

usage() {
  cat <<'USAGE'
───────────────────────────────────────────────────────────────────────────────────────────────
UTILIZZO:
  ./audio_analyzer_psycho.sh <codec> <keep> <bitrate> <run> <file|directory|"">
  ./audio_analyzer_psycho.sh --files <codec> <keep> <bitrate> <run> <file1> [file2...]

MODALITA' INPUT:
  file      : Analizza un singolo file multimediale.
  directory : Analizza tutti i file compatibili dentro la directory indicata.
  ""        : Analizza tutti i file compatibili nella cartella corrente.
  --files   : Analizza solo i file elencati esplicitamente dopo i parametri.
PARAMETRI:
  codec   : eac3    (Default) Codec per il batch file generato.
            ac3     Alternativa.
  keep    : no      (Default) Non conservare audio originale.
            si      Conserva audio originale nel file processato.
  bitrate : Default automatico: AC3  = 640k - EAC3 = 768k
  run     : si      (Default) Genera o aggiorna run_processing.sh.
            no      Esegue solo l'analisi senza creare/modificare il batch.
ESEMPI:
  ./audio_analyzer_psycho.sh eac3 no 768k si "film.mkv"
  ./audio_analyzer_psycho.sh eac3 no 768k si ""
  ./audio_analyzer_psycho.sh --files eac3 no 768k no ep1.mkv ep4.mkv

REGOLAZIONI AUTOMATICHE:
  Analyzer seleziona esclusivamente AEGIS, SONAR, WIDE o AURA come preset filtro.
  VOICEITA: preset esclusivamente manuale, da applicare nel processore.
───────────────────────────────────────────────────────────────────────────────────────────────
USAGE
  exit "${1:-1}"
}

# Senza argomenti o con -h/--help -> mostra usage
[[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage 0
# Modalità multi-file: se il primo argomento è --files, attivo la modalità multi-file e raccolgo i parametri specifici per questa modalità.
# CREATE_RUN accetta si|no e resta "si" per compatibilità con le versioni precedenti.
MULTI_FILES_MODE=false
MULTI_FILES=()
CREATE_RUN="si"

# Modalità --files: i primi 3 argomenti dopo --files sono codec, keep, bitrate.
# Il token successivo è interpretato come run solo se vale esattamente si oppure no;
# altrimenti viene trattato come primo filename, mantenendo la sintassi precedente.
if [[ "${1:-}" == "--files" ]]; then
  MULTI_FILES_MODE=true
  if (( $# < 5 )); then
    err "Uso --files non valido. Sintassi: ./audio_analyzer_psycho.sh --files <codec> <keep> <bitrate> [run] <file1> [file2 ...]"
    usage
  fi

  shift
  INPUT_ARG=""
  BATCH_CODEC="${1:-eac3}"
  BATCH_KEEP="${2:-no}"
  BATCH_BITRATE="${3:-}"
  shift 3

  if [[ "${1:-}" == "si" || "${1:-}" == "no" ]]; then
    CREATE_RUN="$1"
    shift
  fi

  MULTI_FILES=("$@")
else
  # Sintassi canonica: codec keep bitrate run input. Il primo token permette
  # di distinguerla senza ambiguita' dal vecchio ordine che iniziava col file.
  if (( $# == 5 )) && [[ "${1:-}" =~ ^(ac3|eac3)$ ]]; then
    BATCH_CODEC="${1:-eac3}"
    BATCH_KEEP="${2:-no}"
    BATCH_BITRATE="${3:-}"
    CREATE_RUN="${4:-si}"
    INPUT_ARG="${5:-}"
  else
    INPUT_ARG="${1:-}"
    BATCH_CODEC="${2:-eac3}"
    BATCH_KEEP="${3:-no}"
    BATCH_BITRATE="${4:-}"
    CREATE_RUN="${5:-si}"
  fi
fi
# Valori di default
[[ -z "$BATCH_BITRATE" ]] && {
  [[ "$BATCH_CODEC" = "ac3" ]] && BATCH_BITRATE="640k" || BATCH_BITRATE="768k"
}

# Validazione parametri: codec, keep, run, bitrate. Se un parametro non è valido, esco con errore e mostro usage.
case "$BATCH_CODEC" in ac3|eac3) ;; *) err "Codec '$BATCH_CODEC' non valido. Usa ac3 o eac3."; usage ;; esac
case "$BATCH_KEEP" in si|no) ;; *) err "Keep '$BATCH_KEEP' non valido. Usa si o no."; usage ;; esac
case "$CREATE_RUN" in si|no) ;; *) err "Run '$CREATE_RUN' non valido. Usa si o no."; usage ;; esac
[[ "$BATCH_BITRATE" =~ ^[0-9]+([kKmM])?$ ]] || { err "Bitrate '$BATCH_BITRATE' non valido. Es: 448k, 640k, 768k."; usage; }
[[ "$BATCH_BITRATE" =~ [kKmM]$ ]] || BATCH_BITRATE="${BATCH_BITRATE}k"

# Validazione allineata al processore: step da 64 kbps, AC3 fino a 640k,
# EAC3 fino a 768k. Evita di generare un run_processing.sh non eseguibile.
BITRATE_LC="${BATCH_BITRATE,,}"
if [[ "$BITRATE_LC" =~ ^([0-9]+)k$ ]]; then
  BITRATE_KBPS="${BASH_REMATCH[1]}"
elif [[ "$BITRATE_LC" =~ ^([0-9]+)m$ ]]; then
  BITRATE_KBPS="$(( ${BASH_REMATCH[1]} * 1000 ))"
else
  err "Bitrate non valido: $BATCH_BITRATE"
  usage
fi
BITRATE_MAX_KBPS=768
[[ "$BATCH_CODEC" == "ac3" ]] && BITRATE_MAX_KBPS=640
if (( BITRATE_KBPS < 256 || BITRATE_KBPS > BITRATE_MAX_KBPS || ((BITRATE_KBPS - 256) % 64) != 0 )); then
  err "Bitrate non consentito per $BATCH_CODEC: ${BITRATE_KBPS}k"
  if [[ "$BATCH_CODEC" == "ac3" ]]; then
    err "Consentiti: 256k, 320k, 384k, 448k, 512k, 576k, 640k"
  else
    err "Consentiti: 256k, 320k, 384k, 448k, 512k, 576k, 640k, 704k, 768k"
  fi
  exit 1
fi
BATCH_BITRATE="${BITRATE_KBPS}k"
printf '\n'
# Nota: non controllo se i file in --files esistono qui, lo faccio dopo per permettere di passare anche file parzialmente inesistenti senza bloccare tutto.
if [[ "$MULTI_FILES_MODE" == true ]]; then
  info "Metrica: CLASSIFIER RMS + VOICE BAND | Input: lista manuale (${#MULTI_FILES[@]} file) | Batch: ${BATCH_CODEC} / keep=${BATCH_KEEP} / ${BATCH_BITRATE} / run_processing=${CREATE_RUN}"
else
  info "Metrica: CLASSIFIER RMS + VOICE BAND | Batch: ${BATCH_CODEC} / keep=${BATCH_KEEP} / ${BATCH_BITRATE} / run_processing=${CREATE_RUN}"
fi
info "Livello di ascolto: regolare sull'AVR; nessun recupero loudness automatico."

# Cache persistente delle sole metriche. La chiave include percorso canonico,
# dimensione, mtime, stream e versione dello schema: un file modificato oppure
# un futuro cambio dell'algoritmo non puo' riutilizzare risultati obsoleti.
ANALYZER_CACHE="${ANALYZER_CACHE:-1}"
ANALYZER_CACHE_DIR="${ANALYZER_CACHE_DIR:-.clearvoice_analyzer_cache}"
ANALYZER_CACHE_SCHEMA="temporal-surround"
ANALYZER_PROGRESS_INTERVAL="${ANALYZER_PROGRESS_INTERVAL:-10}"

if ! [[ "$ANALYZER_CACHE" =~ ^[01]$ ]]; then
  err "ANALYZER_CACHE non valido: '$ANALYZER_CACHE' (usa 0 oppure 1)"
  exit 1
fi
if ! [[ "$ANALYZER_PROGRESS_INTERVAL" =~ ^[0-9]+$ ]] || \
   (( ANALYZER_PROGRESS_INTERVAL < 1 || ANALYZER_PROGRESS_INTERVAL > 60 )); then
  err "ANALYZER_PROGRESS_INTERVAL non valido: '$ANALYZER_PROGRESS_INTERVAL' (usa 1..60 secondi)"
  exit 1
fi
if [[ "$ANALYZER_CACHE" == "1" ]] && ! mkdir -p -- "$ANALYZER_CACHE_DIR" 2>/dev/null; then
  warn "Cache non disponibile in '$ANALYZER_CACHE_DIR': continuo senza cache."
  ANALYZER_CACHE="0"
fi

# Diagnostica LFE: soglie descrittive, senza correzioni automatiche.
# Finestre 0.5 s a 48 kHz; banda 20-120 Hz solo nel ramo analitico.
LFE_WINDOW_SAMPLES=24000
LFE_ACTIVE_GATE_DB=-60.0
LFE_RELATIVE_GATE_DB=30.0
LFE_MAINS_GATE_DB=-60.0
# Delta rispetto alla SOMMA delle energie dei cinque principali, non alla media.
# Le soglie di persistenza non sono target acustici/calibrazione del sub.
LFE_HOT_DB=-6.0
LFE_VERY_HOT_DB=-2.0

# Diagnostica bassi: proxy energetico, non simulazione del subwoofer/ambiente.
# 20-120 Hz di tutti i canali (LFE pesato +10 dB SOLO nella misura)
# rispetto a 250-5000 Hz dei cinque principali sulle stesse finestre.
BASS_REFERENCE_GATE_DB=-60.0
BASS_RELATIVE_GATE_DB=30.0
BASS_HOT_DB=6.0

# Width Mid/Side sotto questa soglia = surround collassati/stretti (poca separazione L/R).
# In quel caso, a parita' di Delta, una ricostruzione laterale (WIDE) rende di piu'
# di AURA/AEGIS. Non tocca SONAR (deficit estremo) con diagnostica voce separata.
WIDTH_WIDE_GATE="-7.0"

# Classificatore: l'energia full-band descrive la scena; la banda 250-5000 Hz
# descrive la prominenza del parlato senza far pesare eccessivamente bassi ed LFE.
SUR_FAKE_RMS_GATE="-65.0"
CENTER_FULL_SAFETY_GATE="-9.0" # FC full-band - FL/FR: anomalia severa
VOICE_DELTA_GATE="-4.5"        # FC voice-band - FL/FR voice-band
VOICE_MASK_GATE="-1.5"         # SUR voice-band - FC voice-band
VOICE_BAND_RMS_GATE="-70.0"    # sotto questo livello la metrica voce non e' valida
SUR_DOMINANT_GATE="1.0"        # SUR full-band - FL/FR/FC
DOMINANT_VOICE_DELTA_GATE="0.0" # dominanza SUR critica solo con FC non prominente
SONAR_DELTA_GATE="-13.0"
AURA_DELTA_GATE="-7.0"
SUR_BALANCE_WARN_DB="10.0"
PRESET_BORDERLINE_MARGIN="0.7"

# Classificatore: soglie empiriche/sperimentali, NON una calibrazione percettiva.
# Configurabili tramite ambiente. Le soglie storiche sopra restano riferimenti
# globali; quelle attive sono indipendenti, con valori iniziali conservativi.
TEMPORAL_WINDOW_SAMPLES=24000 # 500 ms, ramo full-band a 48 kHz
SUR_ACTIVITY_ABS_DB="${SUR_ACTIVITY_ABS_DB:--60}"
SUR_ACTIVITY_REL_DB="${SUR_ACTIVITY_REL_DB:-35}"
SUR_ACTIVITY_MIN_SECONDS="${SUR_ACTIVITY_MIN_SECONDS:-1}"
SUR_MAIN_MIN_DB="${SUR_MAIN_MIN_DB:--80}"
SUR_CORRELATION_GATE="${SUR_CORRELATION_GATE:-0.8}"
CLASSIFIER_SONAR_ACTIVE_DB="${CLASSIFIER_SONAR_ACTIVE_DB:--13}"
CLASSIFIER_AURA_ACTIVE_DB="${CLASSIFIER_AURA_ACTIVE_DB:--7}"
CLASSIFIER_WIDTH_ACTIVE_DB="${CLASSIFIER_WIDTH_ACTIVE_DB:--7}"
CLASSIFIER_HIGH_CORR_PERSISTENCE="${CLASSIFIER_HIGH_CORR_PERSISTENCE:-0.75}"
CLASSIFIER_MIN_VALID_WINDOWS="${CLASSIFIER_MIN_VALID_WINDOWS:-4}"
CLASSIFIER_MIN_VALID_SECONDS="${CLASSIFIER_MIN_VALID_SECONDS:-2}"
CLASSIFIER_HIGH_VALID_WINDOWS="${CLASSIFIER_HIGH_VALID_WINDOWS:-20}"
CLASSIFIER_HIGH_VALID_SECONDS="${CLASSIFIER_HIGH_VALID_SECONDS:-10}"
CLASSIFIER_VARIABILITY_DB="${CLASSIFIER_VARIABILITY_DB:-10}"
CLASSIFIER_MEDIAN_AGREEMENT_DB="${CLASSIFIER_MEDIAN_AGREEMENT_DB:-6}"
CLASSIFIER_GLOBAL_AGREEMENT_DB="${CLASSIFIER_GLOBAL_AGREEMENT_DB:-6}"
CLASSIFIER_RARE_ACTIVITY_RATIO="${CLASSIFIER_RARE_ACTIVITY_RATIO:-0.2}"
CLASSIFIER_HIGH_VALID_RATIO="${CLASSIFIER_HIGH_VALID_RATIO:-0.2}"
CLASSIFIER_CORRELATION_MARGIN="${CLASSIFIER_CORRELATION_MARGIN:-0.05}"
CLASSIFIER_PERSISTENCE_MARGIN="${CLASSIFIER_PERSISTENCE_MARGIN:-0.1}"
# Preferenza di classificazione, mai parametro del processore DSP.
# Default salvato nel file: on. Per preferire AEGIS, cambia :-on in :-off.
# Un eventuale valore esportato nellambiente continua ad avere precedenza.
SONAR_IMMERSIVE_PREFERENCE="${SONAR_IMMERSIVE_PREFERENCE:-on}"
case "$SONAR_IMMERSIVE_PREFERENCE" in
  off|on) ;;
  *) err "SONAR_IMMERSIVE_PREFERENCE non valido (usa off oppure on)"; exit 1 ;;
esac
# Idoneita immersiva sperimentale: tutte le condizioni devono concordare.
SONAR_IMMERSIVE_MIN_DELTA_DB="${SONAR_IMMERSIVE_MIN_DELTA_DB:--6}"
SONAR_IMMERSIVE_MAX_DELTA_DB="${SONAR_IMMERSIVE_MAX_DELTA_DB:-0}"
SONAR_IMMERSIVE_MIN_ACTIVITY_RATIO="${SONAR_IMMERSIVE_MIN_ACTIVITY_RATIO:-0.5}"
SONAR_IMMERSIVE_MIN_WIDTH_DB="${SONAR_IMMERSIVE_MIN_WIDTH_DB:--3}"
SONAR_IMMERSIVE_MAX_ABS_CORRELATION="${SONAR_IMMERSIVE_MAX_ABS_CORRELATION:-0.5}"
SONAR_IMMERSIVE_MAX_HIGH_CORR_PERSISTENCE="${SONAR_IMMERSIVE_MAX_HIGH_CORR_PERSISTENCE:-0.25}"
SONAR_IMMERSIVE_MIN_VALID_RATIO="${SONAR_IMMERSIVE_MIN_VALID_RATIO:-0.5}"
for _setting in SUR_ACTIVITY_ABS_DB SUR_ACTIVITY_REL_DB SUR_ACTIVITY_MIN_SECONDS \
  SUR_MAIN_MIN_DB SUR_CORRELATION_GATE CLASSIFIER_SONAR_ACTIVE_DB CLASSIFIER_AURA_ACTIVE_DB \
  CLASSIFIER_WIDTH_ACTIVE_DB CLASSIFIER_HIGH_CORR_PERSISTENCE CLASSIFIER_MIN_VALID_WINDOWS \
  CLASSIFIER_MIN_VALID_SECONDS CLASSIFIER_HIGH_VALID_WINDOWS CLASSIFIER_HIGH_VALID_SECONDS \
  CLASSIFIER_VARIABILITY_DB CLASSIFIER_MEDIAN_AGREEMENT_DB CLASSIFIER_GLOBAL_AGREEMENT_DB CLASSIFIER_RARE_ACTIVITY_RATIO \
  CLASSIFIER_HIGH_VALID_RATIO CLASSIFIER_CORRELATION_MARGIN CLASSIFIER_PERSISTENCE_MARGIN \
  SONAR_IMMERSIVE_MIN_DELTA_DB SONAR_IMMERSIVE_MAX_DELTA_DB \
  SONAR_IMMERSIVE_MIN_ACTIVITY_RATIO SONAR_IMMERSIVE_MIN_WIDTH_DB \
  SONAR_IMMERSIVE_MAX_ABS_CORRELATION SONAR_IMMERSIVE_MAX_HIGH_CORR_PERSISTENCE \
  SONAR_IMMERSIVE_MIN_VALID_RATIO; do
  [[ "${!_setting}" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || { err "Soglia non valida: $_setting"; exit 1; }
done
awk -v rel="$SUR_ACTIVITY_REL_DB" -v persist="$SUR_ACTIVITY_MIN_SECONDS" \
  -v corr="$SUR_CORRELATION_GATE" -v hp="$CLASSIFIER_HIGH_CORR_PERSISTENCE" \
  -v sg="$CLASSIFIER_SONAR_ACTIVE_DB" -v ag="$CLASSIFIER_AURA_ACTIVE_DB" \
  -v n="$CLASSIFIER_MIN_VALID_WINDOWS" -v sec="$CLASSIFIER_MIN_VALID_SECONDS" \
  -v hn="$CLASSIFIER_HIGH_VALID_WINDOWS" -v hs="$CLASSIFIER_HIGH_VALID_SECONDS" \
  -v vr="$CLASSIFIER_VARIABILITY_DB" -v ga="$CLASSIFIER_GLOBAL_AGREEMENT_DB" -v rare="$CLASSIFIER_RARE_ACTIVITY_RATIO" \
  -v hr="$CLASSIFIER_HIGH_VALID_RATIO" -v cm="$CLASSIFIER_CORRELATION_MARGIN" -v pm="$CLASSIFIER_PERSISTENCE_MARGIN" \
  -v median_agreement="$CLASSIFIER_MEDIAN_AGREEMENT_DB" \
  'BEGIN {exit !(rel>0 && persist>=0.5 && corr>0 && corr<=1 && hp>0 && hp<=1 &&
    sg<ag && n>=1 && n==int(n) && sec>0 && hn>=n && hn==int(hn) && hs>=sec &&
    vr>0 && ga>0 && rare>=0 && rare<=1 && hr>0 && hr<=1 && cm>=0 && cm<=1 &&
    pm>=0 && pm<=1 && median_agreement>0)}' || { err "Soglie del classificatore incoerenti"; exit 1; }
awk -v lo="$SONAR_IMMERSIVE_MIN_DELTA_DB" -v hi="$SONAR_IMMERSIVE_MAX_DELTA_DB" \
  -v activity="$SONAR_IMMERSIVE_MIN_ACTIVITY_RATIO" -v corr="$SONAR_IMMERSIVE_MAX_ABS_CORRELATION" \
  -v persistence="$SONAR_IMMERSIVE_MAX_HIGH_CORR_PERSISTENCE" -v valid="$SONAR_IMMERSIVE_MIN_VALID_RATIO" \
  'BEGIN {exit !(lo<hi && activity>0 && activity<=1 && corr>=0 && corr<1 &&
    persistence>=0 && persistence<1 && valid>0 && valid<=1)}' || { err "Soglie SONAR immersive incoerenti"; exit 1; }

# Atmos e marker: informazioni di provenienza, senza effetto sulle decisioni.
ATMOS_ORIGINAL_TITLE="EAC3 Atmos Original"
ATMOS_ORIGINAL_TITLE_LEGACY="EAC3 Atmos (Original)"

# Un picco globale uguale o inferiore a questa soglia viene considerato
# silenzio/quasi-silenzio e non deve produrre preset o comandi batch.
ANALYZER_SILENCE_PEAK_DB="-80.0"

info "Classifier: voice FC/front=${VOICE_DELTA_GATE} dB | voice SUR/FC=${VOICE_MASK_GATE} dB | FC safety=${CENTER_FULL_SAFETY_GATE} dB"
info "Preferenza immersiva SONAR: ${SONAR_IMMERSIVE_PREFERENCE} (solo classificazione)"
if [[ "$ANALYZER_CACHE" == "1" ]]; then
  info "Cache metriche: attiva ($ANALYZER_CACHE_DIR) | avanzamento ogni ${ANALYZER_PROGRESS_INTERVAL}s"
else
  info "Cache metriche: disattivata | avanzamento ogni ${ANALYZER_PROGRESS_INTERVAL}s"
fi

# Variabili globali per il verdetto stagionale
GLOBAL_METRIC_VALUES=()
GLOBAL_METRIC_FILES=()
GLOBAL_METRIC_PATHS=()
GLOBAL_LOUDNESS_VALUES=()
GLOBAL_WIDTH_VALUES=()
GLOBAL_LRA_VALUES=()
GLOBAL_PRESET_VALUES=()
GLOBAL_PRESET_FORCED_VALUES=()
GLOBAL_CENTER_DELTA_VALUES=()
GLOBAL_VOICE_DELTA_VALUES=()
GLOBAL_VOICE_MASK_VALUES=()
GLOBAL_BALANCE_VALUES=()
GLOBAL_CONFIDENCE_VALUES=()
GLOBAL_ALTERNATIVE_VALUES=()
GLOBAL_REASON_VALUES=()
GLOBAL_SOURCE_CLASS_VALUES=()
GLOBAL_SOURCE_EVIDENCE_VALUES=()
GLOBAL_MEASURED_PRESET_VALUES=()
GLOBAL_TEMPORAL_VALUES=()
GLOBAL_SELECTION_MODE_VALUES=()
GLOBAL_MEASUREMENT_CONFIDENCE_VALUES=()
GLOBAL_TEMPORAL_ASSESSMENT_VALUES=()

# ────────────────────────────────────────────────────────────────────────────────
# Raccolta file
# ────────────────────────────────────────────────────────────────────────────────
# Modalità raccolta file:
ANALYSIS_ERRORS=0
ANALYSIS_SKIPPED=0
FILES=()
if [[ "$MULTI_FILES_MODE" == true ]]; then
  (( ${#MULTI_FILES[@]} > 0 )) || { err "Modalita' --files richiesta ma nessun file passato."; exit 1; }
  # Controllo esistenza file in modalità --files: se un file non esiste, lo salto con warning ma continuo con gli altri (non blocco tutto).
  for f in "${MULTI_FILES[@]}"; do
    if [[ -f "$f" ]]; then
      FILES+=("$f")
    else
      warn "File inesistente, salto: $f"
      ((ANALYSIS_ERRORS+=1))
    fi
  done
elif [[ -z "$INPUT_ARG" ]]; then
  shopt -s nullglob
  FILES+=( *.mkv *.MKV *.mp4 *.MP4 *.avi *.AVI *.mka *.MKA \
           *.m2ts *.M2TS *.ac3 *.AC3 *.eac3 *.EAC3 \
           *.wav *.WAV *.flac *.FLAC )
  shopt -u nullglob
elif [[ -d "$INPUT_ARG" ]]; then
  shopt -s nullglob
  FILES+=( "$INPUT_ARG"/*.mkv "$INPUT_ARG"/*.MKV "$INPUT_ARG"/*.mp4 "$INPUT_ARG"/*.MP4 \
           "$INPUT_ARG"/*.avi "$INPUT_ARG"/*.AVI "$INPUT_ARG"/*.mka "$INPUT_ARG"/*.MKA \
           "$INPUT_ARG"/*.m2ts "$INPUT_ARG"/*.M2TS "$INPUT_ARG"/*.ac3 "$INPUT_ARG"/*.AC3 \
           "$INPUT_ARG"/*.eac3 "$INPUT_ARG"/*.EAC3 "$INPUT_ARG"/*.wav "$INPUT_ARG"/*.WAV \
           "$INPUT_ARG"/*.flac "$INPUT_ARG"/*.FLAC )
  shopt -u nullglob
elif [[ -f "$INPUT_ARG" ]]; then
  FILES+=("$INPUT_ARG")
else
  err "File o cartella inesistente: $INPUT_ARG"
  exit 1
fi

# Filtra i file già processati dal processore 
FILTERED_FILES=()
for f in "${FILES[@]}"; do
  case "$f" in
    *_AC3_Aegis.mkv|*_AC3_Sonar.mkv|*_AC3_Wide.mkv|*_AC3_Aura.mkv|*_AC3_Voice.mkv|*_AC3_Voiceita.mkv|\
    *_EAC3_Aegis.mkv|*_EAC3_Sonar.mkv|*_EAC3_Wide.mkv|*_EAC3_Aura.mkv|*_EAC3_Voice.mkv|*_EAC3_Voiceita.mkv)
      info "Skip output gia' processato: $f"
      continue
      ;;
    *)
      FILTERED_FILES+=("$f")
      ;;
  esac
done
FILES=("${FILTERED_FILES[@]}")
# Controllo finale: se dopo il filtro non ci sono file validi, esco con errore.
(( ${#FILES[@]} == 0 )) && { err "Nessun file valido trovato da analizzare."; exit 1; }

# ────────────────────────────────────────────────────────────────────────────────
# Selezione stream con sistema a punteggio allineato al processore.
# Entrano solo stream 5.1; tra questi prevalgono lingua italiana e flag default.
# Restituisce: "stream_index canali layout"
# ────────────────────────────────────────────────────────────────────────────────
pick_best_stream() {
  local f="$1"
  local raw_data
  raw_data=$(ffprobe -v error -select_streams a \
    -show_entries stream=index,channels,channel_layout:stream_disposition=default:stream_tags=language \
    -of csv=p=0 "$f" 2>/dev/null </dev/null) || return 1
  raw_data="${raw_data//$'\r'/}"
  # Punteggio identico al processore: lingua italiana, poi flag default.
  local best_idx=""
  local best_ch=0
  local best_layout="unknown"
  local best_score=-999999

  # Se ffprobe non restituisce dati, esco con warning e codice di errore.
  if [[ -n "$raw_data" ]]; then
    local lines
    mapfile -t lines <<< "$raw_data"
    for line in "${lines[@]}"; do
      [[ -z "$line" ]] && continue
      IFS=',' read -r idx ch layout def lang <<<"$line"
      ch="${ch:-0}"
      layout="${layout:-unknown}"
      def="${def:-0}"
      lang="${lang:-}"

      # L'analizzatore e il processore lavorano esclusivamente sul 5.1.
      [[ "$ch" =~ ^[0-9]+$ && "$ch" -eq 6 ]] || continue

      local score=1000
      [[ "$def" == "1" ]] && score=$((score + 200))
      [[ "${lang,,}" =~ ^it ]] && score=$((score + 300))
      # Se questo stream ha un punteggio migliore del migliore finora, lo seleziono come nuovo best.
      if (( score > best_score )); then
        best_score=$score
        best_idx=$idx
        best_ch=$ch
        best_layout=$layout
      fi
    done
  fi
  # Se non ho trovato stream validi, esco con warning e codice di errore.
  echo "$best_idx $best_ch $best_layout"
}

# Rileva una provenienza Atmos su qualunque stream audio del contenitore.
# Prova primaria: profilo ufficiale "Dolby Digital Plus + Dolby Atmos"
# dichiarato dal parser E-AC-3 di FFprobe. Il titolo stabile prodotto dal nostro
# pre-processore resta soltanto un fallback per container gia' preparati.
# Output: ATMOS|prova oppure UNKNOWN|prova.
detect_atmos_source() {
  local f="$1" audio_count audio_ord stream_meta codec profile title
  local marker_found=false marker_stream=""

  # Cattura nativa senza pipeline: evita pipe FFprobe/MSYS pendenti su Windows.
  audio_count=$(ffprobe -v error -select_streams a -show_entries stream=index \
    -of csv=p=0 "$f" 2>/dev/null </dev/null) || return 1
  audio_count="${audio_count//$'\r'/}"
  audio_count=$(awk 'NF { n++ } END { print n+0 }' <<<"$audio_count")

  for (( audio_ord=0; audio_ord<audio_count; audio_ord++ )); do
    stream_meta=$(ffprobe -v error -select_streams "a:${audio_ord}" \
      -show_entries stream=codec_name,profile:stream_tags=title \
      -of default=nw=1 "$f" 2>/dev/null </dev/null || true)
    stream_meta="${stream_meta//$'\r'/}"
    codec=$(printf '%s\n' "$stream_meta" | awk -F= '$1=="codec_name" { print $2; exit }')
    profile=$(printf '%s\n' "$stream_meta" | awk -F= '$1=="profile" { sub(/^[^=]*=/,""); print; exit }')
    title=$(printf '%s\n' "$stream_meta" | awk -F= '$1=="TAG:title" { sub(/^[^=]*=/,""); print; exit }')

    if [[ "${title,,}" == "${ATMOS_ORIGINAL_TITLE,,}" || \
          "${title,,}" == "${ATMOS_ORIGINAL_TITLE_LEGACY,,}" ]]; then
      marker_found=true
      marker_stream="$audio_ord"
    fi

    [[ "$codec" == "eac3" ]] || continue

    if [[ "${profile,,}" == *"atmos"* ]]; then
      printf 'ATMOS|profilo FFprobe sullo stream audio %s\n' "$audio_ord"
      return 0
    fi

  done

  if [[ "$marker_found" == true ]]; then
    printf 'ATMOS|marker affidabile sullo stream audio %s\n' "$marker_stream"
  else
    printf 'UNKNOWN|nessun profilo compatibile\n'
  fi
}

# ──────────────────────────────────────────────────────────────────────────────────
# Colore ANSI associato a un preset (per display coerente quando si parte dal nome).
# ──────────────────────────────────────────────────────────────────────────────────
# Controllo robusto: se il preset non è riconosciuto, restituisco un colore di default (bianco). Evita errori di visualizzazione e permette di gestire casi in cui il preset non è stato classificato correttamente.
preset_color() {
  case "$1" in
    SONAR) echo "\033[1;31m" ;;       # rosso
    AEGIS) echo "\033[38;5;208m" ;;   # arancione (ANSI 256 colori)
    WIDE)  echo "\033[1;32m" ;;       # verde
    AURA)  echo "\033[1;35m" ;;       # viola/magenta
    *)     echo "\033[1;37m" ;;       # bianco
  esac
}

# Classificatore automatico: quattro preset spaziali; la voce resta diagnostica.
# VOICEITA richiede una scelta manuale: le metriche non misurano l'intelligibilita'.
# Resta esclusivamente manuale, mai primario/alternativo/fallback.
# Output: PRESET|COLORE|CONFIDENCE|ALTERNATIVE|REASON|SELECTION_MODE|MEASUREMENT_CONFIDENCE|TEMPORAL_ASSESSMENT
classify_preset() {
  local ds="$1" df="$2" dv="$3" vm="$4" w="$5" temporal="$6" balance="${7:-0}" decision preset rest
  decision=$(awk -F'|' -v ds="$ds" -v df="$df" -v dv="$dv" -v vm="$vm" -v w="$w" \
    -v sg="$CLASSIFIER_SONAR_ACTIVE_DB" -v ag="$CLASSIFIER_AURA_ACTIVE_DB" -v wg="$CLASSIFIER_WIDTH_ACTIVE_DB" \
    -v globalwg="$WIDTH_WIDE_GATE" -v cg="$SUR_CORRELATION_GATE" -v hp="$CLASSIFIER_HIGH_CORR_PERSISTENCE" \
    -v minn="$CLASSIFIER_MIN_VALID_WINDOWS" -v mins="$CLASSIFIER_MIN_VALID_SECONDS" \
    -v highn="$CLASSIFIER_HIGH_VALID_WINDOWS" -v highs="$CLASSIFIER_HIGH_VALID_SECONDS" \
    -v variability="$CLASSIFIER_VARIABILITY_DB" -v agreement="$CLASSIFIER_GLOBAL_AGREEMENT_DB" \
    -v median_agreement="$CLASSIFIER_MEDIAN_AGREEMENT_DB" \
    -v rare="$CLASSIFIER_RARE_ACTIVITY_RATIO" -v margin="$PRESET_BORDERLINE_MARGIN" \
    -v highratio="$CLASSIFIER_HIGH_VALID_RATIO" -v cmargin="$CLASSIFIER_CORRELATION_MARGIN" -v pmargin="$CLASSIFIER_PERSISTENCE_MARGIN" \
    -v preference="$SONAR_IMMERSIVE_PREFERENCE" \
    -v imin="$SONAR_IMMERSIVE_MIN_DELTA_DB" -v imax="$SONAR_IMMERSIVE_MAX_DELTA_DB" \
    -v iactivity="$SONAR_IMMERSIVE_MIN_ACTIVITY_RATIO" -v iwidth="$SONAR_IMMERSIVE_MIN_WIDTH_DB" \
    -v icorr="$SONAR_IMMERSIVE_MAX_ABS_CORRELATION" -v ipersistence="$SONAR_IMMERSIVE_MAX_HIGH_CORR_PERSISTENCE" \
    -v iratio="$SONAR_IMMERSIVE_MIN_VALID_RATIO" -v balance="$balance" -v balancegate="$SUR_BALANCE_WARN_DB" \
    -v fcgate="$CENTER_FULL_SAFETY_GATE" -v vgate="$VOICE_DELTA_GATE" \
    -v vmaskgate="$VOICE_MASK_GATE" -v domgate="$SUR_DOMINANT_GATE" \
    -v domvoicegate="$DOMINANT_VOICE_DELTA_GATE" '
    function finite(v) {return v ~ /^-?[0-9]+([.][0-9]+)?$/}
    function abs(v) {return v<0?-v:v}
    {
      activity=$1; active=$2; p10=$3; p50=$4; p90=$5; aw=$6; corr=$7; persistence=$8;
      valid=$10; seconds=$13; bilateral=$14; corrn=$16;
      preset="INCONCLUSIVE"; confidence="BASSA"; alt="-"; mode="INCONCLUSIVE";
      measurement_confidence="BASSA"; temporal_assessment="INSUFFICIENT"; boundary_resolved=0; median_resolved=0;
      reason="evidenza temporale insufficiente: finestre valide=" valid ", secondi=" seconds;
      if (valid>=minn && seconds>=mins && finite(active) && finite(p10) && finite(p50) && finite(p90)) {
        # Affidabilita del campione e disponibilita delle statistiche: non
        # dipendono dalla dinamica o dalla classe energetica.
        if (bilateral>=minn && corrn>=minn && $17>=mins && aw!="N/A" && finite(corr)) {
          measurement_confidence="MEDIA";
          if (valid>=highn && seconds>=highs && $11>=highratio &&
              bilateral>=highn && $15>=highs && corrn>=highn && $17>=highs)
            measurement_confidence="ALTA";
        }
        central_conflict=(abs(active-p50)>median_agreement);
        # Tolleranza gia prevista per le decisioni vicine alle soglie.
        # Il confronto include la precisione di serializzazione (sei decimali).
        near_aura_boundary=(!central_conflict && abs(active-ag)<=margin+0.000001 &&
          abs(p50-ag)<=margin+0.000001 && abs(active-p50)<=margin+0.000001);
        temporal_assessment=(p90-p10>=variability?"VARIABLE_COHERENT":"STABLE");
        confidence="MEDIA";
        narrow=(w<globalwg && (aw=="-inf" || (finite(aw) && aw<wg)) &&
                finite(corr) && corr>=cg && finite(persistence) && persistence>=hp &&
                bilateral>=minn && corrn>=minn && $17>=mins);
        severe=(active<sg && p50<sg);
        moderate=(active<ag && p50<ag);
        if (severe) {preset="SONAR"; reason="deficit anche durante gli eventi: ActiveDeltaSur=" active ", P50=" p50;}
        else if (narrow) {preset="WIDE"; reason="separazione persistentemente ridotta: Width=" w ", ActiveWidth=" aw ", correlazione=" corr ", persistenza=" persistence;}
        else if (moderate) {preset="AURA"; reason="arretramento moderato durante gli eventi: ActiveDeltaSur=" active ", P50=" p50;}
        else if (active>=ag && p50>=ag) {
          preset="AEGIS";
          reason=(activity<rare?"eventi rari ma energeticamente adeguati":"energia surround adeguata durante gli eventi");
          reason=reason ": Activity=" activity ", ActiveDeltaSur=" active ", P50=" p50;
        } else if (near_aura_boundary) {
          # Pareggio deterministico: la media energetica aggregata decide il lato.
          preset=(active<ag?"AURA":"AEGIS"); reason="energia vicina alla soglia AURA/AEGIS";
        } else if (measurement_confidence=="ALTA" && !central_conflict &&
                   active>=ag && active<=ag+margin+0.000001 &&
                   p50<ag-margin && p50>=sg && abs(active-ds)<agreement) {
          # Aggregato appena sul lato AEGIS, mediana nella fascia moderata:
          # scelta empirica AURA con alternativa, mantenendo il disaccordo.
          preset="AURA"; median_resolved=1;
          reason="mediana AURA con aggregato vicino al confine AEGIS: ActiveDeltaSur=" active ", P50=" p50;
        } else {confidence="BASSA"; reason="energia aggregata e mediana discordanti oltre il margine borderline: ActiveDeltaSur=" active ", P50=" p50;}
        if (preset!="INCONCLUSIVE") {
          mode=(preset=="SONAR"?"IMMERSIVE_RECOVERY":"CONSERVATIVE");
          if ((preset=="AURA" || preset=="AEGIS") && near_aura_boundary) {
            boundary_resolved=1; confidence="BASSA"; temporal_assessment="BORDERLINE";
            alt=(preset=="AURA"?"AEGIS":"AURA");
            reason=reason "; confine AURA/AEGIS entro " margin " dB: ActiveDeltaSur=" active ", P50=" p50 "; scelta dal rapporto energetico aggregato";
          }
          # Lo spread da solo descrive dinamica cinematografica, non incertezza.
          # Conta soltanto se la distribuzione attraversa il confine decisivo.
          distribution_conflict=((preset=="SONAR" && p90>=sg+margin) ||
            (preset=="AURA" && (p10<sg-margin || p90>=ag+margin)) ||
            (preset=="AEGIS" && p10<ag-margin && (central_conflict || p50<ag+margin)));
          unstable=(p90-p10>=variability && distribution_conflict && !boundary_resolved);
          if (!boundary_resolved && valid>=highn && seconds>=highs && $11>=highratio && !unstable &&
              abs(active-ds)<agreement && bilateral>=minn && corrn>=minn) confidence="ALTA";
          if (!boundary_resolved && activity<rare && preset=="AEGIS" && ds<ag) confidence="MEDIA";
          if (unstable) {
            # Code in fasce diverse: VARIABLE se il centro concorda; MIXED
            # per riferimenti discordanti. Nessuna etichetta giudica il mix.
            confidence="BASSA"; temporal_assessment=(central_conflict?"MIXED":"VARIABLE");
            if (central_conflict) reason=reason "; distribuzione temporale ampia con centro energetico discordante";
            else if (preset=="AURA" && median_resolved) reason=reason "; distribuzione ampia; scelta dalla mediana con aggregato vicino alla soglia";
            else if (preset=="AURA") reason=reason "; P10/P90 attraversano fasce energetiche severe o equilibrate; aggregato e mediana indicano AURA";
            else if (preset=="SONAR") reason=reason "; deficit surround severo con eventi piu presenti nella coda P90";
            else reason=reason "; distribuzione temporale attraversa il confine AURA/AEGIS con mediana vicina alla soglia";
          }
          if (central_conflict && preset!="WIDE") {
            confidence="BASSA"; temporal_assessment="MIXED";
            reason=reason "; ActiveDeltaSur e P50 discordanti oltre " median_agreement " dB";
          }
          if (abs(active-ds)>=agreement) {
            if (!(activity<rare && preset=="AEGIS" && active>=ag && p50>=ag)) {
              confidence="BASSA"; temporal_assessment="MIXED";
            }
            reason=reason "; divergenza globale/attivo";
          }
          if (severe && narrow) {confidence="BASSA"; alt="WIDE"; reason=reason "; anche scena stretta (priorita SONAR)";}
          else if (!boundary_resolved && abs(active-sg)<=margin) {confidence="BASSA"; alt=(preset=="SONAR"?"AURA":"SONAR");}
          else if (!boundary_resolved && abs(active-ag)<=margin) {confidence="BASSA"; alt=(preset=="AURA"?"AEGIS":"AURA");}
          else if (!boundary_resolved && finite(aw) && abs(aw-wg)<=margin && corrn>=minn) {confidence="BASSA"; alt=(preset=="WIDE"?(moderate?"AURA":"AEGIS"):"WIDE");}
          if (preset=="WIDE" && (corr-cg<=cmargin || persistence-hp<=pmargin ||
              globalwg-w<=margin)) {
            confidence="BASSA"; alt=(moderate?"AURA":"AEGIS"); reason=reason "; borderline persistenza/correlazione/width globale";
          }
          if (bilateral<minn || corrn<minn || $17<mins) {
            confidence="BASSA"; reason=reason "; campione spaziale bilaterale insufficiente";
          }
          if (finite(corr) && corr< -cg) {confidence="BASSA"; reason=reason "; opposizione di fase: verificare manualmente";}
          if (!narrow && (w<globalwg || aw=="-inf" || (finite(aw) && aw<wg))) {
            confidence="BASSA"; reason=reason "; indizi di width non confermati dalla persistenza";
          }
          if (median_resolved) {
            confidence="BASSA"; temporal_assessment="MIXED"; alt="AEGIS";
          }
        } else temporal_assessment="MIXED";
      }
      if (df<fcgate) reason=reason "; centro full-band anormalmente debole";
      if (finite(dv) && dv<vgate) reason=reason "; voce centrale debole (250-5000 Hz)";
      if (finite(vm) && vm>vmaskgate) reason=reason "; banda voce mascherata dai surround";
      if (finite(dv) && ds>domgate && dv<domvoicegate) reason=reason "; surround dominanti con voce non prominente";
      # Il ramo immersivo viene valutato SOLO dopo la scelta energetica/spaziale.
      # Nessun dato Atmos/codec entra nel classificatore; nessuna stima di altezza.
      immersive_eligible=(preset=="AEGIS" && !boundary_resolved && confidence!="BASSA" && measurement_confidence!="BASSA" &&
        active>=imin && active<=imax && p50>=ag+margin && !central_conflict && p90<=domgate &&
        activity>=iactivity && $11>=iratio && valid>=highn && seconds>=highs &&
        finite(aw) && aw>=iwidth && finite(corr) && abs(corr)<=icorr &&
        finite(persistence) && persistence<=ipersistence &&
        $9>0 && bilateral/$9>=iratio && corrn/$9>=iratio && $15>=highs && $17>=highs &&
        finite(balance) && balance<balancegate-margin && df>=fcgate &&
        (!finite(dv) || dv>=vgate) && (!finite(vm) || vm<=vmaskgate));
      if (preference=="on" && immersive_eligible) {
        preset="SONAR"; mode="IMMERSIVE_PREFERENCE"; confidence="MEDIA"; alt="AEGIS";
        reason="scena surround sufficientemente presente e separata: ActiveDeltaSur=" active ", Activity=" activity ", ActiveWidth=" aw ", correlazione=" corr ", persistenza=" persistence ", ValidRatio=" $11 ", P10/P50/P90=" p10 "/" p50 "/" p90;
        reason=reason "; preferenza psicoacustica immersiva SONAR abilitata; nessuna ricostruzione di oggetti Atmos o canali fisici di altezza; superiorita percettiva non misurata";
        if (temporal_assessment=="VARIABLE_COHERENT") reason=reason "; variabilita energetica con mediana e rapporto aggregato coerenti; P10 descrittivo";
      } else if (immersive_eligible) {
        alt="SONAR"; reason=reason "; candidatura immersiva SONAR idonea; preferenza off, priorita AEGIS";
      } else if (preference=="on" && preset=="AEGIS") {
        if (boundary_resolved) reason=reason "; candidatura immersiva esclusa per scelta energetica borderline";
        if (finite(aw) && aw<iwidth) reason=reason "; candidatura immersiva non confermata: ActiveWidth=" aw " dB sotto " iwidth " dB";
        if (finite(p90) && p90>domgate) reason=reason "; candidatura immersiva non confermata: P90=" p90 " dB oltre " domgate " dB";
      }
      printf "%s|%s|%s|%s|%s|%s|%s",preset,confidence,alt,reason,mode,measurement_confidence,temporal_assessment;
    }' <<<"$temporal") || return 1
  preset="${decision%%|*}"; rest="${decision#*|}"
  printf '%s|%s|%s' "$preset" "$(preset_color "$preset")" "$rest"
}

is_finite_db() {
  [[ "$1" =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

analysis_cache_file() {
  local f="$1" stream="$2" canonical identity cache_hash
  [[ "$ANALYZER_CACHE" == "1" ]] || return 1

  canonical="$(realpath -- "$f" 2>/dev/null)" || return 1
  identity="$(stat -c '%s|%y' -- "$f" 2>/dev/null)" || return 1
  cache_hash="$(printf '%s\n' \
    "${ANALYZER_CACHE_SCHEMA}|${canonical}|${identity}|stream=${stream}|lfe=${LFE_WINDOW_SAMPLES},${LFE_ACTIVE_GATE_DB},${LFE_RELATIVE_GATE_DB},${LFE_MAINS_GATE_DB},${LFE_HOT_DB},${LFE_VERY_HOT_DB}|bass=${BASS_REFERENCE_GATE_DB},${BASS_RELATIVE_GATE_DB},${BASS_HOT_DB}|sur=${TEMPORAL_WINDOW_SAMPLES},${SUR_ACTIVITY_ABS_DB},${SUR_ACTIVITY_REL_DB},${SUR_ACTIVITY_MIN_SECONDS},${SUR_MAIN_MIN_DB},${SUR_CORRELATION_GATE}" | \
    sha256sum | awk '{print $1}')"
  [[ "$cache_hash" =~ ^[0-9a-fA-F]{64}$ ]] || return 1
  printf '%s/%s.metrics\n' "$ANALYZER_CACHE_DIR" "$cache_hash"
}

is_valid_metrics_record() {
  local record="$1" value i
  local -a fields
  [[ -n "$record" && "$record" != *$'\n'* && "$record" != *$'\r'* ]] || return 1
  IFS='|' read -r -a fields <<<"$record"
  [[ ${#fields[@]} -eq 50 ]] || return 1
  for i in 0 1; do
    [[ -z "${fields[$i]}" ]] || is_finite_db "${fields[$i]}" || return 1
  done
  for i in {32..49}; do
    value="${fields[$i]}"
    case "$i:$value" in
      33:N/A|34:N/A|35:N/A|36:N/A|37:N/A|37:-inf|37:+inf|38:N/A|39:N/A|49:-inf) ;;
      *) is_finite_db "$value" || return 1 ;;
    esac
  done
  awk -F'|' '
    function count(v) {return v>=0 && v==int(v)}
    function fraction(v) {return v>=0 && v<=1}
    function abs(v) {return v<0?-v:v}
    {
      if(!fraction($33) || !count($41) || $41<1 || !count($42) || $42>$41 ||
         !fraction($43) || abs($43-$42/$41)>0.000002 || $44<=0 || $45<0 || $45>$44 ||
         !count($46) || $46>$41 || $47<0 || $47>$44 ||
         !count($48) || $48>$46 || $49<0 || $49>$47 ||
         ($39!="N/A" && ($39< -1 || $39>1)) || ($40!="N/A" && !fraction($40)) ||
         (($42==0)!=($34=="N/A")) || (($42==0)!=($35=="N/A")) ||
         (($42==0)!=($36=="N/A")) || (($42==0)!=($37=="N/A")) ||
         (($46==0)!=($38=="N/A")) || (($48==0)!=($39=="N/A")) ||
         (($48==0)!=($40=="N/A")) || ($42>0 && ($35>$36 || $36>$37)) ||
         ($42>0 && $45<=0) || ($46>0 && $47<=0) || ($48>0 && $49<=0) ||
         $45>$33*$44+0.000001*$44+0.000002 ||
         $44>$41*0.5+0.000001 || $44<=($41-1)*0.5) exit 1
    }' <<<"$record" || return 1

  # I/LRA possono essere vuoti su materiale troppo breve; le metriche di
  # livello (comprese LFE) devono essere numeriche oppure -inf.
  for i in {2..19}; do
    value="${fields[$i]}"
    [[ "$value" == "-inf" ]] || is_finite_db "$value" || return 1
  done
  for i in {20..22}; do
    [[ "${fields[$i]}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  done
  for i in {25..28}; do
    [[ "${fields[$i]}" == "-inf" ]] || is_finite_db "${fields[$i]}" || return 1
  done
  for i in {29..31}; do
    [[ "${fields[$i]}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  done
  for i in {23..24}; do
    [[ "${fields[$i]}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  done
  awk -v seconds="${fields[20]}" -v ratio="${fields[21]}" -v count="${fields[22]}" \
    -v persistence="${fields[29]}" -v bass_seconds="${fields[30]}" -v bass_ratio="${fields[31]}" \
    -v hot_p="${fields[23]}" -v very_hot_p="${fields[24]}" \
    'BEGIN { exit !(hot_p >= 0 && hot_p <= 1 && very_hot_p >= 0 && very_hot_p <= hot_p &&
      seconds >= 0 && ratio >= 0 && ratio <= 1 && count > 0 && count == int(count) &&
      persistence >= 0 && persistence <= 1 && bass_seconds >= 0 && bass_ratio >= 0 && bass_ratio <= 1) }'
}

store_metrics_cache() {
  local cache_file="$1" record="$2" cache_tmp
  [[ -n "$cache_file" ]] || return 1
  cache_tmp="${cache_file}.tmp.$$.${RANDOM}"
  if ( umask 077; printf '%s\n' "$record" >"$cache_tmp" ) && \
     mv -f -- "$cache_tmp" "$cache_file"; then
    return 0
  fi
  rm -f -- "$cache_tmp" 2>/dev/null || true
  return 1
}

# Width Mid/Side: descrizione delle metriche surround.
width_to_desc() {
  local w="$1"
  [[ -n "$w" && "$w" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || { echo "N/A"; return; }
  # Soglie empiriche per descrivere la separazione L/R dei surround: se width è molto negativo, i surround sono simili o collassati -> "collassato". Se width è moderatamente negativo, i surround sono stretti -> "stretto". Se width è vicino a 0 o positivo, i surround hanno buona separazione -> "medio" o "largo". Queste soglie sono indicative e possono essere regolate in base all'ascolto.
  if awk -v w="$w" 'BEGIN { exit !(w < -12.0) }'; then
    echo "collassato"
  elif awk -v w="$w" 'BEGIN { exit !(w < -7.0) }'; then
    echo "stretto"
  elif awk -v w="$w" 'BEGIN { exit !(w < -3.0) }'; then
    echo "medio"
  else
    echo "largo"
  fi
}

# Raccoglie finestre sincronizzate: LFE e somma energetica FL/FR/FC/SL/SR.
# P95: istogramma a 0.1 dB, pesato per campioni; nessun sort esterno/GNU asort.
# Output: active RMS|P95|raw peak|bass mains|delta|secondi attivi|frazione attiva|finestre
#         |persistenza HOT|VERY_HOT
measure_lfe_windows() {
  awk -v gate="$LFE_ACTIVE_GATE_DB" -v relative="$LFE_RELATIVE_GATE_DB" -v win="$LFE_WINDOW_SAMPLES" \
    -v main_gate="$LFE_MAINS_GATE_DB" -v hot="$LFE_HOT_DB" -v very_hot="$LFE_VERY_HOT_DB" \
    '
    function finite(v) { return v ~ /^-?[0-9]+([.][0-9]+)?$/ }
    function db(p) { return 10*log(p)/log(10) }
    function flush(    c,p) {
      if (!frame) return
      if (samples <= 0 || samples > win) bad=1
      for(c=1;c<=6;c++) if (!(c in rms) || (rms[c]!="-inf" && !finite(rms[c]))) bad=1
      if (bad) return
      n++; weights[n]=samples; total+=samples
      lf[n]=rms[4]; mains[n]=0
      for(c=1;c<=6;c++) if(c!=4 && rms[c]!="-inf") mains[n]+=10^(rms[c]/10)
      if (finite(lf[n]) && (!have_max || lf[n]+0 > maximum)) {maximum=lf[n]+0; have_max=1}
    }
    index($0,"[astats@full ") {
      if ($0 ~ /Channel:/) ch=$NF
      else if(ch==4 && $0 ~ /Peak level dB:/) peak=$NF
    }
    index($0,"[ametadata@lfe_windows ") {
      if ($0 ~ /frame:/) {
        flush(); frame=1; samples=0
        for(c in rms) delete rms[c]
      } else if ($0 ~ /lavfi.astats.[1-6].RMS_level=/) {
        key=$0; sub(/^.*lavfi.astats./,"",key); split(key,parts,"."); c=parts[1]
        value=$0; sub(/^.*=/,"",value); rms[c]=value
      } else if ($0 ~ /lavfi.astats.Overall.Number_of_samples=/) {
        value=$0; sub(/^.*=/,"",value)
        if (!finite(value)) bad=1
        samples=value+0
      }
    }
    END {
      flush()
      if(bad || !n || (peak!="-inf" && !finite(peak))) exit 1
      threshold=gate
      if(have_max && maximum-relative > threshold) threshold=maximum-relative
      for(i=1;i<=n;i++) if(finite(lf[i]) && lf[i]+0 > threshold) {
        w=weights[i]; active+=w; lp+=10^(lf[i]/10)*w; mp+=mains[i]*w
        # Finestre senza bassi mains affidabili non confermano un eccesso.
        # Restano nel denominatore: persistenza sul TOTALE del tempo LFE attivo.
        if(mains[i]>0 && db(mains[i])>main_gate) {
          d=lf[i]-db(mains[i])
          if(d>hot) hot_samples+=w
          if(d>very_hot) very_hot_samples+=w
        }
        # Arrotondamento per difetto anche per valori negativi; risoluzione 0.1 dB.
        bin=int(lf[i]*10); if(bin > lf[i]*10) bin--
        hist[bin]+=w
        if(!have_bin || bin<lo) lo=bin
        if(!have_bin || bin>hi) hi=bin
        have_bin=1
      }
      if(!active) {printf "-inf|-inf|%s|-inf|-inf|0.000|0.000000|%d|0.000000|0.000000\n",peak,n; exit}
      for(b=lo;b<=hi;b++) {cumulative+=hist[b]; if(cumulative >= .95*active) {p95=b/10; break}}
      l=db(lp/active)
      if(mp>0) printf "%.3f|%.1f|%s|%.3f|%.3f",l,p95,peak,db(mp/active),l-db(mp/active)
      else printf "%.3f|%.1f|%s|-inf|-inf",l,p95,peak
      printf "|%.3f|%.6f|%d",active/48000,active/total,n
      printf "|%.6f|%.6f\n",hot_samples/active,very_hot_samples/active
    }
  ' "$1"
}

# Incrocia per indice e campioni i due rami a 48 kHz, senza dipendere
# dall'ordine delle righe FFmpeg. Nessuna seconda decodifica.
# Output: bass RMS|reference RMS|delta|P95 delta|persistenza|secondi|frazione attiva
measure_bass_windows() {
  awk -v gate="$BASS_REFERENCE_GATE_DB" -v relative="$BASS_RELATIVE_GATE_DB" -v hot="$BASS_HOT_DB" -v win="$LFE_WINDOW_SAMPLES" '
    function finite(v) { return v ~ /^-?[0-9]+([.][0-9]+)?$/ }
    function db(v) { return 10*log(v)/log(10) }
    index($0,"[ametadata@lfe_windows ") || index($0,"[ametadata@bass_ref ") {
      branch=(index($0,"[ametadata@bass_ref ")?2:1)
      if($0 ~ /frame:/) {
        value=$0; sub(/^.*frame:/,"",value); sub(/[[:space:]].*$/,"",value)
        if(value !~ /^[0-9]+$/) {bad=1; next}
        frame[branch]=value+1
        if(frame[branch]>n[branch]) n[branch]=frame[branch]
      } else if($0 ~ /lavfi.astats.[1-6].RMS_level=/) {
        key=$0; sub(/^.*lavfi.astats./,"",key); split(key,parts,"."); c=parts[1]
        value=$0; sub(/^.*=/,"",value)
        if(value!="-inf" && !finite(value)) bad=1
        rms[branch,frame[branch],c]=value
      } else if($0 ~ /lavfi.astats.Overall.Number_of_samples=/) {
        value=$0; sub(/^.*=/,"",value)
        if(!finite(value) || value+0<=0 || value+0>win+0) bad=1
        samples[branch,frame[branch]]=value+0
      }
    }
    END {
      if(bad || n[1]<=0 || n[1]!=n[2]) exit 1
      for(i=1;i<=n[1];i++) {
        if(samples[1,i]<=0 || samples[1,i]!=samples[2,i]) exit 1
        total+=samples[1,i]
        for(c=1;c<=6;c++) {
          if(!((1,i,c) in rms) || !((2,i,c) in rms)) exit 1
          if(rms[1,i,c]!="-inf") bass[i]+=(c==4?10:1)*10^(rms[1,i,c]/10)
          if(c!=4 && rms[2,i,c]!="-inf") ref[i]+=10^(rms[2,i,c]/10)
        }
        if(ref[i]>0 && (!have_max || db(ref[i])>maximum)) {maximum=db(ref[i]); have_max=1}
      }
      threshold=gate
      if(have_max && maximum-relative>threshold) threshold=maximum-relative
      for(i=1;i<=n[1];i++) if(ref[i]>0 && db(ref[i])>threshold) {
        w=samples[1,i]; active+=w; bp+=bass[i]*w; rp+=ref[i]*w
        delta=(bass[i]>0?db(bass[i]/ref[i]):-120)
        if(delta>hot) persistent+=w
        bin=int(delta*10); if(bin>delta*10) bin--
        hist[bin]+=w
        if(!have_bin || bin<lo) lo=bin
        if(!have_bin || bin>hi) hi=bin
        have_bin=1
      }
      if(!active || bp<=0) {printf "-inf|-inf|-inf|-inf|0.000000|%.3f|%.6f\n",active/48000,active/total; exit}
      for(b=lo;b<=hi;b++) {cumulative+=hist[b]; if(cumulative>=.95*active) {p95=b/10; break}}
      printf "%.3f|%.3f|%.3f|%.1f|%.6f|%.3f|%.6f\n",db(bp/active),db(rp/active),db(bp/rp),p95,persistent/active,active/48000,active/total
    }
  ' "$1"
}

# ────────────────────────────────────────────────────────────────────────────────
# Unica decodifica per tutte le metriche del classificatore:
# - ebur128: loudness integrata, LRA e sample peak;
# - astats full-band sui sei canali;
# - Width Mid/Side dei surround;
# - astats 250-5000 Hz sui sei canali.
#
# Astats full-band raccoglie anche il peak LFE; il ramo bassi emette solo
# RMS per-canale e numero di campioni delle finestre.
# Output: 15 metriche storiche | 10 LFE | 7 bassi | 18 temporali.
# ────────────────────────────────────────────────────────────────────────────────
# Un solo ramo full-band: otto canali nella stessa frame (FL/FR/FC/LFE/SL/SR/M/S).
# Statistiche compatte, O(finestre), mai PCM. Percentili nearest-rank pesati,
# istogramma 0.1 dB (errore di quantizzazione <0.1 dB, arrotondato per difetto).
# Pearson: E[SL*SR]=E[M^2]-E[S^2]; sottrarre DC_SL*DC_SR.
# Sommare covarianze/varianze intra-finestra pesate PRIMA di normalizzare.
measure_surround_windows() {
  awk -v gate="$SUR_ACTIVITY_ABS_DB" -v relative="$SUR_ACTIVITY_REL_DB" \
    -v persistence="$SUR_ACTIVITY_MIN_SECONDS" -v maingate="$SUR_MAIN_MIN_DB" \
    -v corr_gate="$SUR_CORRELATION_GATE" -v win="$TEMPORAL_WINDOW_SAMPLES" '
    function finite(v) {return v ~ /^-?[0-9]+([.][0-9]+)?$/}
    function abs(v) {return v<0?-v:v}
    function db(p) {return 10*log(p)/log(10)}
    function ratio(a,b) {return b<=0?(a>0?"+inf":"N/A"):(a<=0?"-inf":sprintf("%.6f",db(a/b)))}
    function flush(    c) {
      if(!frame) return
      if(samples<=0 || samples>win || samples!=int(samples)) bad=1
      for(c=1;c<=8;c++) {
        if(!(c in rms) || (rms[c]!="-inf" && !finite(rms[c])) || !(c in dc) || !finite(dc[c])) bad=1
      }
      if(bad) return
      n++; weights[n]=samples; total+=samples
      for(c=1;c<=8;c++) {power[n,c]=(rms[c]=="-inf"?0:10^(rms[c]/10)); offsets[n,c]=dc[c]+0}
      main[n]=(power[n,1]+power[n,2]+power[n,3])/3
      sur[n]=(power[n,5]+power[n,6])/2
      program+=(3*main[n]+power[n,5]+power[n,6])*samples/5
    }
    function accept_run(last,    k) {
      if(run_samples>=persistence*48000) for(k=start;k<=last;k++) active[k]=1
      run_samples=0; start=0
    }
    index($0,"[ametadata@sur_windows ") {
      sub(/\r$/, "")
      if($0 ~ /frame:/) {
        flush(); frame=1; samples=0
        for(c in rms) delete rms[c]
        for(c in dc) delete dc[c]
        value=$0; sub(/^.*frame:/,"",value); sub(/[[:space:]].*$/,"",value)
        if(value !~ /^[0-9]+$/ || value+0!=n) bad=1
      } else if($0 ~ /lavfi.astats.[1-8].(RMS_level|DC_offset)=/) {
        key=$0; sub(/^.*lavfi.astats./,"",key); split(key,parts,"."); c=parts[1]
        value=$0; sub(/^.*=/,"",value)
        if(parts[2] ~ /^RMS_level=/) rms[c]=value; else dc[c]=value
      } else if($0 ~ /lavfi.astats.Overall.Number_of_samples=/) {
        value=$0; sub(/^.*=/,"",value)
        if(!finite(value)) bad=1
        samples=value+0
      }
    }
    END {
      flush()
      if(bad || !n || !total) exit 1
      program/=total
      threshold=10^(gate/10)
      rel=program*10^(-relative/10); if(rel>threshold) threshold=rel
      # Attivita persistente: sequenze contigue; ultima frame senza padding.
      for(i=1;i<=n;i++) {
        if(power[i,5]>threshold || power[i,6]>threshold) {
          if(!start) start=i
          run_samples+=weights[i]
        } else accept_run(i-1)
      }
      accept_run(n)
      for(i=1;i<=n;i++) if(active[i]) {
        weight=weights[i]; active_samples+=weight
        if(main[i]>10^(maingate/10) && sur[i]>0) {
          valid++; valid_samples+=weight; sp+=sur[i]*weight; mp+=main[i]*weight
          d=db(sur[i]/main[i]); bin=int(d*10); if(bin>d*10) bin--
          hist[bin]+=weight
          if(valid==1 || bin<lo) lo=bin
          if(valid==1 || bin>hi) hi=bin
        }
        if(power[i,5]<=threshold || power[i,6]<=threshold) continue
        bilateral++; bilateral_samples+=weight
        mid+=power[i,7]*weight; side+=power[i,8]*weight
        vl=power[i,5]-offsets[i,5]^2; vr=power[i,6]-offsets[i,6]^2
        cov=power[i,7]-power[i,8]-offsets[i,5]*offsets[i,6]
        # ametadata DC ha sei decimali: escludere varianze sommerse
        # dalla precisione numerica; tolleranza coerente con tale precisione.
        tol_l=2e-6*abs(offsets[i,5])+1e-12
        tol_r=2e-6*abs(offsets[i,6])+1e-12
        if(vl<=tol_l || vr<=tol_r) continue
        r=cov/sqrt(vl*vr)
        if(r>1.001 || r< -1.001) continue
        if(r>1) r=1; if(r< -1) r=-1
        corrn++; corr_samples+=weight; covsum+=cov*weight; vlsum+=vl*weight; vrsum+=vr*weight
        if(r>=corr_gate) high_samples+=weight
      }
      p10=p50=p90="N/A"
      if(valid_samples) for(b=lo;b<=hi;b++) {
        cumulative+=hist[b]
        if(p10=="N/A" && cumulative>=.1*valid_samples) p10=sprintf("%.1f",b/10)
        if(p50=="N/A" && cumulative>=.5*valid_samples) p50=sprintf("%.1f",b/10)
        if(cumulative>=.9*valid_samples) {p90=sprintf("%.1f",b/10); break}
      }
      correlation=high="N/A"
      if(corr_samples) {
        r=covsum/sqrt(vlsum*vrsum); if(r>1) r=1; if(r< -1) r=-1
        correlation=sprintf("%.6f",r); high=sprintf("%.6f",high_samples/corr_samples)
      }
      printf "%.6f|%s|%s|%s|%s|%s|%s|%s|%d|%d|%.6f|%.6f|%.6f|%d|%.6f|%d|%.6f|%s\n", 
        active_samples/total,(valid_samples?ratio(sp,mp):"N/A"),p10,p50,p90,
        (bilateral?ratio(side,mid):"N/A"),correlation,high,n,valid+0,valid/n,total/48000,
        valid_samples/48000,bilateral+0,bilateral_samples/48000,corrn+0,corr_samples/48000,
        (program>0?sprintf("%.6f",db(program)):"-inf")
    }' "$1"
}

measure_classifier_metrics() {
  local f="$1" stream="$2"
  local probe log_file progress_file ffmpeg_rc codec
  local processed last_processed=""
  local -a input_decoder_opts=()
  # Stessa decodifica del processore; non passare opzioni Dolby ad altri codec.
  codec=$(ffprobe -v error -select_streams "$stream" \
    -show_entries stream=codec_name -of default=nw=1:nk=1 "$f" \
    2>/dev/null </dev/null) || return 1
  codec="${codec//$'\r'/}"
  [[ -n "$codec" ]] || return 1
  case "$codec" in
    ac3|eac3)
      input_decoder_opts=("-drc_scale:${stream}" 0)
      info "Decoder ${codec^^}: misure con DRC Dolby disattivata"
      ;;
  esac
  log_file=$(mktemp -p "$ANALYZER_TMPDIR") || return 1
  progress_file=$(mktemp -p "$ANALYZER_TMPDIR") || return 1

  # framelog=verbose sopprime le righe periodiche di ebur128 al normale livello
  # info, conservando il summary finale. Gli astats terminano in anullsink:
  # vengono eseguiti, ma non trasformati/codificati inutilmente come output PCM.
  ffmpeg -y -nostdin -hide_banner -nostats -xerror -loglevel info \
    -stats_period "$ANALYZER_PROGRESS_INTERVAL" -progress "$progress_file" \
    "${input_decoder_opts[@]}" -i "$f" \
    -filter_complex "[0:${stream}]asplit=8[loud_in][full_in][mid_in][side_in][voice_in][bass_in][bass_ref_in][sur_in];\
[full_in]astats@full=metadata=0:reset=0:measure_perchannel=RMS_level+Peak_level:measure_overall=none,anullsink;\
[mid_in]pan=1c|c0=0.5*c4+0.5*c5,astats@mid=metadata=0:reset=0:measure_perchannel=RMS_level:measure_overall=none,anullsink;\
[side_in]pan=1c|c0=0.5*c4-0.5*c5,astats@side=metadata=0:reset=0:measure_perchannel=RMS_level:measure_overall=none,anullsink;\
[voice_in]highpass=f=250,lowpass=f=5000,astats@voice=metadata=0:reset=0:measure_perchannel=RMS_level:measure_overall=none,anullsink;\
[bass_in]aformat=sample_rates=48000:sample_fmts=fltp,highpass=f=20:t=q:w=0.707,lowpass=f=120:t=q:w=0.707,asetnsamples=n=${LFE_WINDOW_SAMPLES}:p=0,astats@bass=metadata=1:reset=1:measure_perchannel=RMS_level:measure_overall=Number_of_samples,ametadata@lfe_windows=mode=print,anullsink;\
[bass_ref_in]aformat=sample_rates=48000:sample_fmts=fltp,highpass=f=250,lowpass=f=5000,asetnsamples=n=${LFE_WINDOW_SAMPLES}:p=0,astats@bass_reference=metadata=1:reset=1:measure_perchannel=RMS_level:measure_overall=Number_of_samples,ametadata@bass_ref=mode=print,anullsink;\
[sur_in]aformat=sample_rates=48000:sample_fmts=dblp,pan=8c|c0=c0|c1=c1|c2=c2|c3=c3|c4=c4|c5=c5|c6=0.5*c4+0.5*c5|c7=0.5*c4-0.5*c5,asetnsamples=n=${TEMPORAL_WINDOW_SAMPLES}:p=0,astats@surround=metadata=1:reset=1:measure_perchannel=RMS_level+DC_offset:measure_overall=Number_of_samples,ametadata@sur_windows=mode=print,anullsink;\
[loud_in]ebur128@loudness=peak=sample:framelog=verbose[loud_out]" \
    -map "[loud_out]" -vn -sn -f null - \
    >/dev/null 2>"$log_file" </dev/null &
  ANALYZER_FFMPEG_PID=$!

  while kill -0 "$ANALYZER_FFMPEG_PID" 2>/dev/null; do
    sleep 0.2
    processed=$(awk -F= '$1 == "out_time" { value=$2 } END { print value }' "$progress_file" 2>/dev/null)
    if [[ -n "$processed" && "$processed" != "$last_processed" ]]; then
      [[ -n "$last_processed" ]] || printf '==> Analisi in corso...\n' >&2
      printf '%b Audio analizzato: %s\n' "$C_PROGRESS" "$processed" >&2
      last_processed="$processed"
    fi
  done
  wait "$ANALYZER_FFMPEG_PID"
  ffmpeg_rc=$?
  ANALYZER_FFMPEG_PID=""

  # Mostra anche l'ultimo timestamp, normalmente scritto subito prima di end.
  processed=$(awk -F= '$1 == "out_time" { value=$2 } END { print value }' "$progress_file" 2>/dev/null)
  if [[ -n "$processed" && "$processed" != "$last_processed" ]]; then
    [[ -n "$last_processed" ]] || printf '==> Analisi in corso...\n' >&2
    printf '%b Audio analizzato: %s\n' "$C_PROGRESS" "$processed" >&2
  fi

  if (( ffmpeg_rc != 0 )); then
    rm -f -- "$log_file" "$progress_file"
    return 1
  fi

  local lfe_metrics bass_metrics temporal_metrics
  lfe_metrics="$(measure_lfe_windows "$log_file")" || {
    rm -f -- "$log_file" "$progress_file"
    return 1
  }
  bass_metrics="$(measure_bass_windows "$log_file")" || {
    rm -f -- "$log_file" "$progress_file"
    return 1
  }
  temporal_metrics="$(measure_surround_windows "$log_file")" || {
    rm -f -- "$log_file" "$progress_file"
    return 1
  }
  # Evita di copiare tutte le finestre nella variabile e nei parser storici.
  probe="$(awk '!index($0,"[ametadata@lfe_windows ") && !index($0,"[ametadata@bass_ref ") && !index($0,"[ametadata@sur_windows ")' "$log_file")"
  rm -f -- "$log_file" "$progress_file"
  probe="${probe//$'\r'/}"

  local i_val lra_val peak_val rms_values
  i_val=$(printf '%s\n' "$probe" | grep -E "^\s+I:\s+-?[0-9]" | awk '{print $2}' | tail -1)
  lra_val=$(printf '%s\n' "$probe" | grep -E "^\s+LRA:\s+-?[0-9]" | awk '{print $2}' | tail -1)
  peak_val=$(printf '%s\n' "$probe" | grep -E "^\s+Peak:\s+(-?[0-9]|-inf)" | awk '{print $2}' | tail -1)

  rms_values=$(awk '
    index($0,"[astats@full ") {
      if ($0 ~ /Channel:/) full_ch=$NF
      else if ($0 ~ /RMS level dB:/) {
        if      (full_ch==1) fl=$NF
        else if (full_ch==2) fr=$NF
        else if (full_ch==3) fc=$NF
        else if (full_ch==5) sl=$NF
        else if (full_ch==6) sr=$NF
      }
      next
    }
    index($0,"[astats@voice ") {
      if ($0 ~ /Channel:/) voice_ch=$NF
      else if ($0 ~ /RMS level dB:/) {
        if      (voice_ch==1) vfl=$NF
        else if (voice_ch==2) vfr=$NF
        else if (voice_ch==3) vfc=$NF
        else if (voice_ch==5) vsl=$NF
        else if (voice_ch==6) vsr=$NF
      }
      next
    }
    index($0,"[astats@mid ")  && /RMS level dB:/ { mid=$NF; next }
    index($0,"[astats@side ") && /RMS level dB:/ { side=$NF; next }
    END { printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s", fl,fr,fc,sl,sr,mid,side,vfl,vfr,vfc,vsl,vsr }
  ' <<<"$probe")

  # Assegna la variabile locale del chiamante senza una subshell.
  all_metrics="${i_val:-}|${lra_val:-}|${peak_val:-}|${rms_values}|${lfe_metrics}|${bass_metrics}|${temporal_metrics}"
}

# Media energetica in dB di due o tre valori RMS. I valori devono essere finiti.
power_mean_db() {
  awk -v a="$1" -v b="$2" -v c="${3:-}" 'BEGIN {
    if (c == "") p=(10^(a/10)+10^(b/10))/2;
    else         p=(10^(a/10)+10^(b/10)+10^(c/10))/3;
    printf "%.1f", 10*log(p)/log(10);
  }'
}

db_floor_for_math() {
  if [[ "$1" == "-inf" ]]; then
    echo "-120.0"
  elif is_finite_db "$1"; then
    echo "$1"
  else
    return 1
  fi
}

# ────────────────────────────────────────────────────────────────────────────────
# Analisi Delta (bilanciamento canali SUR vs FC)
# ────────────────────────────────────────────────────────────────────────────────
scan_delta() {
  local f="$1"
  info "Avvio analisi Delta SUR-FC su: $f"
  # Seleziono lo stream migliore usando la stessa logica del processore: preferenza per 6 canali, traccia default, lingua italiana. Restituisce "stream_index canali layout". Se non riesco a trovare stream validi, esco con warning e codice di errore.
  local stream_info
  stream_info=$(pick_best_stream "$f") || { warn "Probe fallito: $f"; return 1; }
  local target_stream="${stream_info%% *}"
  local rest="${stream_info#* }"
  local max_ch="${rest%% *}"
  local layout="${rest#* }"
  # Se pick_best_stream non riesce a trovare stream validi, esce con warning e codice di errore. Controllo robusto: se target_stream non è un numero valido, esco con warning e codice di errore.
  if [[ -z "$target_stream" ]]; then
    warn "Nessuna traccia 5.1 idonea. File saltato."
    return 2
  fi
  # Controllo robusto: se max_ch non è un numero valido, esco con warning e codice di errore.
  if ! [[ "$max_ch" =~ ^[0-9]+$ ]] || [[ "$max_ch" -ne 6 ]]; then
    warn "Stream [$target_stream] ha '${max_ch:-?}' canali (non 5.1). Delta richiede esattamente 6 canali. Saltato."
    return 1
  fi
  # Alcuni MKV dichiarano sei canali ma il probe breve non raggiunge il primo
  # pacchetto audio. Verifica il layout per la diagnostica dei canali.
  if [[ -z "$layout" || "$layout" == "unknown" ]]; then
    local confirmed_layout
    confirmed_layout=$(ffprobe -v error -analyzeduration 20000000 -probesize 20000000 \
      -select_streams "$target_stream" -show_entries stream=channel_layout \
      -of default=nw=1:nk=1 "$f" 2>/dev/null </dev/null) || confirmed_layout=""
    confirmed_layout="${confirmed_layout//$'\r'/}"
    [[ -z "$confirmed_layout" ]] || layout="$confirmed_layout"
  fi
  local display_layout="${layout:-unknown}"
  if [[ "$display_layout" == "unknown" ]]; then
    display_layout="5.1(side)"
  fi
  info "Stream selezionato: [$target_stream], ${max_ch} canali, layout ${display_layout}."

  local source_probe source_class source_evidence
  source_probe=$(detect_atmos_source "$f")
  IFS='|' read -r source_class source_evidence <<<"$source_probe"
  if [[ "$source_class" == "ATMOS" ]]; then
    echo -e "${C_ATMOS_FOUND} Atmos verificato nella traccia audio originale.\033[0m"
  else
    echo -e "${C_ATMOS_UNKNOWN} Atmos non verificato nella traccia audio originale.\033[0m"
  fi

  # Mapping posizionale robusto, allineato al processore principale: nell'ordine
  # canonico 5.1 c2 e' FC, c4/c5 sono i surround. Non dipende dai nomi del layout.
  case "$layout" in
    "5.1(side)")
      mapping "Layout audio 5.1(side): mapping posizionale FC=c2, SL=c4, SR=c5." ;;
    "5.1"|"5.1(back)")
      mapping "Layout audio ${layout}: mapping posizionale; c4/c5 diventano SL/SR." ;;
    *)
      mapping "Layout audio ${display_layout}: uso del mapping posizionale 5.1 c0..c5 (FC=c2, SL=c4, SR=c5)." ;;
  esac

  # Loudness, LRA, peak, RMS scena, Width e banda voce condividono la stessa
  # decodifica full-duration: una sola lettura del file per episodio.
  info "Misura unica: LUFS/LRA/peak, RMS scena, Width, banda voce e finestre LFE/bassi..."
  local all_metrics="" cached_metrics="" cache_file="" cache_hit=0
  local i_full lra_full peak_full
  local rms_fl rms_fr rms_fc rms_sl rms_sr rms_mid rms_side
  local rms_vfl rms_vfr rms_vfc rms_vsl rms_vsr
  local lfe_active lfe_p95 lfe_peak lfe_mains lfe_delta lfe_seconds lfe_ratio lfe_windows
  local lfe_hot_p lfe_very_hot_p
  local bass_rms bass_reference bass_delta bass_p95 bass_persistence bass_seconds bass_ratio
  local activity active_delta p10 p50 p90 active_width correlation high_corr total_windows valid_windows
  local valid_fraction analyzed_seconds active_seconds bilateral_windows bilateral_seconds corr_windows corr_seconds program_db temporal

  cache_file="$(analysis_cache_file "$f" "$target_stream" || true)"
  if [[ -n "$cache_file" && -s "$cache_file" ]]; then
    cached_metrics="$(<"$cache_file")"
    if is_valid_metrics_record "$cached_metrics"; then
      all_metrics="$cached_metrics"
      cache_hit=1
      info "Cache HIT: riuso metriche full-duration gia' validate"
    else
      warn "Cache non valida ignorata: ricalcolo le metriche"
    fi
  fi

  if (( cache_hit == 0 )); then
    measure_classifier_metrics "$f" "$target_stream" || {
      warn "Analisi FFmpeg non conclusiva. File saltato."
      return 1
    }
    is_valid_metrics_record "$all_metrics" || {
      warn "Metriche incomplete/non valide. File saltato."
      return 1
    }
  fi

  IFS='|' read -r i_full lra_full peak_full \
    rms_fl rms_fr rms_fc rms_sl rms_sr rms_mid rms_side \
    rms_vfl rms_vfr rms_vfc rms_vsl rms_vsr \
    lfe_active lfe_p95 lfe_peak lfe_mains lfe_delta lfe_seconds lfe_ratio lfe_windows \
    lfe_hot_p lfe_very_hot_p \
    bass_rms bass_reference bass_delta bass_p95 bass_persistence bass_seconds bass_ratio \
    activity active_delta p10 p50 p90 active_width correlation high_corr total_windows valid_windows \
    valid_fraction analyzed_seconds active_seconds bilateral_windows bilateral_seconds corr_windows corr_seconds program_db <<<"$all_metrics"
  temporal="$(cut -d'|' -f33- <<<"$all_metrics")"

  # Il sample peak distingue il vero silenzio dal valore sentinella -70 LUFS
  # restituito da ebur128 per una traccia digitalmente vuota.
  if [[ "$peak_full" == "-inf" ]]; then
    warn "Traccia audio digitalmente silenziosa. File saltato."
    return 1
  fi
  if ! is_finite_db "$peak_full"; then
    warn "Sample peak globale non misurabile. File saltato."
    return 1
  fi
  if awk -v peak="$peak_full" -v gate="$ANALYZER_SILENCE_PEAK_DB" 'BEGIN { exit !(peak <= gate) }'; then
    warn "Traccia audio quasi silenziosa (peak ${peak_full} dBFS). File saltato."
    return 1
  fi

  local fl_math fr_math fc_math sl_math sr_math
  fl_math=$(db_floor_for_math "$rms_fl") || { warn "RMS FL non misurabile. File saltato."; return 1; }
  fr_math=$(db_floor_for_math "$rms_fr") || { warn "RMS FR non misurabile. File saltato."; return 1; }
  fc_math=$(db_floor_for_math "$rms_fc") || { warn "RMS FC non misurabile. File saltato."; return 1; }
  sl_math=$(db_floor_for_math "$rms_sl") || { warn "RMS SL non misurabile. File saltato."; return 1; }
  sr_math=$(db_floor_for_math "$rms_sr") || { warn "RMS SR non misurabile. File saltato."; return 1; }

  local rms_sur rms_front rms_main delta_sur delta_fc balance_sur
  rms_sur=$(power_mean_db "$sl_math" "$sr_math")
  rms_front=$(power_mean_db "$fl_math" "$fr_math")
  rms_main=$(power_mean_db "$fl_math" "$fr_math" "$fc_math")
  delta_sur=$(awk -v sur="$rms_sur" -v main="$rms_main" 'BEGIN { printf "%.1f", sur-main }')
  delta_fc=$(awk -v fc="$fc_math" -v front="$rms_front" 'BEGIN { printf "%.1f", fc-front }')
  balance_sur=$(awk -v sl="$sl_math" -v sr="$sr_math" 'BEGIN { d=sl-sr; if(d<0)d=-d; printf "%.1f", d }')

  # Prominenza del parlato e rischio di mascheramento nella banda utile alla
  # voce. Se tutta la banda e' praticamente vuota, non la usiamo per decidere:
  # la classificazione spaziale resta disponibile.
  local vfl_math vfr_math vfc_math vsl_math vsr_math
  vfl_math=$(db_floor_for_math "$rms_vfl") || { warn "RMS voice-band FL non misurabile. File saltato."; return 1; }
  vfr_math=$(db_floor_for_math "$rms_vfr") || { warn "RMS voice-band FR non misurabile. File saltato."; return 1; }
  vfc_math=$(db_floor_for_math "$rms_vfc") || { warn "RMS voice-band FC non misurabile. File saltato."; return 1; }
  vsl_math=$(db_floor_for_math "$rms_vsl") || { warn "RMS voice-band SL non misurabile. File saltato."; return 1; }
  vsr_math=$(db_floor_for_math "$rms_vsr") || { warn "RMS voice-band SR non misurabile. File saltato."; return 1; }

  local rms_voice_front rms_voice_sur rms_voice_main delta_voice voice_mask voice_metric_note
  rms_voice_front=$(power_mean_db "$vfl_math" "$vfr_math")
  rms_voice_sur=$(power_mean_db "$vsl_math" "$vsr_math")
  rms_voice_main=$(power_mean_db "$vfl_math" "$vfr_math" "$vfc_math")
  delta_voice=""
  voice_mask=""
  voice_metric_note="valida"
  if awk -v rms="$rms_voice_main" -v gate="$VOICE_BAND_RMS_GATE" 'BEGIN { exit !(rms >= gate) }'; then
    delta_voice=$(awk -v fc="$vfc_math" -v front="$rms_voice_front" 'BEGIN { printf "%.1f", fc-front }')
    voice_mask=$(awk -v sur="$rms_voice_sur" -v fc="$vfc_math" 'BEGIN { printf "%.1f", sur-fc }')
  else
    voice_metric_note="N/A: banda voce sotto ${VOICE_BAND_RMS_GATE} dBFS"
  fi

  local width_ms width_desc
  local mid_math side_math
  mid_math=$(db_floor_for_math "$rms_mid") || { warn "RMS MID non misurabile. File saltato."; return 1; }
  side_math=$(db_floor_for_math "$rms_side") || { warn "RMS SIDE non misurabile. File saltato."; return 1; }
  width_ms=$(awk -v side="$side_math" -v mid="$mid_math" 'BEGIN { printf "%.1f", side-mid }')
  width_desc=$(width_to_desc "$width_ms")

  # Override di sicurezza: tracce surround assenti o fortemente sbilanciate non
  # sono materiale adatto a una scelta spaziale automatica.
  local forced_preset=0 preset_raw
  if [[ "$rms_sl" == "-inf" || "$rms_sr" == "-inf" ]] || \
     awk -v sur="$rms_sur" -v gate="$SUR_FAKE_RMS_GATE" 'BEGIN { exit !(sur < gate) }'; then
    warn "Surround virtualmente muti (${rms_sur} dBFS RMS): processing automatico bloccato."
    forced_preset=1
    preset_raw="BLOCCATO|\033[1;33m|BASSA|-|surround virtualmente muti|SAFETY_OVERRIDE|BASSA|BLOCKED"
  elif [[ "$rms_fc" == "-inf" ]]; then
    warn "Canale centrale silenzioso: processing automatico bloccato; controllo manuale richiesto."
    forced_preset=1
    preset_raw="BLOCCATO|\033[1;33m|BASSA|-|centro silenzioso|SAFETY_OVERRIDE|BASSA|BLOCKED"
  elif awk -v b="$balance_sur" -v gate="$SUR_BALANCE_WARN_DB" 'BEGIN { exit !(b >= gate) }'; then
    warn "Sbilanciamento SL/SR elevato (${balance_sur} dB): processing automatico bloccato; controllo manuale richiesto."
    forced_preset=1
    preset_raw="BLOCCATO|\033[1;33m|BASSA|-|sbilanciamento SL/SR|SAFETY_OVERRIDE|BASSA|BLOCKED"
  else
    preset_raw=$(classify_preset "$delta_sur" "$delta_fc" "$delta_voice" "$voice_mask" "$width_ms" "$temporal" "$balance_sur") || return 1
  fi
  local measured_preset="${preset_raw%%|*}"
  local preset p_color confidence alternative preset_reason selection_mode measurement_confidence temporal_assessment
  IFS='|' read -r preset p_color confidence alternative preset_reason selection_mode measurement_confidence temporal_assessment <<<"$preset_raw"
  # La scena misurata resta AEGIS quando SONAR dipende dalla preferenza.
  [[ "$selection_mode" != "IMMERSIVE_PREFERENCE" ]] || measured_preset="AEGIS"
  if (( forced_preset == 0 )) && \
     awk -v b="$balance_sur" -v gate="$SUR_BALANCE_WARN_DB" -v margin="$PRESET_BORDERLINE_MARGIN" \
       'BEGIN { exit !(b < gate && (gate-b) <= margin) }'; then
    confidence="BASSA"
    alternative="-"
    preset_reason="${preset_reason} (borderline sbilanciamento)"
  fi

  # La cache conserva solo le misure; nessuna correzione LFE/bassi.
  if [[ -n "$cache_file" ]]; then
    store_metrics_cache "$cache_file" "$all_metrics" || warn "Impossibile aggiornare la cache"
  fi

  # Accumulo metriche e decisioni per-file. Le anomalie restano diagnostiche;
  # il codice di ritorno impedisce di pubblicare un batch non sicuro.
  GLOBAL_METRIC_VALUES+=("$delta_sur")
  GLOBAL_METRIC_FILES+=("$(basename "$f")")
  GLOBAL_METRIC_PATHS+=("$f")
  GLOBAL_LOUDNESS_VALUES+=("${i_full:-N/A}")
  GLOBAL_WIDTH_VALUES+=("${width_ms:-N/A}")
  GLOBAL_LRA_VALUES+=("${lra_full:-N/A}")
  GLOBAL_PRESET_VALUES+=("$preset")
  GLOBAL_PRESET_FORCED_VALUES+=("$forced_preset")
  GLOBAL_CENTER_DELTA_VALUES+=("$delta_fc")
  GLOBAL_VOICE_DELTA_VALUES+=("${delta_voice:-N/A}")
  GLOBAL_VOICE_MASK_VALUES+=("${voice_mask:-N/A}")
  GLOBAL_BALANCE_VALUES+=("$balance_sur")
  GLOBAL_CONFIDENCE_VALUES+=("$confidence")
  GLOBAL_ALTERNATIVE_VALUES+=("$alternative")
  GLOBAL_REASON_VALUES+=("$preset_reason")
  GLOBAL_SOURCE_CLASS_VALUES+=("$source_class")
  GLOBAL_SOURCE_EVIDENCE_VALUES+=("$source_evidence")
  GLOBAL_MEASURED_PRESET_VALUES+=("$measured_preset")
  GLOBAL_TEMPORAL_VALUES+=("$temporal")
  GLOBAL_SELECTION_MODE_VALUES+=("$selection_mode")
  GLOBAL_MEASUREMENT_CONFIDENCE_VALUES+=("$measurement_confidence")
  GLOBAL_TEMPORAL_ASSESSMENT_VALUES+=("$temporal_assessment")

  # Display dei risultati per il file, con colori e descrizioni. Se alcune metriche non sono misurabili, le segnalo come N/A. Se il preset è stato forzato, mostro comunque il preset forzato ma con la descrizione che indica la ragione.
  ok "Risultati Classifier per: $f"
  printf '\n'
  info "LFE / BASS ANALYSIS (finestre coincidenti da 0.5 s)"
  info "LFE 20-120 Hz | Active RMS: $lfe_active dBFS | P95: $lfe_p95 dBFS | Peak full-band: $lfe_peak dBFS"
  info "Bass mains (somma energie 5 canali): $lfe_mains dBFS | LFE Delta: $lfe_delta dB"
  info "Attivita LFE: $lfe_seconds s | frazione: $lfe_ratio | finestre totali: $lfe_windows"
  info "Persistenza diagnostica (frazione attivita LFE): HOT=$lfe_hot_p | VERY_HOT=$lfe_very_hot_p"
  info "BASS (proxy energetico; LFE +10 dB solo nella misura)"
  info "Bass RMS: $bass_rms dBFS | riferimento 250-5000 Hz: $bass_reference dBFS"
  info "Bass Delta: $bass_delta dB | P95 delta: $bass_p95 dB | persistenza: $bass_persistence"
  info "Finestre valide: $bass_seconds s | frazione: $bass_ratio"
  printf '\n'
  echo -e "  \033[1;33mRMS MAIN: \033[0m  ${rms_main} dBFS  (media energetica FL/FR/FC)"
  echo -e "  \033[1;33mRMS SUR:  \033[0m  ${rms_sur} dBFS  (media energetica SL/SR)"
  echo -e "  \033[1;37mDeltaSur: \033[0m  ${p_color}${delta_sur} dB\033[0m  (SUR - MAIN)"
  echo -e "  \033[1;37mDeltaFC:  \033[0m  ${delta_fc} dB  (FC - FRONT)"
  echo -e "  \033[1;33mVoiceDelta:\033[0m ${delta_voice:-N/A} dB  (FC - FRONT, 250-5000 Hz; ${voice_metric_note})"
  echo -e "  \033[1;33mVoiceMask: \033[0m ${voice_mask:-N/A} dB  (SUR - FC, 250-5000 Hz; alto = piu' rischio)"
  echo -e "  \033[1;37mBalance:  \033[0m  ${balance_sur} dB  (|SL - SR|)"
  echo -e "  \033[1;36mWidth MS: \033[0m  ${width_ms} dB  (${width_desc}; SIDE - MID SL/SR)"
  echo -e "  \033[1;33mI(full):  \033[0m  ${i_full:-N/A} LUFS"
  echo -e "  \033[1;33mLRA:      \033[0m  ${lra_full:-N/A} LU  (solo informazione)"
  echo -e "  \033[1;36mAudio:    \033[0m  ${display_layout}"
  if [[ "$source_class" == "ATMOS" ]]; then
    echo -e "  \033[1;36mAtmos:    \033[0m  verificato (${source_evidence}; solo informazione)"
  else
    echo -e "  \033[1;36mAtmos:    \033[0m  non verificato (solo informazione)"
  fi
  printf '\n'
  info "TEMPORAL SURROUND ANALYSIS (full-band; finestre sincronizzate da 500 ms)"
  printf '  Surround Activity: %s%%\n' "$(awk -v r="$activity" 'BEGIN {printf "%.2f",r*100}')"
  printf '  Active DeltaSur: %s dB\n' "$active_delta"
  printf '  DeltaSur P10/P50/P90: %s / %s / %s dB\n' "$p10" "$p50" "$p90"
  printf '  Active Width: %s dB\n' "$active_width"
  printf '  Surround Correlation: %s\n' "$correlation"
  printf '  High Correlation Persistence: %s\n' "$(awk -v r="$high_corr" 'BEGIN {if(r=="N/A") print r; else printf "%.2f%%",r*100}')"
  printf '  Valid Windows: %s (%s%%; %s s)\n' "$valid_windows" "$(awk -v r="$valid_fraction" 'BEGIN {printf "%.2f",r*100}')" "$active_seconds"
  printf '  Total Windows: %s | Analyzed Duration: %s s\n' "$total_windows" "$analyzed_seconds"
  printf '  Bilateral Windows: %s (%s s) | Correlation Windows: %s (%s s)\n' "$bilateral_windows" "$bilateral_seconds" "$corr_windows" "$corr_seconds"
  printf '\n'
  info "CLASSIFIER"
  echo -e "  Preset: ${p_color}${preset}\033[0m"
  local alternative_color="" alternative_reset=""
  case "$alternative" in
    SONAR|AEGIS|WIDE|AURA)
      alternative_color="$(preset_color "$alternative")"
      alternative_reset="\033[0m"
      ;;
  esac
  printf '  Alternative: %b%s%b\n' "$alternative_color" "$alternative" "$alternative_reset"
  printf '  Selection Mode: %s\n' "$selection_mode"
  printf '  Confidence: %s | Measurement Confidence: %s\n' "$confidence" "$measurement_confidence"
  printf '  Temporal Assessment: %s\n' "$temporal_assessment"
  # Sintesi solo a video; la motivazione completa resta nei dati e nel batch.
  local reason_summary="${preset_reason%%;*}"
  reason_summary="${reason_summary%%:*}"
  if [[ "$selection_mode" == "IMMERSIVE_PREFERENCE" ]]; then
    reason_summary="Preferenza immersiva attiva; scena misurata AEGIS."
  fi
  printf '  Reason: %s\n' "$reason_summary"
  if [[ "$selection_mode" == "IMMERSIVE_PREFERENCE" ]]; then
    printf '  Nota: nessuna ricostruzione Atmos; superiorita percettiva non misurata.\n'
  fi
  if [[ "$preset" == "INCONCLUSIVE" ]]; then
    printf '  %b Processing automatico escluso.\n' "$C_WARN"
  fi
  echo ""
  # Le metriche restano nel report, ma il ciclo principale impedisce il batch.
  if (( forced_preset != 0 )); then return 1; fi
  return 0
}

# ────────────────────────────────────────────────────────────────────────────────
# CICLO PRINCIPALE
# ────────────────────────────────────────────────────────────────────────────────
# Per ogni file, analizzo la struttura audio e poi eseguo l'analisi Delta. Se la struttura audio non è valida (es. nessuna traccia, traccia non 5.1), salto il file con un warning. I risultati di ogni file vengono accumulati in array globali per il verdetto stagionale e la tabella finale.
for CUR_FILE in "${FILES[@]}"; do
  info "Analisi: $CUR_FILE"
  scan_delta "$CUR_FILE"
  case $? in
    0) ;;
    2) ((ANALYSIS_SKIPPED+=1)) ;;
    *) ((ANALYSIS_ERRORS+=1)) ;;
  esac
done

# Un batch incompleto non sostituisce quello precedente.
if (( ANALYSIS_ERRORS > 0 || ${#GLOBAL_METRIC_VALUES[@]} == 0 )); then
  err "Analisi non completata: OK=${#GLOBAL_METRIC_VALUES[@]}, FALLITI=$ANALYSIS_ERRORS, SALTATI=$ANALYSIS_SKIPPED"
  [[ "$CREATE_RUN" != "si" ]] || warn "Batch NON aggiornato. Non eseguire un eventuale run_processing.sh precedente per questa analisi."
  exit 1
fi

# ────────────────────────────────────────────────────────────────────────────────
# VERDETTO STAGIONALE / GENERAZIONE BATCH
# Preset modale per-file; consenso < 2/3, parita' o spread DeltaSur > 4 dB -> MIXED.
# ────────────────────────────────────────────────────────────────────────────────
if [[ "${#GLOBAL_METRIC_VALUES[@]}" -gt 0 ]]; then
  CNT=${#GLOBAL_METRIC_VALUES[@]}
  HIGH_SPREAD=0

  # Se ho più di un episodio, calcolo statistiche (min, max, media, P25) per il verdetto stagionale. Uso file temporanei e awk per gestire i calcoli in modo robusto e preciso, evitando problemi di formattazione o precisione nei passaggi di variabili. Se ho un solo episodio, uso direttamente quel valore per tutte le statistiche.
  if [[ "$CNT" -gt 1 ]]; then
    _vals_tmp=$(mktemp -p "$ANALYZER_TMPDIR")
    printf '%s\n' "${GLOBAL_METRIC_VALUES[@]}" > "$_vals_tmp"
    # Calcolo statistiche con awk: ordino i valori, prendo min (primo), max (ultimo), media (somma/n) e P25 (valore al rank 0.25*n). Se il calcolo fallisce per qualche motivo, esco con warning e codice di errore.
    _stats_tmp=$(mktemp -p "$ANALYZER_TMPDIR")
    awk '{v[NR]=$1+0} END{n=NR; for(i=2;i<=n;i++){k=v[i];j=i-1; while(j>=1&&v[j]>k){v[j+1]=v[j];j--}; v[j+1]=k}; mn=v[1];mx=v[n]; s=0;for(i=1;i<=n;i++)s+=v[i]; avg=s/n; raw=0.25*n;rank=int(raw);if(raw>rank)rank=rank+1; if(rank<1)rank=1;if(rank>n)rank=n; pctl=v[rank]; printf "%.1f %.1f %.1f %.1f\n",mn,mx,avg,pctl}' "$_vals_tmp" > "$_stats_tmp"
    
    # Leggo le statistiche calcolate da awk, che sono formattate con una cifra decimale. Se per qualche motivo la lettura fallisce, esco con warning e codice di errore.
    read -r m_min m_max m_avg m_pctl < "$_stats_tmp"
    rm -f "$_vals_tmp" "$_stats_tmp"
    # Calcolo lo spread come differenza tra max e min, formattato con una cifra decimale. Se lo spread è maggiore di 4 dB, considero la stagione eterogenea e suggerisco di considerare i preset per-file invece del verdetto stagionale.
    m_spread=$(awk -v mx="$m_max" -v mn="$m_min" 'BEGIN { s=mx-mn; if(s<0)s=-s; printf "%.1f",s }')
    HIGH_SPREAD=$(awk -v s="$m_spread" 'BEGIN { print (s > 4.0) ? 1 : 0 }')
  else
    m_min="${GLOBAL_METRIC_VALUES[0]}"
    m_max="${GLOBAL_METRIC_VALUES[0]}"
    m_avg="${GLOBAL_METRIC_VALUES[0]}"
    m_pctl="${GLOBAL_METRIC_VALUES[0]}"
    m_spread="0.0"
  fi
  # Il verdetto stagionale deriva dai preset finali per-file e conserva quindi
  # DeltaFC, VoiceDelta, VoiceMask e Width. Il batch resta sempre per-file.
  declare -A PRESET_COUNTS=()
  for p in "${GLOBAL_PRESET_VALUES[@]}"; do
    PRESET_COUNTS[$p]=$(( ${PRESET_COUNTS[$p]:-0} + 1 ))
  done
  dominant_preset=""; dominant_count=0; dominant_tie=0
  preset_distribution=""
  for p in SONAR AURA WIDE AEGIS INCONCLUSIVE; do
    p_count="${PRESET_COUNTS[$p]:-0}"
    (( p_count > 0 )) && preset_distribution+="${p}:${p_count} "
    [[ "$p" != "INCONCLUSIVE" ]] || continue
    if (( p_count > dominant_count )); then
      dominant_preset="$p"; dominant_count=$p_count; dominant_tie=0
    elif (( p_count == dominant_count && p_count > 0 )); then
      dominant_tie=1
    fi
  done

  low_confidence_count=0
  medium_confidence_count=0
  high_confidence_count=0
  forced_count=0
  for (( i=0; i<CNT; i++ )); do
    [[ "${GLOBAL_CONFIDENCE_VALUES[$i]}" == "BASSA" ]] && low_confidence_count=$((low_confidence_count + 1))
    [[ "${GLOBAL_CONFIDENCE_VALUES[$i]}" == "MEDIA" ]] && medium_confidence_count=$((medium_confidence_count + 1))
    [[ "${GLOBAL_CONFIDENCE_VALUES[$i]}" == "ALTA" ]] && high_confidence_count=$((high_confidence_count + 1))
    [[ "${GLOBAL_PRESET_FORCED_VALUES[$i]}" == "1" ]] && forced_count=$((forced_count + 1))
  done

  season_preset="$dominant_preset"
  season_desc="preset piu' frequente tra le decisioni per-file"
  # Oltre alla parita', richiedo almeno due terzi di consenso: una maggioranza
  # debole non e' una base sufficiente per suggerire un preset unico.
  if (( dominant_count == 0 )); then
    season_preset="INCONCLUSIVE"
    season_color="\033[1;37m"
    season_desc="nessuna evidenza sufficiente; tutti i file esclusi dal processing automatico"
  elif (( dominant_tie == 1 || HIGH_SPREAD == 1 || dominant_count * 3 < CNT * 2 )); then
    season_preset="MIXED"
    season_color="\033[1;37m"
    season_desc="nessun preset unico affidabile; usare le decisioni per-file"
  else
    season_color="$(preset_color "$season_preset")"
  fi
  # Display del verdetto stagionale, con statistiche e preset consigliato. Se lo spread è alto, avverto che la stagione è eterogenea e suggerisco di considerare i preset per-file, che mostro in una tabella con i nomi dei file (troncati se troppo lunghi), i valori di Delta e i preset consigliati per ciascun file, con colori.
  if [[ "$CNT" -gt 1 ]]; then
    echo -e "  Episodi analizzati:  \033[1;37m${CNT}\033[0m"
    echo -e "  DeltaSur medio:      \033[0;37m${m_avg} dB\033[0m"
    echo -e "  DeltaSur P25:        \033[0;37m${m_pctl} dB\033[0m  (solo diagnostica)"
    echo -e "  Range DeltaSur:      \033[0;37m${m_min} / ${m_max} dB  (spread: ${m_spread} dB)\033[0m"
    echo -e "  Distribuzione:       \033[0;37m${preset_distribution% }\033[0m"
    echo -e "  Decisioni incerte:   \033[0;37m${low_confidence_count}/${CNT}\033[0m"
    echo "  Confidence: ALTA=${high_confidence_count} MEDIA=${medium_confidence_count} BASSA=${low_confidence_count}"
    echo -e "  Preset Consigliato:  ${season_color}${season_preset}\033[0m  (${season_desc})"

    # Le anomalie gravi bloccano il batch prima del riepilogo stagionale.
    if [[ "$forced_count" -gt 0 ]]; then
      echo -e "  \033[0;33mNota: ${forced_count} file con override di sicurezza; verificare le righe per-file.\033[0m"
    fi 
    # Se il verdetto e' MIXED, mostro le metriche decisive per ogni file.
    if [[ "$season_preset" == "MIXED" ]]; then
      echo ""
      echo -e "  \033[0;33m   La stagione è eterogenea o non ha consenso sufficiente.\033[0m"
      echo -e "  \033[0;33m   Per risultati ottimali, considera i preset per-file:\033[0m"
      echo ""
      for (( i=0; i<CNT; i++ )); do
        pf_preset="${GLOBAL_PRESET_VALUES[$i]}"
        pf_color="$(preset_color "$pf_preset")"
        fname="${GLOBAL_METRIC_FILES[$i]}"
        (( ${#fname} > 50 )) && fname="${fname:0:47}..."
        printf "    %-50s  %b%-5s\033[0m  (Sur=%s, FC=%s, Voice=%s, Mask=%s dB, src=%s, conf=%s)\n" \
          "$fname" "$pf_color" "$pf_preset" "${GLOBAL_METRIC_VALUES[$i]}" \
          "${GLOBAL_CENTER_DELTA_VALUES[$i]}" "${GLOBAL_VOICE_DELTA_VALUES[$i]}" \
          "${GLOBAL_VOICE_MASK_VALUES[$i]}" "${GLOBAL_SOURCE_CLASS_VALUES[$i]}" "${GLOBAL_CONFIDENCE_VALUES[$i]}"
      done
    fi
  fi

  # ── Generazione batch file ─────────────────────────────────────────────────
  # Genero i comandi con i soli quattro preset automatici per-file, conservando
  # i parametri e le metriche. Il verdetto stagionale resta solo diagnostico.
  BATCH_FILE="run_processing.sh"
  if [[ "$CREATE_RUN" == "si" ]]; then
    BATCH_TMP=$(mktemp "./.${BATCH_FILE}.XXXXXX") || { err "Impossibile creare il batch temporaneo"; exit 1; }
    (
      set -e
      echo '#!/usr/bin/env bash'
      echo "# ── Batch generato da audio_analyzer Temporal Surround Intelligence ──"
      echo "# SONAR_IMMERSIVE_PREFERENCE=${SONAR_IMMERSIVE_PREFERENCE} (decisione salvata; rigenerare per cambiarla)"
      echo "# Data: $(date '+%Y-%m-%d %H:%M')"
      echo "# Metrica: DeltaSur + DeltaFC + VoiceDelta + VoiceMask + Balance + Width | preset sempre per-file"
      echo '# Temporal fields: Activity|ActiveDeltaSur|P10|P50|P90|ActiveWidth|Correlation|HighCorrelationPersistence|TotalWindows|ValidWindows|ValidFraction|AnalyzedSeconds|ValidSeconds|BilateralWindows|BilateralSeconds|CorrelationWindows|CorrelationSeconds|ProgramDB'
      echo '#'
      echo '# Modifica le variabili sotto se necessario, poi lancia:'
      echo "#   ./${BATCH_FILE}"
      echo '#'
      echo ''
      echo '# ── CONFIGURAZIONE (modifica qui) ──'
      echo "CODEC=\"${BATCH_CODEC}\"        # ac3 | eac3"
      echo "KEEP=\"${BATCH_KEEP}\"           # si | no"
      echo "BITRATE=\"${BATCH_BITRATE}\"      # es. 448k, 640k, 768k"
      printf 'DEFAULT_PROCESSOR=%q\n' "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/aegis_sonar_wide_aura_voice_psycho.sh"
      echo 'PROC="${PROC:-$DEFAULT_PROCESSOR}"'
      echo ''
      echo '# ── COMANDI ──'
      echo 'BATCH_FAILURES=0'
      echo "# Preset per-file; misure LFE/bassi solo diagnostiche. Volume di ascolto sull'AVR."
      echo "# VOICEITA e' un preset manuale: non selezionato o generato da audio_analyzer."
  
      # Per ogni file genero un comando usando sempre il preset raffinato per-file. Escludo gli output già processati.
      for (( i=0; i<CNT; i++ )); do
        case "${GLOBAL_METRIC_PATHS[$i]}" in
          *_AC3_Aegis.mkv|*_AC3_Sonar.mkv|*_AC3_Wide.mkv|*_AC3_Aura.mkv|*_AC3_Voice.mkv|*_AC3_Voiceita.mkv|\
          *_EAC3_Aegis.mkv|*_EAC3_Sonar.mkv|*_EAC3_Wide.mkv|*_EAC3_Aura.mkv|*_EAC3_Voice.mkv|*_EAC3_Voiceita.mkv)
            continue
            ;;
        esac
        # Il batch usa SEMPRE il preset raffinato per-file gia' calcolato in scan_delta.
        # In questo modo non perde le metriche voce, Width e gli override di sicurezza.
        file_preset="${GLOBAL_PRESET_VALUES[$i]:-}"
        if [[ "$file_preset" == "INCONCLUSIVE" ]]; then
          printf '# ESCLUSO INCONCLUSIVE: %q | %s | confidence=%s | SelectionMode=%s\n' \
            "${GLOBAL_METRIC_PATHS[$i]}" "${GLOBAL_REASON_VALUES[$i]}" "${GLOBAL_CONFIDENCE_VALUES[$i]}" "${GLOBAL_SELECTION_MODE_VALUES[$i]}"
          continue
        fi
        case "$file_preset" in
          AEGIS|SONAR|WIDE|AURA) ;;
          *) err "Preset automatico non sicuro: $file_preset"; exit 1 ;;
        esac
        file_preset_lower="${file_preset,,}"
        file_loudness="${GLOBAL_LOUDNESS_VALUES[$i]:-N/A}"
        file_width="${GLOBAL_WIDTH_VALUES[$i]:-N/A}"
        file_lra="${GLOBAL_LRA_VALUES[$i]:-N/A}"
        file_delta_fc="${GLOBAL_CENTER_DELTA_VALUES[$i]:-N/A}"
        file_delta_voice="${GLOBAL_VOICE_DELTA_VALUES[$i]:-N/A}"
        file_voice_mask="${GLOBAL_VOICE_MASK_VALUES[$i]:-N/A}"
        file_balance="${GLOBAL_BALANCE_VALUES[$i]:-N/A}"
        file_confidence="${GLOBAL_CONFIDENCE_VALUES[$i]:-N/A}"
        file_alternative="${GLOBAL_ALTERNATIVE_VALUES[$i]:--}"
        file_source_class="${GLOBAL_SOURCE_CLASS_VALUES[$i]:-UNKNOWN}"
        file_atmos_status="non-verificato"
        [[ "$file_source_class" != "ATMOS" ]] || file_atmos_status="verificato"
        file_source_evidence="${GLOBAL_SOURCE_EVIDENCE_VALUES[$i]:-nessun segnale Atmos}"
        file_measured_preset="${GLOBAL_MEASURED_PRESET_VALUES[$i]:-N/A}"
        escaped_path=$(printf '%q' "${GLOBAL_METRIC_PATHS[$i]}")
        printf '# Temporal: %s | reason: %s\n' "${GLOBAL_TEMPORAL_VALUES[$i]}" "${GLOBAL_REASON_VALUES[$i]}"
        printf '# SelectionMode=%s | MeasurementConfidence=%s | Confidence=%s | Alternative=%s\n' \
          "${GLOBAL_SELECTION_MODE_VALUES[$i]}" "${GLOBAL_MEASUREMENT_CONFIDENCE_VALUES[$i]}" "$file_confidence" "$file_alternative"
        printf '# TemporalAssessment=%s\n' "${GLOBAL_TEMPORAL_ASSESSMENT_VALUES[$i]}"
  
        # Il commento conserva metriche, confidenza, alternativa e prova Atmos.
        printf '"$PROC" "$CODEC" "$KEEP" "$BITRATE" %s -- %s || BATCH_FAILURES=$((BATCH_FAILURES + 1))  # OutputAudio=5.1(side) Atmos=%s (%s) MeasuredPreset=%s | DeltaSur=%s dB | DeltaFC=%s dB | VoiceDelta=%s dB | VoiceMask=%s dB | Balance=%s dB | Width=%s dB | conf=%s alt=%s | I=%s LUFS LRA=%s LU\n' \
          "$file_preset_lower" "$escaped_path" "$file_atmos_status" "$file_source_evidence" \
          "$file_measured_preset" "${GLOBAL_METRIC_VALUES[$i]}" \
          "$file_delta_fc" "$file_delta_voice" "$file_voice_mask" "$file_balance" "$file_width" "$file_confidence" "$file_alternative" \
          "$file_loudness" "$file_lra"
      done
  
      echo ''
      echo 'if (( BATCH_FAILURES > 0 )); then'
      echo '  echo "Batch completato con errori: FALLITI=$BATCH_FAILURES" >&2'
      echo '  exit 1'
      echo 'fi'
      echo 'echo "Batch completato senza errori."'
    ) > "$BATCH_TMP"
    BATCH_RC=$?
    if (( BATCH_RC != 0 )) || ! chmod +x "$BATCH_TMP" || ! mv -fT -- "$BATCH_TMP" "$BATCH_FILE"; then
      err "Pubblicazione batch fallita. run_processing.sh non aggiornato."
      exit 1
    fi
    BATCH_TMP=""
    ok "Batch file generato: ${BATCH_FILE}"
  else
    info "Batch disattivato (run=no); eventuale run_processing.sh esistente invariato."
  fi
else
  if [[ "$CREATE_RUN" == "si" ]]; then
    warn "Nessun risultato Classifier valido: run_processing.sh non generato."
  else
    warn "Nessun risultato Classifier valido."
  fi
fi

echo -e ""
ok "Analisi completata. Nessun file audio e' stato modificato."

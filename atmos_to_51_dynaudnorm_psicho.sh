#!/usr/bin/env bash
# ╭──────────────────────────────────────────────────────────────────────────────╮
# │   atmos_to_51_dynaudnorm_psicho.sh - Settembre 2026                          │
# │   By Sandro (D@mocle77) Sabbioni                                             │
# │                                                                              │
# │   Prende un file con traccia EAC3 Atmos (JOC) e produce un MKV con:          │
# │     • Traccia 1: EAC3 5.1 standard con normalizzazione dinamica (default)    │
# │     • Traccia 2: EAC3 Atmos originale (copia bit-perfect)                    │
# │                                                                              │
# │   La decodifica FFmpeg di EAC3 JOC espone il bed 5.1 compatibile; FFmpeg     │
# │   non esegue il rendering degli oggetti Atmos. dynaudnorm applica una        │
# │   normalizzazione dinamica conservativa al bed, che resta lo stadio          │
# │   primario da analizzare/elaborare con i preset psicoacustici.               │
# │                                                                              │
# │   UTILIZZO:                                                                  │
# │     ./atmos_to_51_dynaudnorm_psicho.sh [bitrate] <file|directory|"">         │
# │     ./atmos_to_51_dynaudnorm_psicho.sh --files <bitrate> <file1> [...]       │
# │                                                                              │
# │   PARAMETRI:                                                                 │
# │     file    : File sorgente (mkv/mp4/m2ts), directory da processare          │
# │               oppure "" per batch nella cartella corrente.                   │
# │     bitrate : Bitrate traccia 5.1 (default: 640k).                           │
# │                                                                              │
# │   DIPENDENZE: ffmpeg, ffprobe (con supporto EAC3 JOC)                        │
# ╰──────────────────────────────────────────────────────────────────────────────╯
set -uo pipefail

# Colori
C_INFO="\033[0;36m[INFO]\033[0m"
C_WARN="\033[0;33m[WARNING]\033[0m"
C_MAPPING="\033[0;33m[MAPPING]\033[0m"
C_ATMOS_FOUND="\033[0;38;5;208m[ATMOS]"
C_ATMOS_UNKNOWN="\033[0;38;5;208m[ATMOS]"
C_ERR="\033[0;31m[ERROR]\033[0m"
C_OK="\033[0;32m[OK]\033[0m"

# Funzioni di log
info(){ echo -e "${C_INFO} $*"; }
mapping(){ echo -e "${C_MAPPING} $*"; }
warn(){ echo -e "${C_WARN} $*"; }
err(){  echo -e "${C_ERR}  $*"; }
ok(){   echo -e "${C_OK}  $*"; }

# Guard rail della verifica comparativa tra bed sorgente e traccia normalizzata.
VERIFY_SILENCE_PEAK_DB="-80.0"
VERIFY_MAX_SAMPLE_DELTA_RATIO="0.02"
VERIFY_ACTIVE_INPUT_RMS_DB="-65.0"
VERIFY_MAX_OVERALL_DROP_DB="18.0"
VERIFY_MAX_MAIN_CHANNEL_DROP_DB="24.0"
VERIFY_MAX_LFE_DROP_DB="36.0"

# Funzione per confermare sovrascrittura
confirm_overwrite() {
  local target="$1"
  local ans=""
  if [[ ! -e /dev/tty ]]; then
    warn "TTY non disponibile e '$target' esiste gia' -> skip automatico."
    return 1
  fi
  echo -ne "${C_WARN} '$target' esiste gia'. Sovrascrivere? [s/n/t]: "
  if ! read -r ans < /dev/tty; then
    warn "Impossibile leggere da /dev/tty -> skip automatico."
    return 1
  fi
  case "${ans,,}" in
    t|tutti) OVERWRITE_ALL=true; info "Sovrascrittura automatica attivata."; return 0 ;;
    s|si|y|yes) info "Sovrascrivo."; return 0 ;;
    *) info "Skip manuale richiesto."; return 1 ;;
  esac
}

usage() {
  local rc="${1:-0}"
  cat <<'USAGE'
----------------------------------------------------------------------------------------
UTILIZZO:
  ./atmos_to_51_dynaudnorm_psicho.sh [bitrate] <file|directory|"">
  ./atmos_to_51_dynaudnorm_psicho.sh --files <bitrate> <file1> [file2 ...]

PARAMETRI:
  file|directory : File sorgente (mkv/mp4/m2ts), cartella contenente
                   file video da processare in batch, oppure "" per la
                   cartella corrente.
  bitrate        : Bitrate traccia EAC3 5.1 in uscita (default: 640k).

MODALITA' --files:
  Analizza e converte soltanto i file elencati. Il bitrate e' obbligatorio
  per separare in modo non ambiguo i parametri dai nomi dei file.

ESEMPI:
  ./atmos_to_51_dynaudnorm_psicho.sh 640k film.mkv       # singolo file
  ./atmos_to_51_dynaudnorm_psicho.sh 768k /path/folder   # batch su cartella
  ./atmos_to_51_dynaudnorm_psicho.sh 768k ""             # batch nella cartella corrente
  ./atmos_to_51_dynaudnorm_psicho.sh --files 768k ep1.mkv ep4.mkv

COMPATIBILITA': resta accettato anche il vecchio ordine <file> [bitrate].

OUTPUT:
  <nome>-0.mkv con:
    • Traccia 1: EAC3 5.1 normalizzata (dynaudnorm, default)
    • Traccia 2: EAC3 Atmos originale (copia bit-perfect)

DIPENDENZE: ffmpeg, ffprobe (con supporto EAC3 JOC)
----------------------------------------------------------------------------------------
USAGE
  exit "$rc"
}

# Help: nessun argomento o flag esplicito
[[ $# -eq 0 || "${1:-}" =~ ^(-h|--help)$ ]] && usage
# Check dipendenze
for _bin in ffmpeg ffprobe awk mktemp; do
  command -v "$_bin" &>/dev/null || { err "$_bin non trovato nel PATH"; exit 1; }
done

if ! ffmpeg -hide_banner -encoders 2>/dev/null | grep -E '^[[:space:]]*A[.A-Z]*[[:space:]]+eac3[[:space:]]' >/dev/null; then
  err "Encoder FFmpeg eac3 non disponibile in questa build."
  exit 1
fi

# Parametri. In modalita' --files la sintassi e' volutamente fissa:
# --files <bitrate> <file1> [file2 ...].
MULTI_FILES_MODE=false
MULTI_FILES=()
if [[ "${1:-}" == "--files" ]]; then
  (( $# >= 3 )) || { err "Uso --files non valido: servono bitrate e almeno un file."; usage 1; }
  MULTI_FILES_MODE=true
  BITRATE="${2:-}"
  shift 2
  MULTI_FILES=("$@")
  INPUT_ARG=""
else
  # Sintassi canonica: [bitrate] <input>. Se il primo token non e' un bitrate,
  # mantengo la compatibilita' con il vecchio ordine <input> [bitrate].
  if (( $# == 2 )) && [[ "${1:-}" =~ ^[0-9]+([kKmM])?$ ]]; then
    BITRATE="${1:-640k}"
    INPUT_ARG="${2:-}"
  else
    INPUT_ARG="${1:-}"
    BITRATE="${2:-640k}"
  fi
fi
# Normalizzazione e validazione bitrate EAC3 5.1.
[[ "$BITRATE" =~ ^[0-9]+([kKmM])?$ ]] || { err "Bitrate '$BITRATE' non valido. Es: 640k, 768k."; exit 1; }
BITRATE_LC="${BITRATE,,}"
if [[ "$BITRATE_LC" =~ ^([0-9]+)$ ]]; then
  BITRATE_KBPS="${BASH_REMATCH[1]}"
elif [[ "$BITRATE_LC" =~ ^([0-9]+)k$ ]]; then
  BITRATE_KBPS="${BASH_REMATCH[1]}"
elif [[ "$BITRATE_LC" =~ ^([0-9]+)m$ ]]; then
  BITRATE_KBPS="$(( ${BASH_REMATCH[1]} * 1000 ))"
else
  err "Bitrate '$BITRATE' non valido. Es: 640k, 768k."
  exit 1
fi
if (( BITRATE_KBPS < 256 || BITRATE_KBPS > 768 || ((BITRATE_KBPS - 256) % 64) != 0 )); then
  err "Bitrate EAC3 5.1 non consentito: ${BITRATE_KBPS}k"
  err "Consentiti: 256k, 320k, 384k, 448k, 512k, 576k, 640k, 704k, 768k"
  exit 1
fi
BITRATE="${BITRATE_KBPS}k"

# Dynaudnorm: parametri conservativi per normalizzazione domestica/notturna
# framelen=500   : finestra 500ms — buon compromesso reattività/smoothness
# gausssize=31   : finestra gaussiana 31 frame — smoothing ampio (no pumping)
# peak=0.92      : picco target lineare del normalizzatore
# maxgain=4      : fattore lineare massimo (non 4 dB; circa +12 dB nominali)
# targetrms=0    : target RMS disabilitato; controllo guidato dai picchi
# compress=0     : compressione opzionale interna disabilitata
# coupling=1     : canali accoppiati — preserva l'immagine stereo/surround
# altboundary=0  : boundary mode standard
DYNAUDNORM="highpass=f=20:t=q:w=0.707,dynaudnorm=framelen=500:gausssize=31:peak=0.92:maxgain=4:targetrms=0:compress=0:coupling=1:altboundary=0"

# NB: nessun filtro LFE qui. Questo script e' solo pre-stadio di aegis_sonar_wide_aura_voice_volamp_psycho.sh,
# che gestisce interamente l'LFE (highpass 32 + lowpass 110 + limiter picchi sub). Applicare qui gli stessi
# highpass/lowpass creerebbe un doppio band-pass (ordine raddoppiato, -6 dB ai corner 32/110 Hz): ridondante e dannoso.

# Probe chiave/valore: profilo, layout e lingua dalla stessa interrogazione.
# Il mapping c0..c5 richiede esattamente sei canali: nessun downmix implicito.
find_atmos_stream() {
  local f="$1" raw_data line field idx codec ch def lang profile layout score
  local best_atmos="" best_atmos_score=-1 best_fallback="" best_fallback_score=-1
  local -a fields
  raw_data="$(ffprobe -v error -select_streams a \
    -show_entries stream=index,codec_name,channels,profile,channel_layout:stream_disposition=default:stream_tags=language \
    -of compact=p=0:nk=0 "$f" 2>/dev/null </dev/null)" || return 1
  raw_data="${raw_data//$'\r'/}"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    idx=""; codec=""; ch="0"; def="0"; lang="und"; profile=""; layout=""
    IFS='|' read -r -a fields <<<"$line"
    for field in "${fields[@]}"; do
      case "$field" in
        index=*) idx="${field#index=}" ;;
        codec_name=*) codec="${field#codec_name=}" ;;
        channels=*) ch="${field#channels=}" ;;
        profile=*) profile="${field#profile=}" ;;
        channel_layout=*) layout="${field#channel_layout=}" ;;
        disposition:default=*) def="${field#disposition:default=}" ;;
        tag:language=*) lang="${field#tag:language=}" ;;
      esac
    done
    [[ "$idx" =~ ^[0-9]+$ && "$codec" == "eac3" && "$ch" =~ ^[0-9]+$ ]] || continue
    if (( ch != 6 )); then
      warn "Stream EAC3 idx:${idx} con ${ch} canali escluso: richiesto bed a 6 canali." >&2
      continue
    fi
    score=0
    [[ "$def" == "1" ]] && ((score+=200))
    [[ "${lang,,}" =~ ^it ]] && ((score+=300))
    if [[ "${profile,,}" == *"atmos"* ]]; then
      if (( score > best_atmos_score )); then
        best_atmos_score=$score
        best_atmos="${idx}|${ch}|${lang}|atmos|${layout}"
      fi
    elif (( score > best_fallback_score )); then
      best_fallback_score=$score
      best_fallback="${idx}|${ch}|${lang}|fallback|${layout}"
    fi
  done <<<"$raw_data"
  if [[ -n "$best_atmos" ]]; then
    printf '%s\n' "$best_atmos"
  elif [[ -n "$best_fallback" ]]; then
    echo -e "${C_ATMOS_UNKNOWN} NON RILEVATO - nessun profilo Atmos esplicito trovato: uso il miglior EAC3 6ch come fallback.\033[0m" >&2
    printf '%s\n' "$best_fallback"
  else
    return 1
  fi
}

# Misura peak, RMS, campioni e RMS per-canale.
measure_audio_signal() {
  local f="$1" map_spec="$2" expected_channels=6 probe metrics
  probe="$(
    ffmpeg -hide_banner -nostdin -nostats -xerror -v info -i "$f" \
      -map "$map_spec" -vn -sn -dn \
      -af "aformat=sample_rates=48000:sample_fmts=fltp,astats=metadata=0:reset=0" \
      -f null - 2>&1
  )" || return 1
  probe="${probe//$'\r'/}"

  metrics="$(printf '%s\n' "$probe" | awk -v expected="$expected_channels" '
    /Channel:/ { channel=$NF; overall=0; next }
    /] Overall$/ { overall=1; channel=0; next }
    /Peak level dB:/ { if (overall) overall_peak=$NF; next }
    /RMS level dB:/ {
      if (overall) overall_rms=$NF
      else if (channel >= 1 && channel <= expected) channel_rms[channel]=$NF
      next
    }
    /Number of samples:/ { if (overall) samples=$NF; next }
    END {
      if (overall_peak == "" || overall_rms == "" || samples == "") exit 1
      for (i=1; i<=expected; i++) if (channel_rms[i] == "") exit 1
      printf "%s|%s|%s", overall_peak, overall_rms, samples
      for (i=1; i<=expected; i++) printf "|%s", channel_rms[i]
      printf "\n"
    }
  ')" || return 1

  [[ -n "$metrics" ]] || return 1
  printf '%s\n' "$metrics"
}

is_finite_db() {
  [[ "$1" =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

verify_output_audio_signal() {
  local f="$1" input_metrics="$2" output_metrics
  local -a in_m out_m channel_names=(FL FR FC LFE SL SR)
  local input_peak input_rms input_samples output_peak output_rms output_samples
  local i input_channel_rms output_channel_rms max_drop

  output_metrics="$(measure_audio_signal "$f" "0:a:0")" || {
    VERIFY_REASON="astats non ha restituito metriche complete per l'output"
    return 2
  }

  IFS='|' read -r -a in_m <<<"$input_metrics"
  IFS='|' read -r -a out_m <<<"$output_metrics"
  [[ ${#in_m[@]} -eq 9 && ${#out_m[@]} -eq 9 ]] || {
    VERIFY_REASON="numero di metriche input/output inatteso"
    return 2
  }

  input_peak="${in_m[0]}"; input_rms="${in_m[1]}"; input_samples="${in_m[2]}"
  output_peak="${out_m[0]}"; output_rms="${out_m[1]}"; output_samples="${out_m[2]}"

  if [[ "$output_peak" == "-inf" || "$output_rms" == "-inf" ]]; then
    VERIFY_REASON="output digitalmente silenzioso"
    return 1
  fi
  if ! is_finite_db "$input_peak" || ! is_finite_db "$input_rms" || \
     ! is_finite_db "$output_peak" || ! is_finite_db "$output_rms" || \
     ! [[ "$input_samples" =~ ^[0-9]+([.][0-9]+)?$ && "$output_samples" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    VERIFY_REASON="metriche globali non numeriche"
    return 2
  fi

  if awk -v i="$input_samples" -v o="$output_samples" 'BEGIN { exit !(i <= 0 || o <= 0) }'; then
    VERIFY_REASON="numero di campioni nullo/non valido"
    return 2
  fi
  if awk -v v="$output_peak" -v lim="$VERIFY_SILENCE_PEAK_DB" 'BEGIN { exit !(v <= lim) }'; then
    VERIFY_REASON="picco output troppo basso (${output_peak} dBFS)"
    return 1
  fi
  if awk -v i="$input_rms" -v o="$output_rms" -v lim="$VERIFY_MAX_OVERALL_DROP_DB" \
       'BEGIN { exit !((i-o) > lim) }'; then
    VERIFY_REASON="perdita RMS globale eccessiva: input=${input_rms} dBFS, output=${output_rms} dBFS"
    return 1
  fi
  if awk -v i="$input_samples" -v o="$output_samples" -v d="$VERIFY_MAX_SAMPLE_DELTA_RATIO" \
       'BEGIN { exit !(o < i*(1-d) || o > i*(1+d)) }'; then
    VERIFY_REASON="durata incoerente: campioni input=${input_samples}, output=${output_samples}"
    return 1
  fi

  for i in {0..5}; do
    input_channel_rms="${in_m[$((i+3))]}"
    output_channel_rms="${out_m[$((i+3))]}"

    # Un canale sorgente sotto questa soglia e' considerato intenzionalmente inattivo.
    if [[ "$input_channel_rms" == "-inf" ]]; then
      continue
    fi
    if ! is_finite_db "$input_channel_rms" || \
       { [[ "$output_channel_rms" != "-inf" ]] && ! is_finite_db "$output_channel_rms"; }; then
      VERIFY_REASON="metrica canale ${channel_names[$i]} non numerica"
      return 2
    fi
    if ! awk -v v="$input_channel_rms" -v lim="$VERIFY_ACTIVE_INPUT_RMS_DB" \
         'BEGIN { exit !(v > lim) }'; then
      continue
    fi
    if [[ "$output_channel_rms" == "-inf" ]]; then
      VERIFY_REASON="canale ${channel_names[$i]} attivo in input ma silenzioso in output"
      return 1
    fi

    max_drop="$VERIFY_MAX_MAIN_CHANNEL_DROP_DB"
    [[ $i -eq 3 ]] && max_drop="$VERIFY_MAX_LFE_DROP_DB"
    if awk -v src="$input_channel_rms" -v dst="$output_channel_rms" -v lim="$max_drop" \
         'BEGIN { exit !((src-dst) > lim) }'; then
      VERIFY_REASON="canale ${channel_names[$i]} attenuato eccessivamente: input=${input_channel_rms} dBFS, output=${output_channel_rms} dBFS"
      return 1
    fi
  done

  info "Verifica audio: peak ${input_peak}→${output_peak} dBFS; RMS ${input_rms}→${output_rms} dBFS; campioni ${input_samples}→${output_samples}"
  return 0
}

# True Peak post-codec: stessa soglia e stesso retry limitato del processore 5.1.
VERIFY_MAX_TRUE_PEAK_DB="-0.1"
TRUE_PEAK_RETRY_MARGIN_DB="0.2"
TRUE_PEAK_MAX_AUTO_TRIM_DB="3.0"

# Estrae soltanto il Peak della sezione True peak dell'ultimo summary ebur128.
# Il valore e l'unita' devono essere riconosciuti: nessun fallback a Sample Peak.
measure_true_peak_db() {
  awk '
    /Summary:[[:space:]]*$/ { in_summary=1; expect_peak=0; tp=""; next }
    !in_summary { next }
    /^[[:space:]]*True peak:[[:space:]]*$/ { expect_peak=1; tp=""; next }
    expect_peak {
      if (NF == 0) next
      if (NF == 3 && $1 == "Peak:" && $2 ~ /^[+-]?[0-9]+([.][0-9]+)?$/ &&
          ($3 == "dBFS" || $3 == "dBTP")) tp=$2
      expect_peak=0
    }
    END {
      if (tp == "") exit 1
      print tp
    }
  '
}

# Decodifica l'intero candidato AC3/EAC3: niente -ss/-t e nessuna finestra QC.
# Un errore FFmpeg o un summary incompleto rendono la misura non conclusiva.
measure_encoded_true_peak() {
  local probe
  probe="$(ffmpeg -hide_banner -nostdin -nostats -xerror -v info -i "$1" \
    -map "0:a:0" -vn -sn -dn -af "ebur128=peak=true:framelog=verbose" \
    -f null - 2>&1)" || return 1
  probe="${probe//$'\r'/}"
  printf '%s\n' "$probe" | measure_true_peak_db
}


verify_audio_candidate() {
  local rc
  VERIFY_FAILURE_KIND=""
  VERIFY_OUTPUT_TRUE_PEAK=""
  VERIFY_REASON=""
  info "Verifica comparativa sull'intera traccia audio"
  verify_output_audio_signal "$1" "$INPUT_AUDIO_METRICS"
  rc=$?
  (( rc == 0 )) || return "$rc"
  info "Verifica True Peak post-codec sull'intera traccia audio"
  VERIFY_OUTPUT_TRUE_PEAK="$(measure_encoded_true_peak "$1")" || {
    VERIFY_REASON="misura True Peak post-codec fallita o non conclusiva"
    return 2
  }
  info "True Peak post-codec: ${VERIFY_OUTPUT_TRUE_PEAK} dBTP"
  if awk -v tp="$VERIFY_OUTPUT_TRUE_PEAK" -v lim="$VERIFY_MAX_TRUE_PEAK_DB" \
       'BEGIN { exit !(tp > lim) }'; then
    VERIFY_FAILURE_KIND="true_peak"
    VERIFY_REASON="True Peak ${VERIFY_OUTPUT_TRUE_PEAK} dBTP oltre ${VERIFY_MAX_TRUE_PEAK_DB} dBTP"
    return 1
  fi
  return 0
}

# Conserva i timestamp sorgente anche nel candidato solo audio, cosi' il mux
# mantiene l'offset audio/video. Il trim del retry segue tutto il DSP originale.
encode_audio_candidate() {
  local output_file="$1" graph="$2" trim="$3" output_label="[aout]"
  if awk -v trim="$trim" 'BEGIN { exit !(trim > 0) }'; then
    graph="${graph};[aout]volume=-${trim}dB[retry_out]"
    output_label="[retry_out]"
  fi
  local -a cmd=(ffmpeg -hide_banner -nostdin -stats -xerror -loglevel warning -y
    -copyts -i "$CUR_FILE" -filter_complex "$graph"
    -map "$output_label" -c:a:0 "$OUT_CODEC" -b:a:0 "$BITRATE"
    -dialnorm -31 -ar:a:0 48000 -ac:a:0 6
    -metadata:s:a:0 "title=$FINAL_AUDIO_TITLE" -disposition:a:0 default
    -avoid_negative_ts disabled)
  [[ -n "$A_LANG" && "${A_LANG,,}" != "und" ]] && cmd+=(-metadata:s:a:0 "language=$A_LANG")
  cmd+=("$output_file")
  "${cmd[@]}"
}

mux_verified_audio() {
  local output_file="$1" audio_file="$2"
  local -a cmd=(ffmpeg -hide_banner -nostdin -stats -xerror -loglevel warning -y
    -copyts -i "$CUR_FILE" -i "$audio_file"
    -map_metadata 0 -map_chapters 0
    -map "0:V:0?" -c:v copy -map "0:s?" -c:s copy -map "0:t?" -c:t copy
    -map "1:a:0" -c:a:0 copy
    -metadata:s:a:0 "title=$FINAL_AUDIO_TITLE" -disposition:a:0 default
    -avoid_negative_ts make_zero)
  if [[ "$KEEP_ORIGINAL" == "si" ]]; then
    cmd+=(-map "0:$ORIGINAL_INDEX" -c:a:1 copy
      -metadata:s:a:1 "title=$ORIGINAL_TITLE" -disposition:a:1 0)
  fi
  if [[ -n "$A_LANG" && "${A_LANG,,}" != "und" ]]; then
    cmd+=(-metadata:s:a:0 "language=$A_LANG")
    [[ "$KEEP_ORIGINAL" == "si" ]] && cmd+=(-metadata:s:a:1 "language=$A_LANG")
  fi
  cmd+=("$output_file")
  "${cmd[@]}"
}

# Directory riservata atomicamente nella cartella dell'output: nessuna collisione
# puo' far cancellare file altrui. Gli errori e le interruzioni conservano il debug.
# Gli script restano autonomi: questo flusso e' identico nei due processori.
process_verified_audio() {
  local graph="$1" work_dir candidate first_candidate mux_file rc trim="0.0"
  work_dir="$(mktemp -d "$(dirname -- "$OUT_FILE")/.$(basename -- "${OUT_FILE%.mkv}").partial.XXXXXX")" || {
    err "Impossibile riservare la directory temporanea"
    return 1
  }
  info "Temporanei: $work_dir"
  first_candidate="$work_dir/audio.mka"
  candidate="$first_candidate"
  mux_file="$work_dir/mux.mkv"
  if ! encode_audio_candidate "$candidate" "$graph" "$trim"; then
    err "Encoding audio fallito; temporanei conservati: $work_dir"
    return 1
  fi
  verify_audio_candidate "$candidate"
  rc=$?
  if [[ "$rc" -eq 1 && "$VERIFY_FAILURE_KIND" == "true_peak" ]]; then
    trim="$(awk -v tp="$VERIFY_OUTPUT_TRUE_PEAK" -v lim="$VERIFY_MAX_TRUE_PEAK_DB" \
      -v margin="$TRUE_PEAK_RETRY_MARGIN_DB" -v maximum="$TRUE_PEAK_MAX_AUTO_TRIM_DB" \
      'BEGIN { required=tp-lim+margin; printf "%.2f", (required < maximum ? required : maximum) }')"
    info "Retry unico dalla sorgente: trim finale -${trim} dB (massimo ${TRUE_PEAK_MAX_AUTO_TRIM_DB} dB)"
    candidate="$work_dir/audio.retry.mka"
    if ! encode_audio_candidate "$candidate" "$graph" "$trim"; then
      err "Retry audio fallito; temporanei conservati: $work_dir"
      return 1
    fi
    verify_audio_candidate "$candidate"
    rc=$?
  fi
  if (( rc != 0 )); then
    err "Verifica rifiutata/non conclusiva: $VERIFY_REASON"
    err "Nessun altro encode; output finale invariato. Temporanei: $work_dir"
    return 1
  fi
  info "Audio verificato: mux finale unico"
  if ! mux_verified_audio "$mux_file" "$candidate"; then
    err "Mux fallito; audio verificato e temporanei conservati: $work_dir"
    return 1
  fi
  if ! mv -f -- "$mux_file" "$OUT_FILE"; then
    err "Pubblicazione fallita; temporanei conservati: $work_dir"
    return 1
  fi
  # Soltanto file di questa esecuzione; mai pulizia ricorsiva o su nomi condivisi.
  rm -f -- "$first_candidate" "$work_dir/audio.retry.mka" || warn "Pulizia audio incompleta: $work_dir"
  rmdir -- "$work_dir" || warn "Directory temporanea conservata: $work_dir"
  ok "Creato e verificato (trim finale -${trim} dB): $OUT_FILE"
  return 0
}

trap 'warn "Interrotto: temporanei conservati per il debug"; exit 130' INT
trap 'warn "Terminato: temporanei conservati per il debug"; exit 143' TERM

# Raccolta file
FILES=()
if [[ "$MULTI_FILES_MODE" == true ]]; then
  for f in "${MULTI_FILES[@]}"; do
    if [[ -f "$f" ]]; then
      FILES+=("$f")
    else
      warn "File inesistente, salto: $f"
    fi
  done
elif [[ -z "$INPUT_ARG" ]]; then
  shopt -s nullglob
  FILES+=( *.mkv *.MKV *.mp4 *.MP4 *.m2ts *.M2TS )
  shopt -u nullglob
elif [[ -d "$INPUT_ARG" ]]; then
  shopt -s nullglob
  FILES+=( "$INPUT_ARG"/*.mkv "$INPUT_ARG"/*.MKV "$INPUT_ARG"/*.mp4 "$INPUT_ARG"/*.MP4 "$INPUT_ARG"/*.m2ts "$INPUT_ARG"/*.M2TS )
  shopt -u nullglob
elif [[ -f "$INPUT_ARG" ]]; then
  FILES+=("$INPUT_ARG")
else
  err "File o cartella non esiste: $INPUT_ARG"; exit 1
fi

# Filtra file gia' normalizzati (evita doppioni)
FILTERED_FILES=()
for f in "${FILES[@]}"; do
  case "$f" in
    *-0.mkv)
      info "Skip output gia' normalizzato: $f"
      continue
      ;;
    *)
      FILTERED_FILES+=("$f")
      ;;
  esac
done
FILES=("${FILTERED_FILES[@]}")

# Check se ci sono file da processare
(( ${#FILES[@]} == 0 )) && { err "Nessun file trovato."; exit 1; }
# Mostra info
info "Bitrate 5.1: $BITRATE"
info "dynaudnorm:  $DYNAUDNORM"
echo ""

# Ciclo elaborazione
OVERWRITE_ALL=false
OK_COUNT=0
ERR_COUNT=0
SKIP_COUNT=0

# Ciclo sui file
for CUR_FILE in "${FILES[@]}"; do
  info "━━━ Input: $CUR_FILE"

  # Trova traccia Atmos/EAC3
  PROBE_RESULT=$(find_atmos_stream "$CUR_FILE") || {
    warn "Nessuna traccia EAC3 a 6 canali trovata → salto."
    ((SKIP_COUNT+=1))
    continue
  }
  # Split probe result: idx|ch|lang|type|layout
  IFS='|' read -r A_IDX A_CH A_LANG A_TYPE A_LAYOUT <<<"$PROBE_RESULT"
  A_IDX="${A_IDX//[$'\r\n ']/}"
  A_CH="${A_CH//[$'\r\n ']/}"
  A_LANG="${A_LANG//$'\r'/}"

  info "Traccia audio: idx=$A_IDX, canali=$A_CH, lingua=$A_LANG, tipo=$A_TYPE"
  if [[ "$A_TYPE" == "atmos" ]]; then
    echo -e "${C_ATMOS_FOUND} RILEVATO - origine verificata tramite profilo FFprobe.\033[0m"
  fi

  # Come nel motore principale, il pan usa indici di canale espliciti. In questo
  # modo aformat non puo' rimappare automaticamente i sei canali quando il layout
  # e' assente, non standard oppure dichiarato come 5.1(back).
  case "$A_LAYOUT" in
    "5.1(side)")
      mapping "Layout input: 5.1(side) → copia posizionale pura c0..c5"
      ;;
    "5.1"|"5.1(back)")
      mapping "Layout input: ${A_LAYOUT} → copia posizionale pura; c4/c5 diventano SL/SR"
      ;;
    *)
      mapping "Layout audio '${A_LAYOUT:-unknown}': uso del mapping posizionale 5.1 c0..c5 (FC=c2, SL=c4, SR=c5)."
      ;;
  esac

  # Filename output
  OUT_FILE="${CUR_FILE%.*}-0.mkv"

  # Gestione sovrascrittura
  if [[ -f "$OUT_FILE" ]]; then
    if [[ "$OVERWRITE_ALL" == false ]]; then
      confirm_overwrite "$OUT_FILE" || { info "Salto '$CUR_FILE'."; ((SKIP_COUNT+=1)); continue; }
    else
      info "Sovrascrittura automatica: '$OUT_FILE'"
    fi
  fi

  # Filter complex per traccia 5.1: mapping posizionale non distruttivo, poi
  # dynaudnorm con coupling attivo. Nessun trattamento LFE: lo fa aegis.
  FILTER_COMPLEX="[0:${A_IDX}]aformat=sample_rates=48000:sample_fmts=fltp,pan=5.1(side)|FL=c0|FR=c1|FC=c2|LFE=c3|SL=c4|SR=c5,${DYNAUDNORM}[aout]"

  # Il riferimento viene misurato prima dell'encode. Se la sorgente non e'
  # misurabile in modo affidabile, non produciamo un output non verificabile.
  INPUT_AUDIO_METRICS="$(measure_audio_signal "$CUR_FILE" "0:${A_IDX}")" || {
    err "Impossibile misurare la traccia sorgente → salto: $CUR_FILE"
    ((ERR_COUNT+=1))
    continue
  }

  OUT_CODEC="eac3"
  FINAL_AUDIO_TITLE="EAC3 5.1 Normalized"
  KEEP_ORIGINAL="si"
  ORIGINAL_INDEX="$A_IDX"
  if [[ "$A_TYPE" == "atmos" ]]; then
    ORIGINAL_TITLE="EAC3 Atmos Original"
  else
    ORIGINAL_TITLE="EAC3 Original"
  fi
  if process_verified_audio "$FILTER_COMPLEX"; then
    ((OK_COUNT+=1))
  else
    ((ERR_COUNT+=1))
  fi
  echo ""
done

if (( ERR_COUNT > 0 )); then
  err "Elaborazione completata con errori: OK=$OK_COUNT, FALLITI=$ERR_COUNT, SALTATI=$SKIP_COUNT"
  exit 1
fi
if (( OK_COUNT == 0 )); then
  warn "Nessun file elaborato: SALTATI=$SKIP_COUNT"
  exit 0
fi
ok "Elaborazione completata: OK=$OK_COUNT, FALLITI=0, SALTATI=$SKIP_COUNT"

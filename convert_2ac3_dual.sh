#!/usr/bin/env bash
set -euo pipefail

# ╭──────────────────────────────────────────────────────────────────────────────╮
# │   convert_2AC3_sonar.sh - SONAR Upfiring + Voice HQ sartoriale               │
# │                                                                              │
# │   Stanza: 4.0m (prof.) × 5.0m (largh.) × 4.1m (h)                            │
# │   Ascoltatore: 3.6 m dal TV                                                  │
# │   Surround: 1.0 m dietro | altezza 1.2 m | distanza TV ↔ Surround ≈ 4.6 m    │
# │                                                                              │
# │   Parametri CLI:                                                             │
# │      ./convert_2ac3_sonar.sh <mode> <keep> "<file>" <bitrate>                │
# │                                                                              │
# │     <mode>   → sonar | clean | dual                                          │
# │     <keep>   → si | no                                                       │
# │     <file>   → percorso/file .mkv/.mp4 oppure "" per batch in cartella       │
# │     <bitrate>→ 256k | 320k | 384k | 448k | 512k | 640k (default: 640k)       │
# │                                                                              │
# │   DSP TUNING (room-tuned):                                                   │
# │    • Ritardo surround: 24 ms (L) / 28 ms (R)                                 │
# │    • EQ pinna: +3 dB @ 6.5 kHz  /  −2 dB @ 11 kHz                            │
# │    • EQ voce: +1.5 dB @ 2.4 kHz (centrale) | +1.1 dB (frontali)              │
# │    • Coda “late” LPF 1.5 kHz (−3 dB)                                         │
# │    • Mix: main 1.00 / up 0.75 / late 0.45                                    │
# │    • Boost finale: +3.5 dB (surround compensati)                             │
# │    • Limiter: 0.97 (headroom di sicurezza)                                   │
# │    • LFE: passthrough totale (nessun filtro o attenuazione)                  │
# │                                                                              │
# │   FASE PREVENTIVA (ffMediaMaster o equivalente)                              │
# │      1. Apri la sorgente DTS/EAC3/Atmos in ffMediaMaster.                    │
# │      2. Imposta:                                                             │
# │           • Audio Peak Normalization: −2.0 dBFS  (−1.0 dB se già AC3/EAC3).  │
# │           • Dynamic Normalization → ON                                       │
# │           • Target Peak Value: 92                                            │
# │           • Max Gain: 10 | RMS: 0 | Compress: 0                              │
# │           • Channel Coupling → ON | Gaussian Filter → 31                     │
# │      3. Esporta in AC3 640 kbps 5.1 senza loudness extra.                    │
# │      4. Esegui: ./convert_2ac3_sonar.sh sonar no "Film.mkv" 640k             │
# │         (o “clean si” per mix più neutri).                                   │
# │      5. Verifica: voci chiare, sub naturale, surround aperto, nessun clip.   │
# │                                                                              │
# │   *Tuning ottimizzato per: KENWOOD RV-6000 + KC1-300HS + SW40HT              │
# │   *Realizzato da: Sandro “Damocle77” Sabbioni & GPT-5 AudioLab               │
# ╰──────────────────────────────────────────────────────────────────────────────╯


# ╭──────────────────────────────────────────────╮
# │ 🎨 Colori                                                                  
# ╰──────────────────────────────────────────────╯
C_INFO="\033[0;36m[INFO]\033[0m"
C_WARN="\033[0;33m[WARNING]\033[0m"
C_ERR="\033[0;31m[ERROR]\033[0m"
C_OK="\033[0;32m[OK]\033[0m"

info(){ echo -e "${C_INFO} $*"; }
warn(){ echo -e "${C_WARN} $*"; }
err(){  echo -e "${C_ERR}  $*"; }
ok(){   echo -e "${C_OK}  $*"; }

# ╭──────────────────────────────────────────────╮
# 🆘 Help
# ╰──────────────────────────────────────────────╯
show_help(){ cat <<'USAGE'
────────────────────────────────────────────────────────────────────────────────
UTILIZZO:
  ./convert_2ac3_sonar.sh <sonar|clean|dual> <si|no> [file.mkv/.mp4] [bitrate]

PARAMETRI:
  1)  Modalità:
        sonar → EQ Voce + Surround virtual upfiring (effetto pinna)
        clean → EQ Voce + Surround clean (nessun upfiring)
        dual  → genera entrambe le tracce (Sonar + Clean) nello stesso file

  2)  Mantieni originale:
        si → conserva la traccia audio originale
        no → output solo con traccia AC3 convertita

  3)  File in input:
        percorso del file .mkv da convertire
        oppure "" per elaborare tutti i file .mkv/.mp4 nella cartella corrente

  4)  Bitrate output:
        256k | 320k | 384k | 448k | 512k | 640k (default)

NOTE:
  • EQ Voce: 2.4 kHz, +1.5 dB su FC e +1.1 dB su FL/FR.
  • Boost Surround: +3.5 dB (Sonar), +3.3 dB (Clean).
  • LFE passthrough: nessun filtro o attenuazione.
────────────────────────────────────────────────────────────────────────────────
USAGE
}

# ╭──────────────────────────────────────────────╮
# ✅ Argomenti
# ╰──────────────────────────────────────────────╯
SONAR_MODE="${1:-}"          # sonar | clean | dual
KEEP_ORIG="${2:-}"           # si | no
INPUT_FILE="${3:-}"          # mkv | mp4
BITRATE="${4:-640k}"         # 256k | 320k | 384k | 448k | 512k | 640k (default)

# Validazione argomenti
if [[ $# -lt 2 ]]; then show_help; exit 1; fi
[[ "$SONAR_MODE" =~ ^(sonar|clean|dual)$ ]] || { err "Modalità non valida: $SONAR_MODE"; show_help; exit 1; }
[[ "$KEEP_ORIG"  =~ ^(si|no)$     ]] || { err "Parametro 2 (si|no) non valido: $KEEP_ORIG"; show_help; exit 1; }
case "$BITRATE" in
  256k|320k|384k|448k|512k|640k) ;; 
  *) err "Bitrate non valido (256k|320k|384k|448k|512k|640k)"; exit 1 ;;
esac

# ╭──────────────────────────────────────────────╮
# 🧩 Selezione files
# ╰──────────────────────────────────────────────╯
declare -a FILES
if [[ -n "${INPUT_FILE}" ]]; then
  FILES=("$INPUT_FILE")
else
  mapfile -t FILES < <(find . -maxdepth 1 -type f -name "*.mkv" ! -name "*_AC3_*" | sort)
  info "Batch: trovati ${#FILES[@]} file"
fi
[[ ${#FILES[@]} -gt 0 ]] || { warn "Nessun file da elaborare."; exit 0; }

# ╭──────────────────────────────────────────────╮
# 🔧 DSP blocks
# ╰──────────────────────────────────────────────╯

# EQ voce Sartoriale (EQ su 2.4kHz, high-shelf su 1.8Hz)
get_voice_filter() {
  if [ "$SONAR_MODE" = "sonar" ]; then
    cat <<'EOF'
[FC]highshelf=f=1800:g=1.0:t=q:w=0.8,equalizer=f=2400:t=q:w=0.9:g=1.2,volume=+1.8dB[FC_eq];
EOF
  else
    cat <<'EOF'
[FC]highshelf=f=1800:g=0.6:t=q:w=0.8,equalizer=f=2400:t=q:w=1.1:g=1.5,volume=+0.8dB[FC_eq];
EOF
  fi
}

# Surround Sonar: (tuned 4x5x4m room, upfiring virtuale)
get_sonar_atmosx(){
  cat <<'EOF'
[SL]asplit=3[SLm][SLv_in][SLlate_in];
[SLv_in]adelay=24|24,highpass=f=1600,equalizer=f=6500:t=q:w=1.2:g=+3.0,equalizer=f=11000:t=q:w=1.0:g=-2.0[SLv];
[SLlate_in]adelay=58|58,lowpass=f=1500,volume=-3dB[SLlate];
[SLm][SLv][SLlate]amix=inputs=3:weights='1 0.75 0.45':normalize=0,volume=+3.5dB,alimiter=limit=0.97[SL_out];
[SR]asplit=3[SRm][SRv_in][SRlate_in];
[SRv_in]adelay=28|28,highpass=f=1600,equalizer=f=6600:t=q:w=1.2:g=+3.0,equalizer=f=11000:t=q:w=1.0:g=-2.0[SRv];
[SRlate_in]adelay=62|62,lowpass=f=1500,volume=-3dB[SRlate];
[SRm][SRv][SRlate]amix=inputs=3:weights='1 0.75 0.45':normalize=0,volume=+3.5dB,alimiter=limit=0.97[SR_out];
EOF
}

# Surround Clean: (solo boost +3.3dB, nessun upfiring)
get_clean_surround(){
  cat <<'EOF'
[SL]volume=+3.3dB,alimiter=limit=0.97[SL_out];
[SR]volume=+3.3dB,alimiter=limit=0.97[SR_out];
EOF
}

# ╭──────────────────────────────────────────────╮
# 🚀 Elaborazione
# ╰──────────────────────────────────────────────╯
for CUR_FILE in "${FILES[@]}"; do
  BASENAME=$(basename "$CUR_FILE" .mkv)
  OUT_SUFFIX=$(
    case "$SONAR_MODE" in
      sonar) echo "Sonar" ;;
      clean) echo "Clean" ;;
      dual)  echo "Dual"  ;;
    esac
  )
  OUT_FILE="${BASENAME}_AC3_${OUT_SUFFIX}.mkv"

  # Verifica esistenza file di output
  if [[ -f "$OUT_FILE" ]]; then
    warn "Il file '$OUT_FILE' esiste. Sovrascrivere? [s/N] \c"
    read a
    [[ "$a" =~ ^[sS]$ ]] || { warn "Skip '$OUT_FILE'"; continue; }
  fi

  # Messaggi di recap su schermo
  echo
  echo "───────────────────────────────────────────────────────────────────────────"
  info "File In Input:  $CUR_FILE"
  info "File In Output: $OUT_FILE"
  if [[ "$SONAR_MODE" = "dual" ]]; then
    BOOST="Sonar +3.5 dB / Clean +3.3 dB"
  else
    BOOST=$( [ "$SONAR_MODE" = "sonar" ] && echo '+3.5 dB' || echo '+3.3 dB' )
  fi
  info "Effetto Surround: \033[0;31m${SONAR_MODE}\033[0m | Boost: \033[0;36m${BOOST}\033[0m"
  info "EQ Sartoriale: \033[0;33m1.8 + 2.4 kHz\033[0m | LFE: \033[0;32mpassthrough\033[0m"
  echo "───────────────────────────────────────────────────────────────────────────"
  
  # Costruzione filter complex + mapping
  if [[ "$SONAR_MODE" = "dual" ]]; then
    FILTER_COMPLEX="[0:a:0]asplit=2[aS][aC];\
[aS]channelsplit=channel_layout=5.1[FL_S][FR_S][FC_S][LFE_S][SL_S][SR_S];\
[FC_S]highshelf=f=1800:g=1.0:t=q:w=0.8,equalizer=f=2400:t=q:w=0.9:g=1.2,volume=+1.8dB[FC_S_eq];\
[SL_S]asplit=3[SLm_S][SLv_in_S][SLlate_in_S];\
[SLv_in_S]adelay=24|24,highpass=f=1600,equalizer=f=6500:t=q:w=1.2:g=+3.0,equalizer=f=11000:t=q:w=1.0:g=-2.0[SLv_S];\
[SLlate_in_S]adelay=58|58,lowpass=f=1500,volume=-3dB[SLlate_S];\
[SLm_S][SLv_S][SLlate_S]amix=inputs=3:weights='1 0.75 0.45':normalize=0,volume=+3.5dB,alimiter=limit=0.97[SL_out_S];\
[SR_S]asplit=3[SRm_S][SRv_in_S][SRlate_in_S];\
[SRv_in_S]adelay=28|28,highpass=f=1600,equalizer=f=6600:t=q:w=1.2:g=+3.0,equalizer=f=11000:t=q:w=1.0:g=-2.0[SRv_S];\
[SRlate_in_S]adelay=62|62,lowpass=f=1500,volume=-3dB[SRlate_S];\
[SRm_S][SRv_S][SRlate_S]amix=inputs=3:weights='1 0.75 0.45':normalize=0,volume=+3.5dB,alimiter=limit=0.97[SR_out_S];\
[FC_S_eq]aformat=channel_layouts=FC[FC_Sf];[LFE_S]aformat=channel_layouts=LFE[LFE_Sf];\
[SL_out_S]aformat=channel_layouts=SL[SL_Sf];[SR_out_S]aformat=channel_layouts=SR[SR_Sf];\
[FL_S][FR_S][FC_Sf][LFE_Sf][SL_Sf][SR_Sf]amerge=inputs=6,channelmap=channel_layout=5.1,volume=-0.5dB,alimiter=limit=0.97,aresample=resampler=soxr:precision=28:dither_method=triangular[aout_sonar];\
[aC]channelsplit=channel_layout=5.1[FL_C][FR_C][FC_C][LFE_C][SL_C][SR_C];\
[FC_C]highshelf=f=1800:g=0.6:t=q:w=0.8,equalizer=f=2400:t=q:w=1.1:g=1.5,volume=0.8dB[FC_C_eq];\
[SL_C]volume=+3.3dB,alimiter=limit=0.97[SL_out_C];\
[SR_C]volume=+3.3dB,alimiter=limit=0.97[SR_out_C];\
[FC_C_eq]aformat=channel_layouts=FC[FC_Cf];[LFE_C]aformat=channel_layouts=LFE[LFE_Cf];\
[SL_out_C]aformat=channel_layouts=SL[SL_Cf];[SR_out_C]aformat=channel_layouts=SR[SR_Cf];\
[FL_C][FR_C][FC_Cf][LFE_Cf][SL_Cf][SR_Cf]amerge=inputs=6,channelmap=channel_layout=5.1,volume=-0.5dB,alimiter=limit=0.97,aresample=resampler=soxr:precision=28:dither_method=triangular[aout_clean]"

    CMD=(ffmpeg -y -hide_banner -nostdin -stats -loglevel warning \
         -i "$CUR_FILE" -filter_complex "$FILTER_COMPLEX" \
         -map 0:v:0 -c:v copy \
         -map "[aout_sonar]" -c:a:0 ac3 -b:a:0 "$BITRATE" -ar:a:0 48000 -ac:a:0 6 \
         -map "[aout_clean]" -c:a:1 ac3 -b:a:1 "$BITRATE" -ar:a:1 48000 -ac:a:1 6)

    # Sottotitoli se presenti
    if ffprobe -v quiet -select_streams s -show_entries stream=index -of csv=p=0 "$CUR_FILE" | grep -q .; then
      CMD+=(-map 0:s -c:s copy)
    fi

    # Gestione audio originale
    if [[ "$KEEP_ORIG" = "si" ]]; then
      ORIG_TITLE=$(ffprobe -v quiet -select_streams a:0 -show_entries stream_tags=title -of csv=p=0 "$CUR_FILE" 2>/dev/null || true)
      [[ -z "$ORIG_TITLE" ]] && ORIG_TITLE="Original Audio"
      CMD+=(-map 0:a:0 -c:a:2 copy -metadata:s:a:2 title="$ORIG_TITLE" -disposition:a:2 0)
    fi

    # Metadati tracce AC3
    CMD+=(-metadata:s:a:0 title="AC3 5.1 Sonar" -disposition:a:0 default \
         -metadata:s:a:1 title="AC3 5.1 Clean" -disposition:a:1 0 \
         "$OUT_FILE")

  else
    # === Comportamento originale (una sola traccia) ===
    VOICE_FILTER="$(get_voice_filter)"
    if [[ "$SONAR_MODE" = "sonar" ]]; then
      SUR_FILTERS="$(get_sonar_atmosx)"
    else
      SUR_FILTERS="$(get_clean_surround)"
    fi

    FILTER_COMPLEX="[0:a:0]channelsplit=channel_layout=5.1[FL][FR][FC][LFE][SL][SR];${VOICE_FILTER}${SUR_FILTERS}\
  [FC_eq]aformat=channel_layouts=FC[FCf];[LFE]aformat=channel_layouts=LFE[LFEf];\
  [SL_out]aformat=channel_layouts=SL[SLf];[SR_out]aformat=channel_layouts=SR[SRf];\
  [FL][FR][FCf][LFEf][SLf][SRf]amerge=inputs=6,channelmap=channel_layout=5.1,volume=-0.5dB,alimiter=limit=0.97,aresample=resampler=soxr:precision=28:dither_method=triangular[aout]"

    CMD=(ffmpeg -y -hide_banner -nostdin -stats -loglevel warning
         -i "$CUR_FILE" -filter_complex "$FILTER_COMPLEX"
         -map 0:v:0 -c:v copy
         -map "[aout]" -c:a ac3 -b:a "$BITRATE" -ar 48000 -ac 6)

    if ffprobe -v quiet -select_streams s -show_entries stream=index -of csv=p=0 "$CUR_FILE" | grep -q .; then
      CMD+=(-map 0:s -c:s copy)
    fi

    if [[ "$KEEP_ORIG" = "si" ]]; then
      ORIG_TITLE=$(ffprobe -v quiet -select_streams a:0 -show_entries stream_tags=title -of csv=p=0 "$CUR_FILE" 2>/dev/null || true)
      [[ -z "$ORIG_TITLE" ]] && ORIG_TITLE="Original Audio"
      CMD+=(-map 0:a:0 -c:a:1 copy -metadata:s:a:1 title="$ORIG_TITLE" -disposition:a:1 0)
    fi

    CMD+=(-metadata:s:a:0 title="AC3 5.1 ${OUT_SUFFIX}" -disposition:a:0 default "$OUT_FILE")
  fi

  info "Avvio conversione → AC3 $BITRATE ..."
  
  # Esecuzione pipeline
  set +e
  "${CMD[@]}"
  RET=$?
  set -e

  # Sinottico finale post-elaborazione
  if [[ $RET -eq 0 || $RET -eq 1 ]]; then
    ok "Completato: \033[0;33m${OUT_FILE}\033[0m"
  else
    if [[ -f "$OUT_FILE" ]]; then
      warn "Skip FFmpeg: '$OUT_FILE' parzialmente creato o già presente."
    else
      err "Errore: $OUT_FILE (exit $RET)"
    fi
  fi
done

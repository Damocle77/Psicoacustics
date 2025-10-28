#!/usr/bin/env bash
set -euo pipefail
# ----------------------------------------------------------------------------------------------------
# converti_2ac3_sonar.sh  —  TUTTO-IN-UNO (wrapper + core) • FFmpeg virtual upfiring
# ----------------------------------------------------------------------------------------------------
# USO (posizionali):
#   ./converti_2ac3_sonar.sh <sonar|clean> <si|no> <file.mkv> [bitrate] [neuralx|atmosx]
#
# SIGNIFICATO
#   arg1 = surround mode: "sonar" (upfiring SL/SR) oppure "clean" (no upfiring)
#   arg2 = conserva traccia audio ORIGINALE: "si" oppure "no"
#   arg3 = file di input .mkv (prima traccia audio 5.1)
#   arg4 = bitrate AC-3 (opz., default 640k) → 320k|448k|640k
#   arg5 = voicing (opz., vale solo se arg1=sonar): "neuralx" | "atmosx"
#
# COSA FA
#   • Ricodifica audio in AC-3 5.1 (48 kHz), copiando video e sottotitoli.
#   • EQ voce SEMPRE su FL/FR/FC (FC +0.6 dB; FL/FR +0.3 dB @ 2.4 kHz).
#   • Upfiring SOLO sui surround (SL/SR) in modalità "sonar"; "clean" = niente upfiring.
#   • Boost surround auto: +3.2 dB (sonar) / +2.9 dB (clean).
#   • LFE SEMPRE con HPF a 22 Hz (nessun preset/trim).
#
# CONSIGLI (upfiring/voicing per "sonar")
#   • neuralx → cupola ampia/spettacolare: Star Wars, MCU/Marvel, Transformers, F&F, Pacific Rim.
#   • atmosx  → cupola più focalizzata/precisa: Alien, Blade Runner 2049, Dune, The Batman, Tenet.
# ----------------------------------------------------------------------------------------------------
#
# NOTE:
# - Il video viene copiato (pass-through). I sottotitoli, se presenti, vengono copiati.
# - L'uscita è sempre AC-3 5.1 con naming fisso: _AC3_sonar_neuralx / _AC3_sonar_atmosx / _AC3_clean.
# - Richiede ffmpeg e ffprobe nel PATH.
# ----------------------------------------------------------------------------------------------------

# Help a schermo
if [[ $# -lt 3 ]] || [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  sed -n '1,80p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi

# Parse posizionali
SUR_MODE="$1"; shift                                    # sonar | clean
KEEP="$1"; shift                                        # si | no
INPUT_FILE="$1"; shift                                  # percorso file .mkv
BITRATE="${1:-640k}"; [[ $# -gt 0 ]] && shift || true
VOICE_UI="${1:-neuralx}"                                # neuralx | atmosx (solo se sonar)

# Validazioni
case "$SUR_MODE" in sonar|clean) ;; *) echo "[ERR] arg1 deve essere sonar|clean" >&2; exit 2;; esac
case "$KEEP" in si|no) ;; *) echo "[ERR] arg2 deve essere si|no" >&2; exit 2;; esac
[[ -f "$INPUT_FILE" ]] || { echo "[ERR] File non trovato: $INPUT_FILE" >&2; exit 2; }
case "$BITRATE" in 320k|448k|640k) ;; *) echo "[ERR] bitrate non valido (320k|448k|640k)" >&2; exit 2;; esac
case "$VOICE_UI" in neuralx|atmosx) ;; *) echo "[ERR] voicing non valido (neuralx|atmosx)" >&2; exit 2;; esac

# Dipendenze
command -v ffmpeg >/dev/null || { echo "[ERR] ffmpeg non trovato" >&2; exit 3; }
command -v ffprobe >/dev/null || { echo "[ERR] ffprobe non trovato" >&2; exit 3; }

# Voicing interno per i surround SONAR
MODE="neuralx"                                  # default
if [[ "$SUR_MODE" = "sonar" && "$VOICE_UI" = "atmosx" ]]; then MODE="atmos"; fi

# robe layout 5.1 e normalizzazione a 5.1(side)
IN_LAYOUT="$(ffprobe -v error -select_streams a:0 -show_entries stream=channel_layout -of csv=p=0 "$INPUT_FILE" || true)"
CH_CNT="$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of csv=p=0 "$INPUT_FILE" || true)"
[[ -z "$IN_LAYOUT" ]] && IN_LAYOUT="5.1"
[[ "$CH_CNT" = "6" ]] || { echo "[ERR] La prima traccia non è 5.1 (ch=$CH_CNT)" >&2; exit 4; }

case "$IN_LAYOUT" in
  "5.1"|"5.1(side)") PAN_NORMALIZE="[0:a:0]anullref[ain];";;
  "5.1(back)")       PAN_NORMALIZE="[0:a:0]pan=FL|c0=c0,anull[aFL];[0:a:0]pan=FR|c0=c1,anull[aFR];[0:a:0]pan=FC|c0=c2,anull[aFC];[0:a:0]pan=LFE|c0=c3,anull[aLFE];[0:a:0]pan=SL|c0=c4,anull[aSL];[0:a:0]pan=SR|c0=c5,anull[aSR];[aFL][aFR][aFC][aLFE][aSL][aSR]amerge=inputs=6[ain];";; # back→side
  *)                 PAN_NORMALIZE="[0:a:0]anullref[ain];";;
esac

# Voice-EQ SEMPRE attiva su FL/FR/FC
VOICE_FILTER='[FC]equalizer=f=2400:t=q:w=1.0:g=0.6[FC_eq];[FL]equalizer=f=2400:t=q:w=1.0:g=0.3[FL_eq];[FR]equalizer=f=2400:t=q:w=1.0:g=0.3[FR_eq];'

# LFE: HPF 22 Hz SEMPRE (anti-rumble)
LFE_FILTER='[LFE]highpass=f=22[LFE_clean];'


# --- Funzioni surround ----------------------------------------------------------------------------------------------------

# Funzione: surround upfiring stile NeuralX (cupola ampia/spettacolare)
get_sonar_neuralx(){ cat <<'EOF'
# SL: split in dry/side/front/up/late/decor
[SL]asplit=6[SL_dry][SL_side_in][SL_front_in][SL_up_in][SL_late_in][SL_decor_in];
# SL: riflessione laterale (~6 ms)
[SL_side_in]adelay=6,  volume=-6dB[SL_side];
# SL: riflessione frontale (~10 ms)
[SL_front_in]adelay=10, volume=-7dB[SL_front];
# SL: componente upfiring (HRTF leggera)
[SL_up_in]adelay=17, highpass=f=1500, bandpass=f=4600:t=q:w=1.7, allpass=f=3300:t=q:w=0.7:mix=1.0, equalizer=f=9000:t=q:w=1.2:g=-2.0, volume=+0.5dB[SL_up];
# SL: coda diffusa/late energy
[SL_late_in]adelay=46, highpass=f=1500, bandpass=f=5200:t=q:w=1.8, allpass=f=3800:t=q:w=0.6:mix=1.0, lowpass=f=5800, volume=-11dB[SL_late];
# SL: decorrelazione lieve
[SL_decor_in]adelay=3, allpass=f=2800:t=q:w=0.7:mix=1.0, volume=-14dB[SL_decor];
# SL: ramo dry
[SL_dry]anull[SL_d0];
# SL: mix finale pesato (dry+early+up+late+decor)
[SL_d0][SL_side][SL_front][SL_up][SL_late][SL_decor]amix=inputs=6:weights=1 0.22 0.22 0.36 0.19 0.11:normalize=0[SL_sum];
# SL: lieve echo di sala + boost + limiter
[SL_sum]aecho=0.14:0.08:17:0.030, volume=+3.2dB, alimiter=limit=0.97[SL_out];

# SR: piccolo ITD (0.25 ms) per ampiezza
[SR]adelay=0.25, asplit=6[SR_dry][SR_side_in][SR_front_in][SR_up_in][SR_late_in][SR_decor_in];
# SR: riflessione laterale (~7 ms)
[SR_side_in]adelay=7,  volume=-6dB[SR_side];
# SR: riflessione frontale (~10 ms)
[SR_front_in]adelay=10, volume=-7dB[SR_front];
# SR: componente upfiring (HRTF leggera)
[SR_up_in]adelay=18, highpass=f=1500, bandpass=f=4700:t=q:w=1.7, allpass=f=3500:t=q:w=0.7:mix=1.0, equalizer=f=9000:t=q:w=1.2:g=-2.0, volume=+0.5dB[SR_up];
# SR: coda diffusa/late energy
[SR_late_in]adelay=49, highpass=f=1500, bandpass=f=5400:t=q:w=1.8, allpass=f=4000:t=q:w=0.6:mix=1.0, lowpass=f=5800, volume=-11dB[SR_late];
# SR: decorrelazione lieve
[SR_decor_in]adelay=3.2, allpass=f=3000:t=q:w=0.7:mix=1.0, volume=-14dB[SR_decor];
# SR: ramo dry
[SR_dry]anull[SR_d0];
# SR: mix finale pesato (dry+early+up+late+decor)
[SR_d0][SR_side][SR_front][SR_up][SR_late][SR_decor]amix=inputs=6:weights=1 0.22 0.22 0.36 0.19 0.11:normalize=0[SR_sum];
# SR: lieve echo di sala + boost + limiter
[SR_sum]aecho=0.14:0.08:19:0.030, volume=+3.2dB, alimiter=limit=0.97[SR_out];
EOF
}

# Funzione: surround upfiring stile AtmosX (più focalizzato/preciso)
get_sonar_atmosx(){ cat <<'EOF'
# SL: split in dry/side/front/up/late
[SL]asplit=5[SL_dry][SL_side_in][SL_front_in][SL_up_in][SL_late_in];
# SL: riflessione laterale (~6 ms)
[SL_side_in]adelay=6,   volume=-7dB[SL_side];
# SL: riflessione frontale (~10 ms)
[SL_front_in]adelay=10, volume=-8dB[SL_front];
# SL: componente upfiring (HRTF leggera)
[SL_up_in]adelay=17, highpass=f=1600, bandpass=f=4400:t=q:w=1.5, allpass=f=3400:t=q:w=0.6:mix=1.0, equalizer=f=9000:t=q:w=1.0:g=-2.0, volume=+0.5dB[SL_up];
# SL: coda diffusa/late energy
[SL_late_in]adelay=38, highpass=f=1600, bandpass=f=5200:t=q:w=1.6, allpass=f=3700:t=q:w=0.5:mix=1.0, lowpass=f=5800, volume=-11dB[SL_late];
# SL: ramo dry
[SL_dry]anull[SL_d0];
# SL: mix finale pesato (dry+early+up+late)
[SL_d0][SL_side][SL_front][SL_up][SL_late]amix=inputs=5:weights=1 0.35 0.35 0.55 0.25:normalize=0[SL_sum];
# SL: lieve echo di sala + boost + limiter
[SL_sum]aecho=0.12:0.07:17:0.028, volume=+3.2dB, alimiter=limit=0.97[SL_out];

# SR: piccolo ITD (0.25 ms) per ampiezza
[SR]adelay=0.25, asplit=5[SR_dry][SR_side_in][SR_front_in][SR_up_in][SR_late_in];
# SR: riflessione laterale (~7 ms)
[SR_side_in]adelay=7,   volume=-7dB[SR_side];
# SR: riflessione frontale (~10 ms)
[SR_front_in]adelay=10, volume=-8dB[SR_front];
# SR: componente upfiring (HRTF leggera)
[SR_up_in]adelay=18, highpass=f=1600, bandpass=f=4500:t=q:w=1.5, allpass=f=3600:t=q:w=0.6:mix=1.0, equalizer=f=9000:t=q:w=1.0:g=-2.0, volume=+0.5dB[SR_up];
# SR: coda diffusa/late energy
[SR_late_in]adelay=40, highpass=f=1600, bandpass=f=5400:t=q:w=1.6, allpass=f=3900:t=q:w=0.5:mix=1.0, lowpass=f=5800, volume=-11dB[SR_late];
# SR: ramo dry
[SR_dry]anull[SR_d0];
# SR: mix finale pesato (dry+early+up+late)
[SR_d0][SR_side][SR_front][SR_up][SR_late]amix=inputs=5:weights=1 0.35 0.35 0.55 0.25:normalize=0[SR_sum];
# SR: lieve echo di sala + boost + limiter
[SR_sum]aecho=0.12:0.07:19:0.028, alimiter=limit=0.97, volume=+3.2dB[SR_out];
EOF
}

# Funzione: surround clean (nessun upfiring, boost + limiter)
get_clean(){ cat <<'EOF'
[SL]volume=+2.9dB, alimiter=limit=0.97[SL_out];
[SR]volume=+2.9dB, alimiter=limit=0.97[SR_out];
EOF
}

# Selezione catena surround (SONAR/CLEAN)
if [[ "$SUR_MODE" = "sonar" ]]; then
  if [[ "$MODE" = "atmos" ]]; then SUR_FILTERS="$(get_sonar_atmosx)"; else SUR_FILTERS="$(get_sonar_neuralx)"; fi
else
  SUR_FILTERS="$(get_clean)"
fi


# --- Filtergraph completo -------------------------------------------------------------------------------------------------

read -r -d '' FILTER_COMPLEX <<EOF || true
[0:a:0]anullref[ain];
${PAN_NORMALIZE}
[ain]channelsplit=channel_layout=5.1[FL][FR][FC][LFE][SL][SR];

# Voice-EQ (sempre attiva su FL/FR/FC)
[FC]equalizer=f=2400:t=q:w=1.0:g=0.6[FC_eq];
[FL]equalizer=f=2400:t=q:w=1.0:g=0.3[FL_eq];
[FR]equalizer=f=2400:t=q:w=1.0:g=0.3[FR_eq];

# LFE: HPF 22 Hz fisso
${LFE_FILTER}

# Surround (sonar/clean)
${SUR_FILTERS}

# Merge → 5.1(side)
[FL_eq]aformat=channel_layouts=mono[FLf];
[FR_eq]aformat=channel_layouts=mono[FRf];
[FC_eq]aformat=channel_layouts=mono[FCf];
[LFE_clean]aformat=channel_layouts=mono[LFEf];
[SL_out]aformat=channel_layouts=mono[SLf];
[SR_out]aformat=channel_layouts=mono[SRf];
[FLf][FRf][FCf][LFEf][SLf][SRf]amerge=inputs=6[a_merged];
[a_merged]channelmap=channel_layout=5.1(side):map=0-FL|1-FR|2-FC|3-LFE|4-SL|5-SR[a_mapped];
[a_mapped]aresample=resampler=soxr:precision=28:dither_method=triangular[aout]
EOF

# Naming fisso dell'output
stem="${INPUT_FILE%.*}"
if [[ "$SUR_MODE" = "sonar" ]]; then
  if [[ "$MODE" = "atmos" ]]; then OUTPUT_FILE="${stem}_AC3_sonar_atmosx.mkv"; else OUTPUT_FILE="${stem}_AC3_sonar_neuralx.mkv"; fi
else
  OUTPUT_FILE="${stem}_AC3_clean.mkv"
fi


# --- Comando ffmpeg -------------------------------------------------------------------------------------------------------

CMD=(ffmpeg -y -hide_banner -nostdin -loglevel error \
     -i "$INPUT_FILE" -filter_complex "$FILTER_COMPLEX" \
     -map 0:v:0 -c:v copy \
     -map "[aout]" -c:a ac3 -b:a "$BITRATE" -ar 48000 -ac 6)

# Copia sottotitoli se presenti
if ffprobe -v quiet -select_streams s -show_entries stream=index -of csv=p=0 "$INPUT_FILE" | grep -q .; then
  CMD+=(-map 0:s -c:s copy)
fi

# Mantieni traccia audio originale (se richiesto)
if [[ "$KEEP" = "si" ]]; then
  ORIG_TITLE="$(ffprobe -v quiet -select_streams a:0 -show_entries stream_tags=title -of csv=p=0 "$INPUT_FILE" 2>/dev/null || true)"
  [[ -z "$ORIG_TITLE" ]] && ORIG_TITLE="Original Audio"
  CMD+=(-map 0:a:0 -c:a:1 copy -metadata:s:a:1 title="$ORIG_TITLE" -disposition:a:1 none)
fi

# Metadata parlante
CMD+=(-metadata:s:a:0 title="AC3 5.1 ${SUR_MODE^} ${MODE} + VoiceEQ (SL/SR boost auto; LFE HPF 22 Hz)" \
      -disposition:a:0 default -map_metadata 0 -map_chapters 0 "$OUTPUT_FILE")

# --- Esecuzione -------------------------------------------------------------------------------------------------------------
exec "${CMD[@]}"

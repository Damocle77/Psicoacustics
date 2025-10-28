#!/usr/bin/env bash
set -euo pipefail
# =====================================================================================
# convert_2ac3_sonar_2x.sh  —  TUTTO-IN-UNO (wrapper + core) • FFmpeg virtual upfiring
# -------------------------------------------------------------------------------------
# USO (posizionali):
#   ./convert_2ac3_sonar_2x.sh <sonar|clean|dualx> <si|no> <file.mkv> [bitrate] [neuralx|atmosx]
#
# SIGNIFICATO
#   arg1 = modalità:
#          - "sonar"  → upfiring SL/SR (scegli il voicing con arg5: neuralx|atmosx)
#          - "clean"  → nessun upfiring (solo boost controllato dei surround)
#          - "dualx"  → crea DUE tracce AC-3 5.1 (NeuralX + AtmosX) nello stesso MKV
#   arg2 = conserva traccia audio ORIGINALE: "si" oppure "no"
#   arg3 = file di input .mkv (prima traccia audio 5.1)
#   arg4 = bitrate AC-3 (opz., default 640k) → 320k|448k|640k
#   arg5 = voicing (opz., vale solo se arg1=sonar): "neuralx" | "atmosx"
#
# COSA FA (sempre)
#   • Ricodifica audio in AC-3 5.1 (48 kHz), copiando video e sottotitoli.
#   • EQ voce SEMPRE su FL/FR/FC (FC +0.6 dB; FL/FR +0.3 dB @ 2.4 kHz).
#   • Upfiring SOLO sui surround (SL/SR) in modalità "sonar"/"dualx"; "clean" = niente upfiring.
#   • Boost surround: +3.2 dB (sonar/dualx) / +2.9 dB (clean).
#   • LFE SEMPRE con HPF a 22 Hz.
#
# CONSIGLI rapidi (voicing per "sonar")
#   • neuralx → cupola ampia/spettacolare (Star Wars, MCU, Transformers, F&F, Pacific Rim).
#   • atmosx  → cupola focalizzata/precisa (Alien, Blade Runner 2049, Dune, The Batman, Tenet, A Quiet Place).
# =====================================================================================

# --- Help a schermo robusto (funziona anche su Git Bash) ---
if [[ $# -lt 3 ]] || [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "help" ]]; then
  cat <<'HELP'
convert_2ac3_sonar_2x.sh  —  TUTTO-IN-UNO (FFmpeg virtual upfiring)

USO (posizionali):
  ./convert_2ac3_sonar_2x.sh <sonar|clean|dualx> <si|no> <file.mkv> [bitrate] [neuralx|atmosx]

SIGNIFICATO
  arg1 = modalità:
         - "sonar"  → upfiring SL/SR (scegli il voicing con arg5: neuralx|atmosx)
         - "clean"  → nessun upfiring (solo boost controllato dei surround)
         - "dualx"  → crea DUE tracce AC-3 5.1 (NeuralX + AtmosX) nello stesso MKV
  arg2 = conserva traccia audio ORIGINALE: "si" oppure "no"
  arg3 = file di input .mkv (prima traccia audio 5.1)
  arg4 = bitrate AC-3 (opz., default 640k) → 320k|448k|640k
  arg5 = voicing (opz., vale solo se arg1=sonar): "neuralx" | "atmosx"

COSA FA (sempre)
  • Ricodifica audio in AC-3 5.1 (48 kHz), copiando video e sottotitoli.
  • EQ voce SEMPRE su FL/FR/FC (FC +0.6 dB; FL/FR +0.3 dB @ 2.4 kHz).
  • Upfiring SOLO sui surround (SL/SR) in modalità "sonar"/"dualx"; "clean" = niente upfiring.
  • Boost surround: +3.2 dB (sonar/dualx) / +2.9 dB (clean).
  • LFE SEMPRE con HPF a 22 Hz.

OUTPUT
  • sonar + neuralx → <nome>_AC3_sonar_neuralx.mkv
  • sonar + atmosx  → <nome>_AC3_sonar_atmosx.mkv
  • clean           → <nome>_AC3_clean.mkv
  • dualx           → <nome>_AC3_sonar_dualx.mkv   (NeuralX default + AtmosX)

ESEMPI
  ./convert_2ac3_sonar_2x.sh sonar no   "Avengers.mkv" 640k neuralx
  ./convert_2ac3_sonar_2x.sh sonar si   "Alien.mkv"    640k atmosx
  ./convert_2ac3_sonar_2x.sh clean no   "Terminator.mkv"
  ./convert_2ac3_sonar_2x.sh dualx no   "Fast_X.mkv"   640k
  ./convert_2ac3_sonar_2x.sh dualx si   "Dune.mkv"     640k

NOTE
  - Video e sottotitoli vengono copiati.
  - Richiede ffmpeg e ffprobe nel PATH.
HELP
  exit 2
fi

# --- Parse posizionali ---
SUR_MODE="$1"; shift            # sonar | clean | dualx
KEEP="$1"; shift                # si | no
INPUT_FILE="$1"; shift          # file .mkv
BITRATE="${1:-640k}"; [[ $# -gt 0 ]] && shift || true
VOICE_UI="${1:-neuralx}"        # neuralx | atmosx (solo se sonar)

# --- Validazioni ---
case "$SUR_MODE" in sonar|clean|dualx) ;; *) echo "[ERR] arg1 deve essere sonar|clean|dualx" >&2; exit 2;; esac
case "$KEEP" in si|no) ;; *) echo "[ERR] arg2 deve essere si|no" >&2; exit 2;; esac
[[ -f "$INPUT_FILE" ]] || { echo "[ERR] File non trovato: $INPUT_FILE" >&2; exit 2; }
case "$BITRATE" in 320k|448k|640k) ;; *) echo "[ERR] bitrate non valido (320k|448k|640k)" >&2; exit 2;; esac
if [[ "$SUR_MODE" == "sonar" ]]; then
  case "$VOICE_UI" in neuralx|atmosx) ;; *) echo "[ERR] voicing non valido (neuralx|atmosx)" >&2; exit 2;; esac
fi

# --- Dipendenze ---
command -v ffmpeg >/dev/null || { echo "[ERR] ffmpeg non trovato" >&2; exit 3; }
command -v ffprobe >/dev/null || { echo "[ERR] ffprobe non trovato" >&2; exit 3; }

# --- Probe layout e normalizzazione a 5.1(side) ---
IN_LAYOUT="$(ffprobe -v error -select_streams a:0 -show_entries stream=channel_layout -of csv=p=0 "$INPUT_FILE" || true)"
CH_CNT="$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of csv=p=0 "$INPUT_FILE" || true)"
[[ -z "$IN_LAYOUT" ]] && IN_LAYOUT="5.1"
[[ "$CH_CNT" = "6" ]] || { echo "[ERR] La prima traccia non è 5.1 (ch=$CH_CNT)" >&2; exit 4; }

case "$IN_LAYOUT" in
  "5.1"|"5.1(side)")
    PAN_NORMALIZE="[0:a:0]anullref[ain];"
    ;;
  "5.1(back)")
    # Remap BL/BR -> SL/SR
    PAN_NORMALIZE="[0:a:0]channelmap=channel_layout=5.1(side):map=FL-FL|FR-FR|FC-FC|LFE-LFE|BL-SL|BR-SR[ain];"
    ;;
  *)
    PAN_NORMALIZE="[0:a:0]anullref[ain];"
    ;;
esac

# --- Blocchi fissi ---
VOICE_FILTER='[FC]equalizer=f=2400:t=q:w=1.0:g=0.6[FC_eq];[FL]equalizer=f=2400:t=q:w=1.0:g=0.3[FL_eq];[FR]equalizer=f=2400:t=q:w=1.0:g=0.3[FR_eq];'
LFE_FILTER='[LFE]highpass=f=22[LFE_clean];'

# === Funzioni surround ========================================================
# SINGLE-BRANCH (usa etichette [SL]/[SR] e produce [SL_out]/[SR_out])
get_sonar_neuralx(){ cat <<'EOF'
[SL]asplit=6[SL_dry][SL_side_in][SL_front_in][SL_up_in][SL_late_in][SL_decor_in];
[SL_side_in]adelay=6,  volume=-6dB[SL_side];
[SL_front_in]adelay=10, volume=-7dB[SL_front];
[SL_up_in]adelay=17, highpass=f=1500, bandpass=f=4600:t=q:w=1.7, allpass=f=3300:t=q:w=0.7:mix=1.0, equalizer=f=9000:t=q:w=1.2:g=-2.0, volume=+0.5dB[SL_up];
[SL_late_in]adelay=46, highpass=f=1500, bandpass=f=5200:t=q:w=1.8, allpass=f=3800:t=q:w=0.6:mix=1.0, lowpass=f=5800, volume=-11dB[SL_late];
[SL_decor_in]adelay=3, allpass=f=2800:t=q:w=0.7:mix=1.0, volume=-14dB[SL_decor];
[SL_dry]anull[SL_d0];
[SL_d0][SL_side][SL_front][SL_up][SL_late][SL_decor]amix=inputs=6:weights=1 0.22 0.22 0.36 0.19 0.11:normalize=0[SL_sum];
[SL_sum]aecho=0.14:0.08:17:0.030, volume=+3.2dB, alimiter=limit=0.97[SL_out];

[SR]adelay=0.25, asplit=6[SR_dry][SR_side_in][SR_front_in][SR_up_in][SR_late_in][SR_decor_in];
[SR_side_in]adelay=7,  volume=-6dB[SR_side];
[SR_front_in]adelay=10, volume=-7dB[SR_front];
[SR_up_in]adelay=18, highpass=f=1500, bandpass=f=4700:t=q:w=1.7, allpass=f=3500:t=q:w=0.7:mix=1.0, equalizer=f=9000:t=q:w=1.2:g=-2.0, volume=+0.5dB[SR_up];
[SR_late_in]adelay=49, highpass=f=1500, bandpass=f=5400:t=q:w=1.8, allpass=f=4000:t=q:w=0.6:mix=1.0, lowpass=f=5800, volume=-11dB[SR_late];
[SR_decor_in]adelay=3.2, allpass=f=3000:t=q:w=0.7:mix=1.0, volume=-14dB[SR_decor];
[SR_dry]anull[SR_d0];
[SR_d0][SR_side][SR_front][SR_up][SR_late][SR_decor]amix=inputs=6:weights=1 0.22 0.22 0.36 0.19 0.11:normalize=0[SR_sum];
[SR_sum]aecho=0.14:0.08:19:0.030, volume=+3.2dB, alimiter=limit=0.97[SR_out];
EOF
}

get_sonar_atmosx(){ cat <<'EOF'
[SL]asplit=5[SL_dry][SL_side_in][SL_front_in][SL_up_in][SL_late_in];
[SL_side_in]adelay=6,   volume=-7dB[SL_side];
[SL_front_in]adelay=10, volume=-8dB[SL_front];
[SL_up_in]adelay=17, highpass=f=1600, bandpass=f=4400:t=q:w=1.5, allpass=f=3400:t=q:w=0.6:mix=1.0, equalizer=f=9000:t=q:w=1.0:g=-2.0, volume=+0.5dB[SL_up];
[SL_late_in]adelay=38, highpass=f=1600, bandpass=f=5200:t=q:w=1.6, allpass=f=3700:t=q:w=0.5:mix=1.0, lowpass=f=5800, volume=-11dB[SL_late];
[SL_dry]anull[SL_d0];
[SL_d0][SL_side][SL_front][SL_up][SL_late]amix=inputs=5:weights=1 0.35 0.35 0.55 0.25:normalize=0[SL_sum];
[SL_sum]aecho=0.12:0.07:17:0.028, volume=+3.2dB, alimiter=limit=0.97[SL_out];

[SR]adelay=0.25, asplit=5[SR_dry][SR_side_in][SR_front_in][SR_up_in][SR_late_in];
[SR_side_in]adelay=7,   volume=-7dB[SR_side];
[SR_front_in]adelay=10, volume=-8dB[SR_front];
[SR_up_in]adelay=18, highpass=f=1600, bandpass=f=4500:t=q:w=1.5, allpass=f=3600:t=q:w=0.6:mix=1.0, equalizer=f=9000:t=q:w=1.0:g=-2.0, volume=+0.5dB[SR_up];
[SR_late_in]adelay=40, highpass=f=1600, bandpass=f=5400:t=q:w=1.6, allpass=f=3900:t=q:w=0.5:mix=1.0, lowpass=f=5800, volume=-11dB[SR_late];
[SR_dry]anull[SR_d0];
[SR_d0][SR_side][SR_front][SR_up][SR_late]amix=inputs=5:weights=1 0.35 0.35 0.55 0.25:normalize=0[SR_sum];
[SR_sum]aecho=0.12:0.07:19:0.028, volume=+3.2dB, alimiter=limit=0.97[SR_out];
EOF
}

get_clean(){ cat <<'EOF'
[SL]volume=+2.9dB, alimiter=limit=0.97[SL_out];
[SR]volume=+2.9dB, alimiter=limit=0.97[SR_out];
EOF
}

# DUAL-BRANCH (etichette indipendenti per evitare collisioni)
get_sonar_neuralx_dual(){ cat <<'EOF'
[SLn]asplit=6[SLn_dry][SLn_side_in][SLn_front_in][SLn_up_in][SLn_late_in][SLn_decor_in];
[SLn_side_in]adelay=6,  volume=-6dB[SLn_side];
[SLn_front_in]adelay=10, volume=-7dB[SLn_front];
[SLn_up_in]adelay=17, highpass=f=1500, bandpass=f=4600:t=q:w=1.7, allpass=f=3300:t=q:w=0.7:mix=1.0, equalizer=f=9000:t=q:w=1.2:g=-2.0, volume=+0.5dB[SLn_up];
[SLn_late_in]adelay=46, highpass=f=1500, bandpass=f=5200:t=q:w=1.8, allpass=f=3800:t=q:w=0.6:mix=1.0, lowpass=f=5800, volume=-11dB[SLn_late];
[SLn_decor_in]adelay=3, allpass=f=2800:t=q:w=0.7:mix=1.0, volume=-14dB[SLn_decor];
[SLn_dry]anull[SLn_d0];
[SLn_d0][SLn_side][SLn_front][SLn_up][SLn_late][SLn_decor]amix=inputs=6:weights=1 0.22 0.22 0.36 0.19 0.11:normalize=0[SLn_sum];
[SLn_sum]aecho=0.14:0.08:17:0.030, volume=+3.2dB, alimiter=limit=0.97[SLn_out];

[SRn]adelay=0.25, asplit=6[SRn_dry][SRn_side_in][SRn_front_in][SRn_up_in][SRn_late_in][SRn_decor_in];
[SRn_side_in]adelay=7,  volume=-6dB[SRn_side];
[SRn_front_in]adelay=10, volume=-7dB[SRn_front];
[SRn_up_in]adelay=18, highpass=f=1500, bandpass=f=4700:t=q:w=1.7, allpass=f=3500:t=q:w=0.7:mix=1.0, equalizer=f=9000:t=q:w=1.2:g=-2.0, volume=+0.5dB[SRn_up];
[SRn_late_in]adelay=49, highpass=f=1500, bandpass=f=5400:t=q:w=1.8, allpass=f=4000:t=q:w=0.6:mix=1.0, lowpass=f=5800, volume=-11dB[SRn_late];
[SRn_decor_in]adelay=3.2, allpass=f=3000:t=q:w=0.7:mix=1.0, volume=-14dB[SRn_decor];
[SRn_dry]anull[SRn_d0];
[SRn_d0][SRn_side][SRn_front][SRn_up][SRn_late][SRn_decor]amix=inputs=6:weights=1 0.22 0.22 0.36 0.19 0.11:normalize=0[SRn_sum];
[SRn_sum]aecho=0.14:0.08:19:0.030, volume=+3.2dB, alimiter=limit=0.97[SRn_out];
EOF
}

get_sonar_atmosx_dual(){ cat <<'EOF'
[SLa]asplit=5[SLa_dry][SLa_side_in][SLa_front_in][SLa_up_in][SLa_late_in];
[SLa_side_in]adelay=6,   volume=-7dB[SLa_side];
[SLa_front_in]adelay=10, volume=-8dB[SLa_front];
[SLa_up_in]adelay=17, highpass=f=1600, bandpass=f=4400:t=q:w=1.5, allpass=f=3400:t=q:w=0.6:mix=1.0, equalizer=f=9000:t=q:w=1.0:g=-2.0, volume=+0.5dB[SLa_up];
[SLa_late_in]adelay=38, highpass=f=1600, bandpass=f=5200:t=q:w=1.6, allpass=f=3700:t=q:w=0.5:mix=1.0, lowpass=f=5800, volume=-11dB[SLa_late];
[SLa_dry]anull[SLa_d0];
[SLa_d0][SLa_side][SLa_front][SLa_up][SLa_late]amix=inputs=5:weights=1 0.35 0.35 0.55 0.25:normalize=0[SLa_sum];
[SLa_sum]aecho=0.12:0.07:17:0.028, volume=+3.2dB, alimiter=limit=0.97[SLa_out];

[SRa]adelay=0.25, asplit=5[SRa_dry][SRa_side_in][SRa_front_in][SRa_up_in][SRa_late_in];
[SRa_side_in]adelay=7,   volume=-7dB[SRa_side];
[SRa_front_in]adelay=10, volume=-8dB[SRa_front];
[SRa_up_in]adelay=18, highpass=f=1600, bandpass=f=4500:t=q:w=1.5, allpass=f=3600:t=q:w=0.6:mix=1.0, equalizer=f=9000:t=q:w=1.0:g=-2.0, volume=+0.5dB[SRa_up];
[SRa_late_in]adelay=40, highpass=f=1600, bandpass=f=5400:t=q:w=1.6, allpass=f=3900:t=q:w=0.5:mix=1.0, lowpass=f=5800, volume=-11dB[SRa_late];
[SRa_dry]anull[SRa_d0];
[SRa_d0][SRa_side][SRa_front][SRa_up][SRa_late]amix=inputs=5:weights=1 0.35 0.35 0.55 0.25:normalize=0[SRa_sum];
[SRa_sum]aecho=0.12:0.07:19:0.028, volume=+3.2dB, alimiter=limit=0.97[SRa_out];
EOF
}

# === Filtergraph in base alla modalità =======================================

if [[ "$SUR_MODE" == "dualx" ]]; then
  read -r -d '' FILTER_COMPLEX <<EOF || true
[0:a:0]anullref[ain];
${PAN_NORMALIZE}
[ain]asplit=2[aNeu][aAtm];

# --- NeuralX ---
[aNeu]channelsplit=channel_layout=5.1[FLn][FRn][FCn][LFEn][SLn][SRn];
[FCn]equalizer=f=2400:t=q:w=1.0:g=0.6[FCn_eq];
[FLn]equalizer=f=2400:t=q:w=1.0:g=0.3[FLn_eq];
[FRn]equalizer=f=2400:t=q:w=1.0:g=0.3[FRn_eq];
[LFEn]highpass=f=22[LFEn_clean];
$(get_sonar_neuralx_dual)
[FLn_eq]aformat=channel_layouts=mono[FLnf];
[FRn_eq]aformat=channel_layouts=mono[FRnf];
[FCn_eq]aformat=channel_layouts=mono[FCnf];
[LFEn_clean]aformat=channel_layouts=mono[LFEnf];
[SLn_out]aformat=channel_layouts=mono[SLnf];
[SRn_out]aformat=channel_layouts=mono[SRnf];
[FLnf][FRnf][FCnf][LFEnf][SLnf][SRnf]amerge=inputs=6[aNeu_m];
[aNeu_m]channelmap=channel_layout=5.1(side):map=0-FL|1-FR|2-FC|3-LFE|4-SL|5-SR[aout_neuralx];

# --- AtmosX ---
[aAtm]channelsplit=channel_layout=5.1[FLa][FRa][FCa][LFEa][SLa][SRa];
[FCa]equalizer=f=2400:t=q:w=1.0:g=0.6[FCa_eq];
[FLa]equalizer=f=2400:t=q:w=1.0:g=0.3[FLa_eq];
[FRa]equalizer=f=2400:t=q:w=1.0:g=0.3[FRa_eq];
[LFEa]highpass=f=22[LFEa_clean];
$(get_sonar_atmosx_dual)
[FLa_eq]aformat=channel_layouts=mono[FLaf];
[FRa_eq]aformat=channel_layouts=mono[FRaf];
[FCa_eq]aformat=channel_layouts=mono[FCaf];
[LFEa_clean]aformat=channel_layouts=mono[LFEaf];
[SLa_out]aformat=channel_layouts=mono[SLaf];
[SRa_out]aformat=channel_layouts=mono[SRaf];
[FLaf][FRaf][FCaf][LFEaf][SLaf][SRaf]amerge=inputs=6[aAtm_m];
[aAtm_m]channelmap=channel_layout=5.1(side):map=0-FL|1-FR|2-FC|3-LFE|4-SL|5-SR[aout_atmosx];
EOF

else
  MODE="neuralx"
  if [[ "$SUR_MODE" = "sonar" && "$VOICE_UI" = "atmosx" ]]; then MODE="atmos"; fi

  if [[ "$SUR_MODE" = "sonar" ]]; then
    if [[ "$MODE" = "atmos" ]]; then SUR_FILTERS="$(get_sonar_atmosx)"; else SUR_FILTERS="$(get_sonar_neuralx)"; fi
  else
    SUR_FILTERS="$(get_clean)"
  fi

  read -r -d '' FILTER_COMPLEX <<EOF || true
[0:a:0]anullref[ain];
${PAN_NORMALIZE}
[ain]channelsplit=channel_layout=5.1[FL][FR][FC][LFE][SL][SR];

# Voice-EQ (sempre su FL/FR/FC)
${VOICE_FILTER}

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
[a_merged]channelmap=channel_layout=5.1(side):map=0-FL|1-FR|2-FC|3-LFE|4-SL|5-SR[aout]
EOF
fi

# --- Comando ffmpeg / mapping / naming ---------------------------------------
stem="${INPUT_FILE%.*}"
CMD=(ffmpeg -y -hide_banner -nostdin -loglevel error -i "$INPUT_FILE" -filter_complex "$FILTER_COMPLEX" -map 0:v:0 -c:v copy)

# copia sottotitoli se presenti
if ffprobe -v quiet -select_streams s -show_entries stream=index -of csv=p=0 "$INPUT_FILE" | grep -q .; then
  CMD+=(-map 0:s -c:s copy)
fi

if [[ "$SUR_MODE" == "dualx" ]]; then
  OUTPUT_FILE="${stem}_AC3_sonar_dualx.mkv"
  if [[ "$KEEP" = "si" ]]; then
    ORIG_TITLE="$(ffprobe -v quiet -select_streams a:0 -show_entries stream_tags=title -of csv=p=0 "$INPUT_FILE" 2>/dev/null || true)"
    [[ -z "$ORIG_TITLE" ]] && ORIG_TITLE="Original Audio"
    CMD+=(-map 0:a:0 -c:a:0 copy -metadata:s:a:0 title="$ORIG_TITLE" -disposition:a:0 none)
    CMD+=(-map "[aout_neuralx]" -c:a:1 ac3 -b:a:1 "$BITRATE" -ar:a:1 48000 -ac:a:1 6 -metadata:s:a:1 title="AC3 5.1 Sonar NeuralX + VoiceEQ (LFE HPF 22 Hz)" -disposition:a:1 default)
    CMD+=(-map "[aout_atmosx]"  -c:a:2 ac3 -b:a:2 "$BITRATE" -ar:a:2 48000 -ac:a:2 6 -metadata:s:a:2 title="AC3 5.1 Sonar AtmosX + VoiceEQ (LFE HPF 22 Hz)" -disposition:a:2 none)
  else
    CMD+=(-map "[aout_neuralx]" -c:a:0 ac3 -b:a:0 "$BITRATE" -ar:a:0 48000 -ac:a:0 6 -metadata:s:a:0 title="AC3 5.1 Sonar NeuralX + VoiceEQ (LFE HPF 22 Hz)" -disposition:a:0 default)
    CMD+=(-map "[aout_atmosx]"  -c:a:1 ac3 -b:a:1 "$BITRATE" -ar:a:1 48000 -ac:a:1 6 -metadata:s:a:1 title="AC3 5.1 Sonar AtmosX + VoiceEQ (LFE HPF 22 Hz)" -disposition:a:1 none)
  fi
  CMD+=(-map_metadata 0 -map_chapters 0 "$OUTPUT_FILE")
else
  if [[ "$SUR_MODE" = "sonar" ]]; then
    if [[ "${VOICE_UI:-neuralx}" = "atmosx" ]]; then
      OUTPUT_FILE="${stem}_AC3_sonar_atmosx.mkv"
      TRACK_TITLE="AC3 5.1 Sonar AtmosX + VoiceEQ (SL/SR boost; LFE HPF 22 Hz)"
    else
      OUTPUT_FILE="${stem}_AC3_sonar_neuralx.mkv"
      TRACK_TITLE="AC3 5.1 Sonar NeuralX + VoiceEQ (SL/SR boost; LFE HPF 22 Hz)"
    fi
  else
    OUTPUT_FILE="${stem}_AC3_clean.mkv"
    TRACK_TITLE="AC3 5.1 Clean + VoiceEQ (SL/SR boost; LFE HPF 22 Hz)"
  fi

  CMD+=(-map "[aout]" -c:a ac3 -b:a "$BITRATE" -ar 48000 -ac 6 -metadata:s:a:0 title="$TRACK_TITLE" -disposition:a:0 default)
  if [[ "$KEEP" = "si" ]]; then
    ORIG_TITLE="$(ffprobe -v quiet -select_streams a:0 -show_entries stream_tags=title -of csv=p=0 "$INPUT_FILE" 2>/dev/null || true)"
    [[ -z "$ORIG_TITLE" ]] && ORIG_TITLE="Original Audio"
    CMD+=(-map 0:a:0 -c:a:1 copy -metadata:s:a:1 title="$ORIG_TITLE" -disposition:a:1 none)
  fi
  CMD+=(-map_metadata 0 -map_chapters 0 "$OUTPUT_FILE")
fi

exec "${CMD[@]}"

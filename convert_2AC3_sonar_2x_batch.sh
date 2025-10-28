#!/usr/bin/env bash
set -euo pipefail
# ────────────────────────────────────────────────────────────
#  convert_2AC3_sonar_2x_batch.sh
#  Batch launcher per converti_2ac3_sonar_2x.sh
#  Firma compatibile: <sonar|clean|dualx> <si|no> [bitrate] [neuralx|atmosx] [file?]
# ────────────────────────────────────────────────────────────

MAIN="converti_2ac3_sonar_2x.sh"

if [[ $# -lt 2 ]] || [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "help" ]]; then
  cat <<'HELP'
convert_2AC3_sonar_2x_batch.sh — batch per il wrapper 2x

USO (posizionali):
  ./convert_2AC3_sonar_2x_batch.sh <sonar|clean|dualx> <si|no> [bitrate] [neuralx|atmosx] [file.mkv]

ESEMPI
  # Batch di tutti i MKV nella cartella, sonar+neuralx, 640k
  ./convert_2AC3_sonar_2x_batch.sh sonar no 640k neuralx

  # Batch dualx (genera NeuralX + AtmosX in ogni MKV)
  ./convert_2AC3_sonar_2x_batch.sh dualx no 640k

  # Singolo file specifico (passa come 5° argomento)
  ./convert_2AC3_sonar_2x_batch.sh sonar si 640k atmosx "/percorso/Film.mkv"
HELP
  exit 2
fi

MODE="$1"; shift          # sonar | clean | dualx
KEEP="$1"; shift          # si | no
BITRATE="${1:-640k}"; [[ $# -gt 0 ]] && shift || true
VOICING="${1:-neuralx}"; [[ $# -gt 0 ]] && shift || true
ONEFILE="${1:-}"

command -v bash >/dev/null || { echo "[ERR] bash non trovato"; exit 1; }
[[ -f "$MAIN" ]] || { echo "[ERR] $MAIN non trovato (posiziona questo batch nella stessa cartella)"; exit 1; }

run_one() {
  local file="$1"
  echo ">>> Elaboro: ${file##*/}"
  if [[ "$MODE" == "sonar" ]]; then
    bash "$MAIN" "$MODE" "$KEEP" "$file" "$BITRATE" "$VOICING"
  else
    bash "$MAIN" "$MODE" "$KEEP" "$file" "$BITRATE"
  fi
  echo ">>> Fatto: ${file##*/}"
  echo "──────────────────────────────────────────────"
}

if [[ -n "$ONEFILE" ]]; then
  [[ -f "$ONEFILE" ]] || { echo "[ERR] File non trovato: $ONEFILE"; exit 1; }
  run_one "$ONEFILE"
  exit 0
fi

mapfile -t mkv_files < <(find . -maxdepth 1 -type f -iname "*.mkv" | sort -V)
total=${#mkv_files[@]}
if (( total == 0 )); then
  echo "Nessun file MKV trovato nella directory corrente."
  exit 0
fi

echo "──────────────────────────────────────────────"
echo "Batch attivo | MODE=$MODE | KEEP=$KEEP | BITRATE=$BITRATE | VOICING=$VOICING"
echo "File trovati: $total"
echo "──────────────────────────────────────────────"

start=$(date +%s)
i=0
for f in "${mkv_files[@]}"; do
  ((i++))
  echo "[ $i / $total ]"
  run_one "$f"
done
end=$(date +%s)
dur=$(( end - start ))
printf "Batch completato in %dm %ds\n" $((dur/60)) $((dur%60))

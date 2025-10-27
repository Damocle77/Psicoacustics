#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────
#  convert_2AC3_sonar_batch.sh                                
#  Batch launcher per convert_2AC3_sonar.sh               
#  Compatibile con nuova versione (5 argomenti)   
#  ./convert_2AC3_sonar_batch.sh sonar no eac36 640k           
# ────────────────────────────────────────────────────────────

SCRIPT_DA_ESEGUIRE="convert_2AC3_sonar.sh"

# ──────────────────────────────────────────────
# ⚠️ Verifica script principale
# ──────────────────────────────────────────────
if [ ! -f "$SCRIPT_DA_ESEGUIRE" ]; then
    echo "Errore: $SCRIPT_DA_ESEGUIRE non trovato. Controlla la directory."
    exit 1
fi

# ──────────────────────────────────────────────
# 🧭 Argomenti
# ──────────────────────────────────────────────
SONAR_MODE="$1"          # sonar | clean
KEEP_ORIG="$2"           # si | no
PRESET="$3"              # atmos|dts|eac37|eac36|ac3
BITRATE="${4:-640k}"     # default 640k
SPECIFIC_FILE="${5:-}"   # opzionale

# ──────────────────────────────────────────────
# 🧪 Processo singolo file
# ──────────────────────────────────────────────
if [[ -n "$SPECIFIC_FILE" && -f "$SPECIFIC_FILE" ]]; then
    echo ">>> Elaborazione singolo file: ${SPECIFIC_FILE}"
    bash "$SCRIPT_DA_ESEGUIRE" "$SONAR_MODE" "$KEEP_ORIG" "$SPECIFIC_FILE" "$PRESET" "$BITRATE"
    echo ">>> Completato: ${SPECIFIC_FILE}"
    exit 0
fi

# ──────────────────────────────────────────────
# 🗂️ Se non è stato passato un file → batch mode
# ──────────────────────────────────────────────
mapfile -t mkv_files < <(find . -maxdepth 1 -type f -name "*.mkv" | sort -V)
total_files=${#mkv_files[@]}

if [ $total_files -eq 0 ]; then
    echo "Nessun file MKV trovato nella directory corrente."
    exit 0
fi

echo "──────────────────────────────────────────────"
echo "Modalità batch attiva"
echo "File trovati: $total_files"
echo "Modalità surround: $SONAR_MODE | Preset: $PRESET | Bitrate: $BITRATE"
echo "──────────────────────────────────────────────"

processed_files=0
batch_start_time=$(date +%s)

for file in "${mkv_files[@]}"; do
    ((processed_files++))
    echo ">>> [$processed_files/$total_files] Elaborazione: ${file##*/}"
    bash "$SCRIPT_DA_ESEGUIRE" "$SONAR_MODE" "$KEEP_ORIG" "$file" "$PRESET" "$BITRATE"
    echo ">>> Fatto: ${file##*/}"
    echo "──────────────────────────────────────────────"
done

# ──────────────────────────────────────────────
# ⏱️ Timer finale
# ──────────────────────────────────────────────
batch_end_time=$(date +%s)
duration=$((batch_end_time - batch_start_time))
minutes=$((duration / 60))
seconds=$((duration % 60))

echo "Batch completato!"
echo "File elaborati: $processed_files / $total_files"
echo "Tempo totale: ${minutes}m ${seconds}s"
echo "──────────────────────────────────────────────"

#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <file.mkv>"
  exit 1
fi

FILE="$1"
if [[ ! -f "$FILE" ]]; then
  echo "❌ File non trovato: $FILE"
  exit 1
fi

echo "🔊 Elenco tracce audio per: $FILE"
echo "─────────────────────────────────────────────────"

ffprobe -v error -select_streams a \
  -show_entries stream=index,codec_name,channels,channel_layout,bit_rate,sample_rate:stream_tags=language,title \
  -of default=noprint_wrappers=1:nokey=1 \
  "$FILE" | \
awk '
  # bufferizziamo ogni riga
  { buf[NR] = $0 }
  END {
    # sappiamo che ogni blocco è di 8 righe
    for (i = 1; i <= NR; i += 8) {
      idx        = buf[i]
      codec      = buf[i+1]
      nch        = buf[i+2]
      layout     = buf[i+3]
      br         = buf[i+4]
      sr         = buf[i+5]
      lang       = buf[i+6]
      title      = buf[i+7]

      if (br == "" || br == "N/A") br = "n/a"
      if (sr == "" ) sr = "n/a"

      printf "🔊 Stream #%s (audio)\n", idx
      printf "    Codec       : %s\n", codec
      printf "    Canali      : %s (%s)\n", nch, layout
      printf "    Bitrate     : %s bps\n", br
      printf "    Sample rate : %s Hz\n", sr
      if (lang  != "") printf "    Lingua      : %s\n", lang
      if (title != "") printf "    Title tag   : %s\n", title
      print "────────────────────────────────────────────────────────────────"
    }
  }
'

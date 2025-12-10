<p align="left">
  <img src="sonary_logo.png" width="600" alt="Sonary Suite Logo">
</p>

# 🎧 Sonary Suite – Yamaha V4A Edition  
DSP avanzato per tracce 5.1 con modalità **Clean** e **Sonar** Upfiring  
Ottimizzato per **Yamaha RX-V4A** in modalità *Straight*.

> "Non tutti i supereroi indossano un mantello... a volte usano `filter_complex` per salvare il mondo del 5.1."  
> ⚡ by Sandro “D@mocle77” Sabbioni ⚡

---

# ✅ Requisiti

### Software necessari
- **FFmpeg 7+** con supporto SOXR  
- **Bash 4.x+**  
- **MKVToolNix** *(opzionale)*  

### Sistema operativo
- Linux / macOS  
- Windows tramite **WSL2** o Git-Bash  

### Hardware consigliato
- Yamaha **RX-V4A**  
- Impianto **5.1** con surround simmetrici  
- Distanza di ascolto: 3–4 m  
- Stanza 4×5 m  

---

# 🚀 Installazione

```
git clone https://github.com/Damocle77/Sonar_AC3D.git
cd Sonar_AC3D
chmod +x convert_sonary.sh
```

---

# 🎚️ EQ Voce Universale (FC)

L’EQ Voce è **sempre attiva** per garantire intelligibilità e corpo sul canale centrale senza alterare il carattere originale.

Curve attuale:

- **+3.5 dB @ 1 kHz**  
- **+5.0 dB @ 2.5 kHz**  
- **Volume finale: +1 dB**

Estratto dallo script:

```
[FC]equalizer=f=1000:t=q:w=1.0:g=3.5,
     equalizer=f=2500:t=q:w=1.0:g=5.0,
     volume=1dB[FCv];
```

---

# 🔊 Modalità Surround

## 1️⃣ Modalità **Clean**
Surround pulito, arioso, controllato.

Caratteristiche:
- High-shelf 3.5 kHz (g = 0.8)  
- Delay 3 ms  
- Volume 1.30  
- Limiter 0.99  

Estratto:
```
[SL]adelay=3,highshelf=f=3500:g=0.8:t=q:w=0.8,volume=1.30,alimiter=limit=0.99[SL_out];
```

---

## 2️⃣ Modalità **Sonar**
Effetto upfiring virtuale stile *Atmos-height*, ottenuto tramite split multilivello e micro-ritardi.

Caratteristiche:
- Triplo split (base / verticale / late)  
- Delay 34 ms + 78 ms  
- High-pass 1600 Hz  
- Presenza 6.5 kHz +3.5 dB  
- Mix 1 : 0.70 : 0.40  
- Limiter 0.99  
- Volume 1.40  

Estratto:
```
[SL]asplit=3[SLm][SLv_in][SLlate_in];
[SLv_in]adelay=34,highpass=f=1600,equalizer=f=6500:t=q:w=1.2:g=3.5 ...
```

---

# 🧩 Utilizzo

```
./convert_sonary.sh <ac3|eac3> <si|no> [file] [bitrate] [sonar|clean]
```

### Parametri
- **Codec output:** `ac3` | `eac3`  
- **Mantieni traccia originale:** `si` | `no`  
- **File:** singolo file o `""` per batch  
- **Bitrate:** 640k / 768k / 896k...  
  - Default: **640k per AC3** • **768k per EAC3**  
- **Modalità surround:** `sonar` | `clean`

### Esempi

```
./convert_sonary.sh ac3 no "film.mkv" 640k sonar
./convert_sonary.sh eac3 si "" 768k clean
```

---

# 🔁 Elaborazione Batch

Lascia vuoto il parametro file per convertire tutti i video nella cartella:

```
./convert_sonary.sh eac3 no "" 768k sonar
```

File supportati: `*.mkv *.mp4 *.m2ts`

---

# 📐 Layout Consigliato

<p align="left">
  <img src="Sonar_Room_Layout.png" width="650" alt="Sonary Room Layout">
</p>

- Surround a 110–120°  
- Center a 130–150 cm  
- Distanza 3–4 m  

---

# 🎥 Compatibilità AVR

- Ottimizzato per **Yamaha RX-V4A**  
- Funziona al meglio in modalità **Straight**  
- Nessuna interferenza con YPAO  
- **LFE invariato**  

---

# 📄 Licenza
MIT License.

> "Per riportare ordine nella Forza Sonora serve solo uno script Bash… questa è la via."


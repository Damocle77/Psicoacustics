<p align="left">
  <img src="sonary_logo.png" width="600" alt="Sonary Suite Logo">
</p>

# 🎧 Sonary Suite – Sonar & Wide Edition  
DSP avanzato per tracce **5.1** con due modalità surround: **Sonar** (upfiring psicoacustico) e **Wide** (widening psicoacustico).  
Pensato per AVR in modalità *Straight / Pure / Direct* (ottimizzato su Yamaha RX‑V4A).

> "Non tutti i supereroi indossano un mantello... a volte usano `-filter_complex` per salvare il mondo del 5.1."  
> ⚡ D@mocle77 | Sandro Sabbioni | ∑(logic) ⚡

---

## ✅ Requisiti

### Software
- **FFmpeg 7+** (con resampler **SOXR** abilitato)
- **Bash 4.x+**
- **MKVToolNix** *(opzionale, solo per operazioni extra sugli MKV)*

### Sistemi operativi
- Linux / macOS  
- Windows tramite **WSL2** o **Git‑Bash**

### Hardware consigliato (ma non obbligatorio)
- AVR (es. Yamaha **RX‑V4A**)  
- Impianto **5.1** con surround simmetrici  
- Distanza di ascolto: 3–4 m  
- Stanza “media” tipo 4×5 m  

---

## 🚀 Installazione

```bash
git clone https://github.com/Damocle77/Sonar_AC3D.git
cd Sonar_AC3D
chmod +x sonarwide.sh
```

---

## 🧠 Cosa fa (in breve)

- Converte una traccia **5.1** (AC3/EAC3/DTS/TrueHD…) in **AC3** o **EAC3**
- Applica DSP **solo sui surround** in modalità **Sonar** o **Wide**
- Applica una **EQ Voce** sul canale **Centrale (FC)** *(sempre attiva)*
- Mantiene **video** e **sottotitoli** in copia
- **LFE invariato** • **FL/FR neutri**

---

## 🎚️ EQ Voce Sartoriale (FC)

L’EQ Voce è **sempre attiva** per massimizzare intelligibilità e presenza del dialogo senza “segare” troppo l’originale.

Parametri attuali (come nello script):
- **-1.2 dB @ 350 Hz**
- **+2.2 dB @ 1 kHz**
- **+2.6 dB @ 2.5 kHz**
- **-0.6 dB @ 7.2 kHz**
- **Gain finale: +0.9 dB**
- **Limiter: 0.99**

Estratto:

```bash
[FC]equalizer=f=350:t=q:w=1.0:g=-1.2,
     equalizer=f=1000:t=q:w=1.0:g=2.2,
     equalizer=f=2500:t=q:w=1.0:g=2.6,
     equalizer=f=7200:t=q:w=1.1:g=-0.6,
     volume=0.9dB,
     alimiter=limit=0.99[FCv];
```

---

## 🔊 Modalità Surround

### 1️⃣ Wide (widening/ariosità controllata)
Obiettivo: surround più **ampi** e **avvolgenti**, senza “vetro” e senza rubare la scena ai frontali.

Come funziona (schema):
- **Direct** (0 ms) + **Early** (≈9–10 ms) + **Diffuse** (≈22–24 ms)
- Bandi di lavoro controllate (highpass/lowpass) + **allpass** per diffusione
- Shelving leggero: **+0.6 dB @ 180 Hz** e **+0.1 dB @ 3.5 kHz**
- **Limiter 0.99** (anti-clipping)

Estratto (SL, SR analogo):

```bash
[SL]asplit=3[SLd_in][SLe_in][SLx_in];
[SLd_in]adelay=0,volume=1.00[SLd];
[SLe_in]adelay=9,highpass=f=300,lowpass=f=7000,allpass=f=1200:t=q:w=0.65,volume=0.42[SLe];
[SLx_in]adelay=22,highpass=f=600,lowpass=f=5000,allpass=f=700:t=q:w=0.70,allpass=f=2600:t=q:w=0.70,volume=0.17[SLx];
[SLd][SLe][SLx]amix=inputs=3:weights='1.00 0.90 0.80':normalize=0,
  lowshelf=f=180:g=0.6:t=q:w=0.7,
  highshelf=f=3500:g=0.1:t=q:w=0.8,
  volume=1.30,alimiter=limit=0.99[SL_out];
```

---

### 2️⃣ Sonar (upfiring psicoacustico)
Obiettivo: creare un “accenno di altezza” stile upfiring/height **senza toccare i frontali**, usando split, micro‑ritardi e shaping in alta frequenza.

Come funziona (schema):
- **Direct** + layer “presence/height” + layer “high diffuse” + **late tail**
- Micro‑ritardi tipici: **14 ms**, **28 ms**, **85 ms**
- HPF su layer “height” (≈1.5 kHz / 2.5 kHz), LPF su late tail (≈1.5 kHz)
- **Limiter 0.99**

Estratto (SL, SR analogo):

```bash
[SL]asplit=4[SLd_in][SLp_in][SLh_in][SLlate_in];
[SLd_in]adelay=0,volume=0.95[SLd];
[SLp_in]adelay=14,highpass=f=1500,
  equalizer=f=6500:t=q:w=1.2:g=2.0,
  equalizer=f=11000:t=q:w=1.0:g=-1.2,volume=1.00[SLp];
[SLh_in]adelay=28,highpass=f=2500,lowpass=f=14000,
  allpass=f=900:t=q:w=0.70,allpass=f=2200:t=q:w=0.70,
  equalizer=f=8000:t=q:w=3.0:g=-3.0,
  equalizer=f=11000:t=q:w=1.2:g=1.0,volume=0.60[SLh];
[SLlate_in]adelay=85,lowpass=f=1500,volume=0.65[SLlate];
[SLd][SLp][SLh][SLlate]amix=inputs=4:weights='1.10 0.85 0.80 0.55':normalize=0,
  volume=1.35,alimiter=limit=0.99[SL_out];
```

---

## 🧩 Utilizzo

```bash
./sonarwide.sh <ac3|eac3> <si|no> [file] [bitrate] [sonar|wide]
```

### Parametri
- **Codec output:** `ac3` | `eac3`
- **Mantieni traccia originale:** `si` | `no`
- **File:** un file specifico, oppure `""` per batch nella cartella
- **Bitrate:** es. `640k`, `768k`  
  - Default: **640k per AC3** • **768k per EAC3**
- **Modalità surround:** `sonar` | `wide`

### Esempi
```bash
./sonarwide.sh ac3 no "film.mkv" 640k sonar
./sonarwide.sh eac3 si "" 768k wide
```

---

## 🔁 Elaborazione batch

Lascia vuoto il parametro file per convertire tutti i video nella cartella:

```bash
./sonarwide.sh eac3 no "" 768k sonar
```

File supportati: `*.mkv *.mp4 *.m2ts`

---

## 📐 Layout consigliato

<p align="left">
  <img src="Sonar_Room_Layout.png" width="650" alt="Sonary Room Layout">
</p>

- Surround a 110–120°  
- Altezza Center 130–150 cm  
- Distanza 3–4 m  

---

## 🎥 Compatibilità AVR

- Ottimizzato per **Yamaha RX‑V4A**, ma funziona con qualunque AVR in modalità *Straight/Pure/Direct*
- Nessuna interferenza con YPAO (lavori “a valle” della correzione, se preferisci)
- **LFE invariato**

---

## 📄 Licenza
MIT License.

> "Per riportare ordine nella Forza Sonora serve solo uno script Bash… questa è la via."

# 🎧 Sonar AC3D Suite — Virtual Upfiring + EQ Voce Sartoriale

> “Non tutti i supereroi indossano un mantello... a volte usano `filter_complex` per salvare il mondo del 5.1.”  
> *— Sandro "D@mocle77" Sabbioni*

---

## 🚀 Descrizione

**Sonar AC3D** è una collezione di script Bash basati su **FFmpeg**, progettata per rifinire l’audio 5.1 con:
- **EQ sartoriale della voce** per massima intelligibilità (FC +0.6 dB / FL‑FR +0.3 dB @ 2.4 kHz)  
- **Virtual upfiring** in stile **AtmosX/NeuralX** per creare una *cupola sonora* anche senza canali Height  
- **LFE gestito con cura**: nella versione _1x_ è puro **passthrough**, nella _2x_ è applicato **HPF 22 Hz**  
- Compatibilità totale: il video e i sottotitoli vengono **copiati 1:1**

---

## 🧩 Versioni incluse

| Script | Descrizione | Note principali |
|--------|--------------|----------------|
| **`converti_2ac3_sonar_2x.sh`** | Versione completa (AtmosX, NeuralX, DualX) | Include HPF 22 Hz su LFE e opzione *dualx* |
| **`convert_2AC3_sonar1.sh`** | Versione snella basata su _2x_ | EQ voce + upfiring AtmosX, **no LFE mitigation**, **batch integrato** |
| **`convert_2AC3_sonar_2x_batch.sh`** | Launcher per `_2x` | Applica lo script principale a tutti i `.mkv` della cartella |
| **`convert_2AC3_audiocheck.sh`** | Utility diagnostica | Elenca codec, layout, bitrate, lingua, titolo delle tracce audio |

---

## 🧠 Requisiti

- **FFmpeg** ≥ 5.0 e **FFprobe** nel `PATH`
- Input con **prima traccia audio 5.1** (`side` o `back`)
- Ambiente consigliato: **Git Bash su Windows**, o **Bash Linux**

### Installazione rapida
```bash
git clone https://github.com/Damocle77/Sonar_AC3D.git
cd Sonar_AC3D
chmod +x *.sh
```

---

## ⚙️ Uso rapido

### 🟦 `convert_2AC3_sonar1.sh` (versione leggera)
```bash
./convert_2AC3_sonar1.sh <sonar|clean> <si|no> [file.mkv] [bitrate]
```

| Parametro | Significato |
|------------|-------------|
| `sonar` | Surround con virtual upfiring AtmosX (+3.2 dB) |
| `clean` | Surround pulito, senza upfiring (+2.9 dB) |
| `si|no` | Mantiene o meno la traccia audio originale |
| `[file.mkv]` | File singolo o `""` per batch |
| `[bitrate]` | 320k / 448k / 640k (default 640k) |

**Esempi**
```bash
# 1️⃣ Singolo file con upfiring AtmosX
./convert_2AC3_sonar1.sh sonar si "Dune.mkv"

# 2️⃣ Tutti i file .mkv della cartella (batch)
./convert_2AC3_sonar1.sh sonar no ""

# 3️⃣ Versione clean, senza upfiring
./convert_2AC3_sonar1.sh clean no "Tenet.mkv" 448k
```

---

### 🟩 `converti_2ac3_sonar_2x.sh` (versione avanzata)
```bash
./converti_2ac3_sonar_2x.sh <sonar|clean|dualx> <si|no> <file.mkv> [bitrate] [neuralx|atmosx]
```
- `dualx` genera **due tracce** (NeuralX + AtmosX) nello stesso MKV.  
- Preserva il video e copia eventuali sottotitoli.

**Esempi**
```bash
# NeuralX dinamico
./converti_2ac3_sonar_2x.sh sonar no "Avengers.mkv" 640k neuralx

# AtmosX con traccia originale conservata
./converti_2ac3_sonar_2x.sh sonar si "Alien.mkv" 640k atmosx

# DualX: entrambe le versioni nello stesso file
./converti_2ac3_sonar_2x.sh dualx si "Dune.mkv" 640k
```

---

## 🔁 Modalità batch
Entrambe le versioni supportano il batch nativamente.

| Modalità | Script | Comando |
|-----------|---------|---------|
| Batch semplice | `convert_2AC3_sonar1.sh` | `./convert_2AC3_sonar1.sh sonar no ""` |
| Batch completo | `convert_2AC3_sonar_2x_batch.sh` | `./convert_2AC3_sonar_2x_batch.sh sonar no 640k atmosx` |

---

## 🔊 Parametri tecnici chiave (_2x / 1x_)
| Sezione | Parametri | Descrizione |
|----------|------------|-------------|
| EQ voce | FC +0.6 dB, FL/FR +0.3 dB @ 2.4 kHz (Q=1.0) | Chiarezza dialoghi |
| Upfiring AtmosX | Delay 17–40 ms · Bandpass 4.4–5.4 kHz · Weights 1 0.35 0.35 0.55 0.25 | Verticalità realistica |
| Surround boost | +3.2 dB (Sonar) · +2.9 dB (Clean) | Ampiezza controllata |
| LFE | HPF 22 Hz (_2x_) · Passthrough (_1x_) | Stabilità e controllo bassi |
| Output | AC-3 5.1 · 48 kHz · soxr resampling | Massima compatibilità |

---

## 🏠 Ambiente di riferimento (ottimale)
| Parametro | Valore consigliato |
|------------|--------------------|
| Stanza | 4 × 5 m |
| Altezza soffitto | 4.1 m |
| Distanza ascoltatore–TV | 3.6 m |
| Altezza frontali | 60–70 cm |
| Altezza centrale | 140 cm (inclinato ~6° verso il basso) |
| Altezza surround | 120 cm, ~1 m dietro l’ascoltatore |
| Risultato | Cupola sonora ampia e coerente con percezione “cinema” |

---

## 🧪 Utility diagnostica
```bash
./convert_2AC3_audiocheck.sh <file.mkv>
```
Mostra codec, canali, bitrate, lingua e tag di ciascuna traccia audio.

---

## 🪶 Licenza
MIT — usa, modifica, condividi.  
Se ti piace come suona la *Kessel Run* nel tuo salotto, lascia una ⭐ su GitHub.  
**Questa è la via.**

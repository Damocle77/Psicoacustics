<p align="left">
  <img src="sonary_logo.png" width="600" alt="Sonary Suite Logo">
</p>

# 🎧 Sonary Suite – Sonar & Wide Edition

DSP **offline** avanzato per tracce audio **5.1**, progettato per migliorare **intelligibilità del parlato**, **coerenza timbrica** e **spazialità surround** senza alterare il mix originale.

Pensato per AVR utilizzati in modalità **Straight / Pure / Direct** (testato e ottimizzato su Yamaha RX-V4A), con piena compatibilità con sistemi di correzione ambientale come **YPAO**.

> "Non tutti i supereroi indossano un mantello... a volte usano `-filter_complex` per salvare il mondo del 5.1."  
> ⚡ D@mocle77 | Sandro Sabbioni | ∑(logic) ⚡

---

## 🧠 Filosofia del progetto

Sonary Suite nasce da un principio semplice ma rigoroso:

> *correggere solo ciò che serve, dove serve, e nel modo meno invasivo possibile.*

Per questo motivo:
- l’elaborazione è **offline** (nessun DSP in tempo reale sull’AVR)
- **FL / FR restano neutri**
- **LFE non viene mai toccato**
- il canale **Centrale (FC)** riceve una EQ dedicata e costante
- i **Surround** sono l’unico elemento variabile (Sonar / Wide)

Il risultato è un suono più leggibile, stabile e naturale, che **non combatte** né YPAO né il mix originale.

---

## ✅ Requisiti

### Software
- **FFmpeg 7+** (compilato con resampler **SOXR**)
- **Bash 4.x+**

### Sistemi operativi
- Linux
- macOS
- Windows tramite **WSL2** o **Git-Bash**

### Hardware consigliato
- AVR multicanale (5.1)
- diffusori surround simmetrici
- stanza domestica medio-grande (es. ~4 × 5 m)

---

## 🚀 Installazione

```bash
git clone https://github.com/Damocle77/Sonar_AC3D.git
cd Sonar_AC3D
chmod +x sonarwide.sh
```

---

## 🎚️ EQ Voce Sartoriale (Canale Centrale – FC)

L’EQ Voce è **sempre attiva**, indipendentemente dalla modalità surround selezionata.
È progettata specificamente per **parlato italiano**, con l’obiettivo di:
- massima intelligibilità anche a basso volume
- naturalezza timbrica
- minima fatica d’ascolto nel lungo periodo

### Curva attuale
- **−1.0 dB @ 230 Hz** → alleggerimento del corpo vocale
- **−1.0 dB @ 350 Hz** → riduzione boxiness
- **−0.5 dB @ 900 Hz** → micro de-nasalizzazione
- **+1.6 dB @ 1 kHz** → articolazione del parlato
- **+2.3 dB @ 2.5 kHz** → presenza e intelligibilità
- **−1.0 dB @ 7.2 kHz** → controllo delle sibilanti
- **Limiter trasparente 0.99** con attack/release (anti-clipping)

Questa EQ è **identica** per Sonar e Wide, così da mantenere coerenza timbrica del dialogo.

---

## 🔊 Modalità Surround

### 1️⃣ Wide — Widening controllato

Modalità pensata per aumentare **ampiezza e avvolgimento** dei surround senza arretrare il centro.

Caratteristiche principali:
- struttura **Direct + Early + Diffuse**
- bande di lavoro controllate (HPF / LPF + allpass)
- shelving leggero per equilibrio tonale
- **Limiter 0.99** di sicurezza

#### Compensazione asimmetria stanza

In ambienti non perfettamente simmetrici (es. lato destro più largo):
- viene applicato un **micro-delay (~0.8 ms)** al surround sinistro
- l’intervento è puramente **psicoacustico**
- agisce **solo sui surround**
- **non interferisce con YPAO**, perché avviene offline

Effetto:
- centro più stabile
- scena più coerente
- nessun eco o sfasamento percepibile

---

### 2️⃣ Sonar — Upfiring psicoacustico

Modalità orientata alla **coerenza e profondità verticale**, ispirata ai sistemi upfiring, ma senza canali height reali.

Caratteristiche principali:
- layer **Direct + Presence + High-Diffuse + Late Tail**
- micro-ritardi tipici: **14 ms / 28 ms / 85 ms**
- lavoro concentrato sulle medio-alte
- scena stabile e rilassata, ideale per ascolti prolungati

Sonar privilegia la **credibilità spaziale** rispetto all’effetto spettacolare.

---

## 🧩 Utilizzo

```bash
./sonarwide.sh <ac3|eac3> <si|no> [file] [bitrate] [sonar|wide]
```

### Parametri
- **Codec output:** `ac3` | `eac3`
- **Mantieni traccia originale:** `si` | `no`
- **File:** nome file oppure `""` per elaborazione batch
- **Bitrate:** es. `640k`, `768k`
- **Modalità surround:** `sonar` | `wide`

### Esempi
```bash
./sonarwide.sh ac3 no "film.mkv" 640k sonar
./sonarwide.sh eac3 si "" 768k wide
```

---

## 🎥 Compatibilità AVR

- Ottimizzato per **Yamaha RX-V4A**
- Compatibile con qualsiasi AVR in modalità *Straight / Pure / Direct*
- Nessuna interferenza con YPAO o sistemi equivalenti
- Nessun DSP AVR richiesto

---

## 🚫 Cosa questo script NON fa

- non applica dialog enhancer artificiali
- non comprime aggressivamente la dinamica
- non modifica i frontali
- non equalizza l’LFE
- non sostituisce la calibrazione ambientale

---

## 📄 Licenza

MIT License.

> *Per riportare ordine nella Forza Sonora serve solo uno script Bash… questa è la via.*

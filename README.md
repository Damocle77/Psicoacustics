<p align="left">
  <img src="sonary_logo.png" width="600" alt="Sonary Suite Logo">
</p>

# 🎧 Sonary Suite — Sonar / Wide / Aegis / Aura / Voice

DSP **offline** avanzato per tracce audio **5.1**, progettato per migliorare **intelligibilità del parlato**, **coerenza timbrica** e **spazialità surround** senza stravolgere il mix originale.

Pensato per AVR usati in modalità **Straight / Pure / Direct** (testato e ottimizzato su **Yamaha RX-V4A con crossover 160Hz**), e compatibile con sistemi di correzione ambientale come **YPAO**.

> "Non tutti i supereroi indossano un mantello… a volte basta un `-filter_complex` per salvare il mondo del 5.1."  
> ⚡ Sandro (D@mocle77) Sabbioni ⚡  
> …perception follows physics…

---

## 🧠 Filosofia del progetto

Sonary Suite nasce da un principio semplice ma rigoroso:

> *correggere solo ciò che serve, dove serve, e nel modo meno invasivo possibile.*

Per questo motivo:
- l'elaborazione è **offline** (nessun DSP in tempo reale sull'AVR)
- **FL / FR restano neutri**
- **LFE non viene mai toccato**
- il canale **Centrale (FC)** riceve una EQ dedicata e costante
- i **Surround** sono l'unico elemento variabile (Sonar / Wide / Aegis / Aura oppure bypass in Voice)

Il risultato è un suono più leggibile, stabile e naturale, che **non combatte** né YPAO né il mix originale.

### ⚙️ Ottimizzazioni specifiche per setup reale
- **Crossover AVR 160Hz** → LFE lowpass alzato a 140Hz, surround highpass coordinato
- **Speaker Small** → Gestione basse frequenze ottimizzata per bass management
- **Stanza irregolare >4×5×4m** → Delay ridotti (50ms vs 85ms), energia surround bilanciata
- **YPAO attivo** → Filtri coordinati per evitare doppia compensazione

> Nota "fisica non negoziabile": **AC3 / E-AC3 si codificano sempre via CPU**. L'eventuale HW accel riguarda al massimo la *decodifica video*, non l'encoding audio.

---

## ✅ Requisiti

### Software
- **FFmpeg 7+** (consigliato con resampler **SOXR**)
- **Bash 4.x+**

### Sistemi operativi
- Linux
- macOS
- Windows (**WSL2**, **Git-Bash**, **MSYS2**)

---

## 🚀 Installazione

```bash
git clone https://github.com/Damocle77/Sonary_Suite.git
cd Sonary_Suite
chmod +x aegis_sonar_wide_aura_voice.sh
chmod +x stereo251_psico.sh
chmod +x asmr_vr_intimate.sh
```

---

## 📦 Suite completa - 3 script

### 1️⃣ **aegis_sonar_wide_aura_voice.sh** - Processing 5.1 esistente
Elabora tracce **5.1 già presenti** con DSP surround psicoacustico

### 2️⃣ **stereo251_psico.sh** - Upmix Stereo → 5.1
Converte tracce **stereo** in 5.1 con upmix psicoacustico reattivo

### 3️⃣ **asmr_vr_intimate.sh** - Audio binaurale intimo
Ottimizza tracce **stereo** per ascolto ravvicinato VR/ASMR/intimo

---

## 🧩 Script 1: aegis_sonar_wide_aura_voice.sh (5.1 DSP)

### Utilizzo base
```bash
./aegis_sonar_wide_aura_voice.sh <ac3|eac3> <si|no> [file|""] [bitrate] [sonar|wide|aegis|aura|voice]
```

### Parametri
- **codec**: `ac3` | `eac3`
- **keep_orig**: `si` | `no` (mantiene o no anche la traccia originale)
- **file**: `"film.mkv"` | `""` (batch: elabora tutti i file nella cartella)
- **bitrate**: es. `448k`, `640k`, `768k` (default: `ac3=640k`, `eac3=768k`)
- **mode**:
  - `sonar` = "altezza" (simulazione psicoacustica 5.1.2 verticale)
  - `wide`  = "ampiezza" (simulazione psicoacustica 7.1 orizzontale)
  - `aegis` = "intermedia" (guardia dinamica + cupola più controllata)
  - `aura`  = **Wide Light** (spazio laterale "soft" a bassa energia)
  - `voice` = **solo EQ Voce Sartoriale su FC** (surround pass-through)

### Esempi pratici
```bash
# Film d'azione moderno → WIDE per massima ampiezza laterale
./aegis_sonar_wide_aura_voice.sh eac3 no "fast_furious.mkv" 768k wide

# Sci-fi/fantasy → SONAR per effetto altezza
./aegis_sonar_wide_aura_voice.sh eac3 no "interstellar.mkv" 768k sonar

# Thriller con dinamica variabile → AEGIS per controllo
./aegis_sonar_wide_aura_voice.sh eac3 no "batman.mkv" 640k aegis

# Drama/contenuto vocale → AURA per spazio discreto
./aegis_sonar_wide_aura_voice.sh ac3 si "drama.mkv" 640k aura

# Traccia con surround inutili → VOICE (solo EQ centrale)
./aegis_sonar_wide_aura_voice.sh ac3 no "vecchio_film.mkv" 640k voice

# Batch intera cartella con WIDE
./aegis_sonar_wide_aura_voice.sh eac3 no "" 768k wide
```

---

## 🎚️ Script 2: stereo251_psico.sh (Upmix Stereo → 5.1)

### Utilizzo base
```bash
./stereo251_psico.sh <pan|surround> [codec] [bitrate] file1.mkv [file2.mkv ...]
```

### Modalità
- **pan**: Restauro / vecchi film (spazio stabile)
- **surround**: Film e serie moderne (spazio reattivo)

### Codec
- **ac3**: Dolby Digital (compatibilità massima, max 640k)
- **eac3**: Dolby Digital Plus (default, qualità superiore, fino 1536k)

### Esempi
```bash
# Film moderno stereo → 5.1 reattivo
./stereo251_psico.sh surround eac3 768k "film_stereo.mkv"

# Vecchio film → 5.1 stabile
./stereo251_psico.sh pan ac3 640k "classico_1960.mkv"

# Default (surround, eac3, 448k)
./stereo251_psico.sh surround "serie.mkv"
```

### Caratteristiche tecniche
- **Crossfeed moderato** (0.02) per stabilità immagine stereo
- **Sidechain upward compression** sui surround (reagisce all'envelope dei front)
- **Aphaser decorrelation** per evitare localizzazione centrale posteriore
- **LFE ottimizzato** per crossover 160Hz (lowpass 140Hz, volume 1.50)
- **Surround highpass 160Hz** coordinato con bass management AVR

---

## 🎧 Script 3: asmr_vr_intimate.sh (Audio binaurale intimo)

### Utilizzo base
```bash
./asmr_vr_intimate.sh [opzioni] <file1> [file2 ...]
```

### Opzioni
```
-o <dir>      Cartella di output
-d <mode>     Distanza simulata: whisper|near|center (default: whisper)
                whisper = 20-30cm (sussurro all'orecchio, massima intimità)
                near    = 30-50cm (conversazione ravvicinata)
                center  = frontale centrale (VR chat)
-k            Mantieni traccia audio originale
-f            Forza overwrite
-l            Attiva pseudo-LFO "breathing" (effetto ipnotico)
-h            Help
```

### Esempi
```bash
# Contenuto intimo/sexy (default whisper)
./asmr_vr_intimate.sh video_intimo.mp4

# Con effetto respirazione ipnotico
./asmr_vr_intimate.sh -d whisper -l asmr_roleplay.mp4

# VR chat conversazionale
./asmr_vr_intimate.sh -d near video_chat.mp4

# Batch con output directory
./asmr_vr_intimate.sh -d whisper -l -o ./processed *.mp4
```

### Caratteristiche tecniche
- **Crossfeed** progressivo (0.42 whisper, 0.50 near, 0.55 center)
- **ITD** (Interaural Time Difference) calibrato per distanza
- **EQ warmth**: boost 85-140Hz per calore corporeo/respiro
- **De-essing** delicato a 5.8kHz, dettaglio ASMR a 9-12kHz
- **LFO breathing** opzionale (0.12Hz = ciclo 8 sec respiratorio)

---

## 🎨️ EQ Voce Sartoriale (Canale Centrale — FC)

L'EQ Voce è **sempre attiva** in tutti gli script (5.1 processing, stereo upmix), indipendentemente dalla modalità surround.

### Versione ottimizzata (2026)
```
−1.0 dB @ 230 Hz   → alleggerimento del corpo vocale
−1.0 dB @ 350 Hz   → riduzione "boxiness"
−0.5 dB @ 900 Hz   → micro de-nasalizzazione
+1.6 dB @ 1.0 kHz  → articolazione del parlato
+0.4 dB @ 1.8 kHz  → "chiodo" frontale
+1.6 dB @ 2.5 kHz  → attacco consonantico (T,K,S,F) - RIDOTTO da +2.3
+0.35 dB @ 3.2 kHz → presenza / intelligibilità
−1.0 dB @ 7.2 kHz  → controllo sibilanti
```

**Cambio chiave**: 2.5 kHz ridotto da **+2.3 dB → +1.6 dB** per ridurre affaticamento su ascolti lunghi mantenendo intelligibilità.

### Delta per modalità (aegis_sonar_wide_aura_voice.sh)
Ogni modalità applica un **boost aggiuntivo** sul canale centrale:

- **SONAR**: +0.54 dB finale
- **WIDE**: +0.58 dB finale + ulteriore +0.25 dB a 2.5kHz
- **AURA**: +0.56 dB finale + ulteriore +0.15 dB a 2.5kHz
- **VOICE**: 0 dB (neutro, solo EQ base)
- **AEGIS**: +0.54 dB finale (come SONAR)

Questo compensa l'energia surround variabile mantenendo la voce sempre prioritaria.

---

## 📊 Modalità Surround — Architettura e caratteristiche

### 1️⃣ WIDE — Widening psicoacustico (simulazione 7.1)
**Quando usarla**: Film d'azione, sport, inseguimenti, battaglie
**Architettura**:
- 3 layer decorrelati (direct, early, cross)
- Allpass asimmetrici (L: 1200Hz, R: 1350Hz)
- Delay: 1, 9-10, 22-24 ms
- Highpass 280Hz (coordinato con crossover 160Hz)
- Lowshelf 160Hz +0.2dB
- Volume finale: 1.30

**Effetto**: Estensione laterale marcata, illusione 7.1 orizzontale

### 2️⃣ SONAR — Upfiring psicoacustico (simulazione 5.1.2)
**Quando usarla**: Sci-fi, fantasy, contenuti con movimento verticale
**Architettura**:
- 4 layer stratificati (direct, presence, height, late)
- Delay: 0, 14, 28, 50 ms (ridotto da 85ms per stanza reale)
- Boost selettivo 6.5kHz (+2.0 dB) per "aria"
- Cut 8kHz (-3.0 dB) per evitare harshness
- Volume finale: 1.35

**Effetto**: Profondità e altezza percepita, riflessi verticali simulati

### 3️⃣ AEGIS — Guardia dinamica (cupola controllata)
**Quando usarla**: Mix affollati, thriller, contenuti con dinamica variabile
**Architettura**:
- Come SONAR ma con **acompressor** dinamico
- Threshold: -16dB, Ratio: 1.6, Attack: 3ms, Release: 60ms
- Energia ridotta su layer alti (volume 0.48 vs 0.60)
- Late layer lowpass 1300Hz (più contenuto)
- Volume finale: 1.20

**Effetto**: Surround presente ma mai invadente, controllo su picchi

### 4️⃣ AURA — Wide Light (spazio laterale soft)
**Quando usarla**: Drama, dialoghi prioritari, mix delicati
**Architettura**:
- Solo 2 layer (direct + ambient)
- Banda stretta 800-4500Hz
- Decorrelazione minima (allpass L: 1400Hz, R: 1550Hz)
- Delay brevi: 1, 8-9 ms
- Volume finale: 1.15

**Effetto**: Spazio laterale discreto, bassa energia, non invasivo

### 5️⃣ VOICE — Solo EQ FC (surround pass-through)
**Quando usarla**: Mix piatti, serie vecchie, surround inutili/dannosi
**Architettura**:
- Surround: `anull` (pass-through completo)
- Solo EQ voce sul centrale
- Limiter conservativo (0.99)

**Effetto**: Zero processing surround, massima priorità voce

---

## 🧪 Workflow consigliato: Analisi RMS + Scelta profilo

### Strumenti necessari
1. **Audacity** (con FFmpeg) per analisi RMS
2. Opzionale: **FFMediaMaster** per normalizzazione preventiva

### Procedura

#### 1) Normalizzazione dinamica preventiva (opzionale)
Solo se la traccia ha dinamica ingestibile (dialoghi bassissimi, esplosioni assordanti):

```bash
# Con FFMediaMaster: Dynamic Audio Normalizer / loudnorm leggero
# Oppure CLI:
ffmpeg -i "input.mkv" -af "dynaudnorm=f=150:g=5:m=10" "prep.mkv"
```

#### 2) Analisi RMS in Audacity
- Apri traccia 5.1 (File → Import → Audio)
- Zoom su 2 scene rappresentative (action + dialogo)
- Analyze → Contrast → Measure RMS su:
  - **FC** (canale centrale)
  - **SL/SR** (surround)

#### 3) Applica schema decisionale

<p align="left">
  <img src="guida_voice_schema.png" width="900" alt="Schema decisionale RMS">
</p>

**Priorità assoluta**: FC (voce) > Surround > LFE

##### Step 1: Valuta RMS Surround (SL/SR)
```
≥ −25 dB          → Presenti        → WIDE
−24 .. −27 dB     → Medi            → AURA / SONAR
−27 .. −31 dB     → Discreti        → SONAR / AEGIS
−31 .. −39 dB     → Molto deboli    → AEGIS o VOICE
≤ −39 dB          → Quasi assenti   → VOICE
```

##### Step 2: Valuta RMS FC (Centrale)
```
> −20 dB          → Voce molto forte → OK, mantieni scelta surround
−21 .. −24 dB     → Voce buona       → OK, mantieni scelta
−25 .. −28 dB     → Voce medio-bassa → DOWNGRADE: WIDE→AEGIS, SONAR→AEGIS
≤ −29 dB          → Voce debole      → AEGIS o VOICE + boost FC
```

**Regola d'oro**: Se FC è basso, **downgrade** il profilo surround

##### Step 3: Combinazioni raccomandate
```
FC ≥ ~−25  e  SL/SR ≥ −26            → WIDE
FC ≥ ~−25  e  SL/SR ~−27 → −30       → AURA
FC ~ −26 → −27  e  SL/SR ~−27 → −32  → SONAR
FC ~ −28 → −31  e  SL/SR ~−27 → −39  → AEGIS
FC ≤ −31  o  SL/SR ≤ −39             → VOICE
```

##### Step 4: Fine-tuning opzionale (Front L/R + LFE)
Solo se necessario per bilanciamento finale:

**Front L/R**:
```
≈ FC (±3 dB)                  → OK
Front > FC +4..+6 dB          → Effetti troppo forti → +1..+2 dB su FC
Front < −26 dB                → Scena front debole → +2..+4 dB su FL/FR
```

**LFE**:
```
> −18 dB          → Bassi molto forti → Perfetto
−19 .. −22 dB     → Bassi buoni       → OK
−23 .. −26 dB     → Bassi discreti    → +3..+6 dB subwoofer
< −26 dB          → Bassi deboli      → +6..+10 dB subwoofer
```

---

## 🎥 Compatibilità AVR

### Testato e ottimizzato
- **Yamaha RX-V4A** (crossover 160Hz, speaker Small, YPAO ON)

### Compatibile con
- Qualsiasi AVR in modalità **Straight / Pure / Direct**
- Sistemi di calibrazione: YPAO, Audyssey, Dirac Live, ecc.
- **Nessun DSP AVR richiesto** (l'elaborazione è offline)

### Setup AVR consigliato
```
Modalità audio: STRAIGHT (o PURE DIRECT)
Crossover: 160Hz (tutti i canali su Small)
YPAO: ON (se disponibile)
Dynamic Range: OFF (già gestito negli script)
Dialogue Lift: OFF
```

---

## 🛋️ Layout consigliato della stanza

Per ottimizzare **Sonar / Wide / Aegis / Aura**:

<p align="left">
  <img src="sonar_room_layout.png" width="900" alt="Layout stanza consigliato">
</p>

### Posizionamento altoparlanti
- **Front L/R**: ±30° rispetto al centro (60° totali), tweeter a livello orecchie
- **Center**: Sotto/sopra TV, centrato, inclinato verso punto d'ascolto (~140cm altezza)
- **Surround L/R**: Laterali o leggermente arretrati, non troppo alti
- **Subwoofer**: Sub crawl per trovare posizione ottimale

### Dimensioni stanza ottimali
- **Minimo**: 3×4m (12m²)
- **Consigliato**: >4×5m con soffitto ≥2.8m
- **Ideale**: Stanza irregolare (riduce modi di risonanza)

**Nota**: Gli script sono ottimizzati per stanze **>4×5×4m** con forma irregolare.

---

## 🚫 Cosa questi script NON fanno

- ❌ Non applicano "dialog enhancer" artificiali
- ❌ Non comprimono aggressivamente la dinamica (solo guardia leggera in Aegis)
- ❌ Non modificano i frontali L/R (restano neutri)
- ❌ Non equalizzano l'LFE
- ❌ Non sostituiscono la calibrazione ambientale
- ❌ Non usano neural networks o AI upscaling

---

## 🔧 Troubleshooting

### Script non parte
```bash
# Verifica permessi
chmod +x *.sh

# Verifica FFmpeg
ffmpeg -version

# Test su file singolo
./aegis_sonar_wide_aura_voice.sh eac3 no "test.mkv" 640k voice
```

### Audio risultante troppo forte/basso
- Controlla livelli RMS originali in Audacity
- Usa normalizzazione preventiva se necessario
- Regola volume master AVR (non gli script)

### Surround troppo invasivi
- Prova modalità **AURA** invece di WIDE
- O passa a **VOICE** (solo EQ centrale)

### Voce ancora poco intelligibile
- Verifica RMS FC originale
- Se FC < -28dB, considera boost manuale post-processing
- O usa **VOICE** mode che preserva solo la voce

---

## 📝 Changelog

### v2.0 (Gennaio 2026) - Ottimizzazione setup reale
- ✅ Crossover 160Hz: LFE → 140Hz lowpass, volume 1.50
- ✅ Surround highpass coordinato a 160Hz
- ✅ Delay ridotti: 85ms → 50ms per stanze reali
- ✅ EQ voce 2.5kHz: +2.3 → +1.6 dB (meno affaticamento)
- ✅ Aggiunto **stereo251_psico.sh** (upmix stereo → 5.1)
- ✅ Aggiunto **asmr_vr_intimate.sh** (audio binaurale intimo)
- ✅ Documentazione completa con workflow RMS

### v1.0 (2025)
- 🎉 Release iniziale con 5 modalità (Sonar, Wide, Aegis, Aura, Voice)

---

## 📄 Licenza

MIT License - Vedi file LICENSE

---

## 👤 Autore

**Sandro (D@mocle77) Sabbioni**

> *Per riportare ordine nella Forza Sonora serve solo uno script Bash… questa è la via.*

---

## 🙏 Ringraziamenti

- Community FFmpeg per gli strumenti
- Yamaha per RX-V4A e YPAO
- Tutti i beta tester che hanno fornito feedback

---

## 🔗 Link utili

- [FFmpeg Documentation](https://ffmpeg.org/documentation.html)
- [Yamaha RX-V4A Manual](https://www.yamaha.com)
- [Audio Engineering Basics](https://www.soundonsound.com)

<p align="left">
  <img src="sonary_logo.png" width="600" alt="Sonary Suite Logo">
</p>

# 🎧 Sonary Suite – Sonar & Wide Edition

DSP **offline** avanzato per tracce audio **5.1**, progettato per migliorare **intelligibilità del parlato**, **coerenza timbrica** e **spazialità surround** senza alterare il mix originale.

Pensato per AVR utilizzati in modalità **Straight / Pure / Direct** (testato e ottimizzato su Yamaha RX-V4A), con piena compatibilità con sistemi di correzione ambientale come **YPAO**.

> "Non tutti i supereroi indossano un mantello...basta un `-filter_complex` per salvare il mondo del 5.1."  
> ⚡Sandro (D@mocle77) Sabbioni ⚡
perception follows physics...

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
- Windows **WSL2** , **Git-Bash** , **MYSYS2**

### Hardware consigliato
- AVR multicanale (5.1)
- diffusori surround simmetrici
- stanza domestica medio-grande (es. ~4 × 5 x 4 m)

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
È progettata per esaltare il **parlato italiano**, con l’obiettivo di ottenere:
- massima intelligibilità anche a basso volume
- naturalezza timbrica
- minima fatica d’ascolto nel lungo periodo

### Curva attuale
- **−1.0 dB @ 230 Hz** → alleggerimento del corpo vocale
- **−1.0 dB @ 350 Hz** → riduzione boxiness (specifico per lingua italiana)
- **−0.5 dB @ 900 Hz** → micro de-nasalizzazione (specifico per lingua italiana)
- **+1.6 dB @ 1 kHz** → articolazione del parlato
- **+0.4 dB @ 1.8 kHz** → chiodo frontale (posizione psicoacustica frontale)
- **+2.3 dB @ 2.5 kHz** → presenza e intelligibilità
- **−1.0 dB @ 7.2 kHz** → controllo delle sibilanti (effetto de-esser)

Questa EQ è **identica** per Sonar e Wide, così da mantenere coerenza timbrica del dialogo.

---

## 🔊 Modalità Surround – Architettura e bande di frequenza

Le modalità **Wide** e **Sonar** utilizzano approcci psicoacustici differenti, ma condividono una filosofia comune:  
*modellare lo spazio attraverso tempo e spettro, non attraverso artifici invasivi*.

Le frequenze vengono quindi trattate in modo **selettivo**, con bande dedicate a specifiche funzioni percettive.

---

### 1️⃣ Wide - Widening psicoacustico controllato  
*(Simulazione 7.1 virtuale)*

La modalità **Wide** lavora principalmente sulla **dimensione orizzontale della scena**, aumentando la percezione di ampiezza laterale e avvolgimento dei surround, senza arretrare il fronte sonoro né destabilizzare il canale centrale.

#### Struttura percettiva
- **Direct**  
  Segnale surround diretto, con contributo pieno e non colorato.
- **Early reflections virtuali**  
  Componenti a breve ritardo per simulare riflessioni laterali.
- **Diffuse layer**  
  Energia decorrelata per aumentare larghezza e immersione.

#### Bande di frequenza (concettuali)
- **Basse frequenze (≈ 300–600 Hz)**  
  Presenti ma controllate, per dare corpo senza creare confusione o risonanze ambientali.
- **Medie (≈ 600–5.000 Hz)**  
  Zona chiave per la spazialità laterale: qui avviene la maggior parte del widening percettivo.
- **Alte (≈ 5.000–7.000 Hz)**  
  Utilizzate con moderazione per aggiungere aria e dettaglio, evitando asprezze.

Allpass e shelving leggeri vengono impiegati per **decorrelare senza colorare**, mantenendo una timbrica coerente con il mix originale.

**Risultato percettivo:**  
scena più larga, più cinematografica, con surround che “abbracciano” l’ascoltatore senza rubare attenzione ai dialoghi.

---

### 2️⃣ Sonar - Upfiring psicoacustico coerente  
*(Simulazione 5.1.2 virtuale)*

La modalità **Sonar** è orientata alla **profondità e alla verticalità percepita**, ispirata ai sistemi upfiring, pur operando su un impianto 5.1 tradizionale.

Qui il tempo diventa il vero protagonista: piccoli ritardi e stratificazioni spettrali inducono il cervello a interpretare il suono come proveniente anche dall’alto.

#### Struttura a layer
- **Direct**  
  Riferimento stabile e non alterato.
- **Presence**  
  Rinforzo controllato per aumentare la sensazione di elevazione.
- **High-Diffuse**  
  Diffusione decorrelata sulle medio-alte.
- **Late Tail**  
  Coda tardiva morbida che amplia la scena senza eco udibili.

#### Micro-ritardi tipici
- **~14 ms** → presenza e riflessioni precoci
- **~28 ms** → diffusione verticale
- **~85 ms** → ambiente tardivo

#### Bande di frequenza (concettuali)
- **Basse frequenze (< 1.500 Hz)**  
  Deliberatamente ridotte: la verticalità non nasce dal basso.
- **Medio-alte (≈ 1.500–8.000 Hz)**  
  Cuore della modalità Sonar: il cervello associa queste bande a riflessioni elevate.
- **Alte (> 8.000 Hz)**  
  Smussate e controllate per evitare fatica d’ascolto.

**Risultato percettivo:**  
una scena più alta, più profonda e rilassata, con un senso di spazio tridimensionale credibile e naturale.

---

### 🧭 Filosofia di scelta

- **Wide** privilegia l’**ampiezza della scena** e l’impatto emotivo in stile cinema moderno
- **Sonar** privilegia la **credibilità spaziale** e la stabilità percettiva della scena nel tempo.

Entrambe le modalità rispettano il mix originale e cooperano con la EQ Voce Sartoriale, senza mai interferire con LFE, frontali o sistemi di calibrazione ambientale.


---

## 🧩 Utilizzo

```bash
./sonarwide.sh <ac3|eac3> <si|no> [file] [bitrate] [sonar|wide] [amd|nvidia|intel|cpu]
```

### Parametri
- **Codec output:** `ac3` | `eac3`
- **Mantieni traccia originale:** `si` | `no`
- **File:** nome file oppure `""` per elaborazione batch
- **Bitrate:** es. `640k`, `768k`
- **Modalità surround:** `sonar` | `wide`

### Esempi
```bash
./sonarwide.sh ac3 no "film.mkv" 640k sonar amd
./sonarwide.sh eac3 si "" 768k wide cpu
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

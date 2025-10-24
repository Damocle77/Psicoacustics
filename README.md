# 🛠️ Convert 2 AC3 Sonar

Script Bash per la **conversione audio multicanale in AC3 5.1**, con:
- EQ vocale sartoriale ottimizzata per lingua italiana 🇮🇹  
- filtro surround **psicoacustico upfiring virtuale** (simulazione Atmos / Neural:X)  
- gestione batch intelligente e logging leggibile a colori 🌈

> ⚡ Perfetto per sistemi home theatre AVR 5.1 classici.

---

## ✨ Funzionalità principali

### 🎤 Voce “Sartoriale”
La voce nei mix cinematografici è spesso **sepolta** sotto FX, score e ambienti.  
Questo script la riporta al centro della scena senza stravolgere il mix.

- **EQ a 2.5 kHz** → agisce sulle **formanti principali** della voce umana italiana, aumentando la **presenza** e la definizione senza rendere il suono “nasale”.
- **EQ a 4.2 kHz** → evidenzia **sibilanti e armoniche superiori**, migliorando la **chiarezza** a basso volume.
- **Volume dinamico** → ogni preset applica un boost differente (0.5–0.7 dB), adattandosi al tipo di sorgente (Atmos, DTS, EAC3, AC3).
- **Limiter finale** → protegge da clipping dopo l’equalizzazione.

> 🎧 Risultato: dialoghi intellegibili anche a volumi moderati, **senza schiacciare la colonna sonora**.

---

### 🌀 LFE / Subwoofer
- High-pass a 25 Hz per eliminare rimbombi infrasonici non udibili.
- Attenuazione opzionale per bilanciare i sub nei preset “cinematografici”.
- Limiter dedicato → protegge woofer e amplificatori da picchi imprevisti.
- Nessun EQ aggiuntivo: lascia lavorare il crossover dell’AVR.

---

### 🛰️ Surround Sonar — Upfiring Virtuale
Molti impianti 5.1 **non supportano Atmos nativamente**, ma ciò non significa rinunciare alla spazialità.  
Il filtro *sonar* utilizza **ritardi psicoacustici ed enfatizzazione spettrale** per creare un effetto percepito “dall’alto” — come i diffusori upfiring.

- **Delay corti e medi (14–92 ms)** → simulano riflessioni verticali sulle pareti/soffitto.
- **Boost sulle medie-alte** + **highshelf sopra gli 8 kHz** → dona “aria” e direzionalità.
- **Asimmetria L/R** → genera profondità spaziale e cue binaurali (effetto HRTF).
- **Limiter finale** → mantiene il mix controllato e coerente con i canali frontali.

📡 L’obiettivo non è creare un Atmos falso, ma simulare la **percezione verticale e spaziale** con sistemi tradizionali.

---

## 🧰 Pipeline robusta
- `channelsplit` → elaborazione canale per canale → `amerge` + `channelmap=5.1`
- Voice / LFE / Surround processati in modo indipendente.
- Prompt di sovrascrittura interattivo.
- Preservazione sottotitoli e traccia audio originale opzionale.
- Conversione singola o batch automatica.

---

## 🧪 Sintassi base

```bash
./converti_2AC3_sonar.sh <modalità> <si|no> [file.mkv] [preset] [bitrate]
```

| Pos. | Parametro      | Opzioni                                              | Descrizione |
|------|---------------|------------------------------------------------------|-------------|
| 1    | modalità       | `sonar` / `clean`                                    | Tipo di surround |
| 2    | keep original  | `si` / `no`                                          | Mantiene o meno la traccia originale |
| 3    | file input     | nome file .mkv (opzionale)                           | Se omesso → batch |
| 4    | preset         | `atmos` `dts` `eac37` `eac36` `ac3` `auto` *(default)* | EQ voce / LFE dinamici |
| 5    | bitrate        | `448k` / `640k` *(default)*                          | Bitrate AC3 |

---

## 🧠 Preset Audio

| Preset | Boost Voce | LFE Volume |
|--------|------------|------------|
| atmos  | +0.7 dB    | −2.0 dB    |
| dts    | +0.7 dB    | −2.3 dB    |
| eac37  | +0.5 dB    | −1.2 dB    |
| eac36  | +0.5 dB    |  0.0 dB    |
| ac3    | +0.5 dB    |  0.0 dB    |
| auto   | rilevamento automatico dal nome file (`atmos`, `dts`, `768`, `640`) |

👉 È possibile forzare manualmente il boost surround:
```bash
SUR_DB=1.2 ./converti_2AC3_sonar.sh sonar si file.mkv
```

---

## 🧭 Esempi pratici

### 🎧 Conversione singolo file con profilo sonar:
```bash
./converti_2AC3_sonar.sh sonar si "Il_Signore_degli_Anelli.mkv"
```

### 🧼 Conversione batch in modalità clean:
```bash
./converti_2AC3_sonar.sh clean no
```

### 🎯 Forzare preset DTS + bitrate personalizzato:
```bash
./converti_2AC3_sonar.sh sonar si film.mkv dts 448k
```

---

## 🛡️ Gestione segnali e sicurezza

- Interruzione manuale con **CTRL+C** → lo script mostra un messaggio pulito e termina con codice 130.  
- Prompt interattivo per evitare sovrascritture accidentali.  
- Limiter finale su tutti i canali → niente clipping selvaggio 😎

---

## 🧩 Pipeline Audio (schema semplificato)

```
[INPUT 5.1]
   │
   ├── Voice (FC) → EQ sartoriale 2.5 + 4.2 kHz + Boost dinamico
   ├── LFE        → High-pass 25 Hz + attenuazione + limiter
   ├── Surround   → sonar (aecho psicoacustico upfiring) / clean
   └── FL/FR      → pass-through
   ▼
[MERGE 5.1 + channelmap + limiter finale]
   ▼
[AC3 5.1 OUTPUT]
```

---

## 📝 Licenza

MIT License © Sandro “D@mocle77” Sabbioni  
Puoi usarlo, modificarlo e migliorarlo liberamente.  
Le uniche cose che **non sono ammesse**: clip digitali e surround piatti. 😄

---

## 💬 Note finali

> 🎙️ *«La voce non dev’essere solo sentita, dev’essere capita.»*  
> ☁️ *«E se il tuo sistema non supporta Atmos, fallo credere al tuo cervello.»*

Questo script nasce per:
- migliorare **l’intelligibilità** dei dialoghi nei film italiani e doppiaggi,  
- simulare **profondità e altezza sonora** su impianti consumer,  
- preservare la dinamica originale senza compressione aggressiva.

🪐 «Non è magia… è psicoacustica. E se non puoi permetterti l’Atmos… fallo credere al cervello.»

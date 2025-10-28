# Sonar AC3D 2x - Virtual upfiring + EQ voce sartoriale

> “Non tutti i supereroi indossano un `mantello`...a volte usano `filter_complex` per salvare il modno del 5.1”  
> " Da un maniaco del suono con la passione per i cinecomic"

Questo repository contiene **una suite bash peculiare** che ricodifica l’audio **5.1** in **AC‑3 5.1** con due focus primari:
1) **EQ “sartoriale” della voce** sempre attiva su **FL/FR/FC** per massima intelligibilità.  
2) **Upfiring virtuale** sui surround **SL/SR** quando richiesto, con due “voicing” ispirati a **NeuralX** (cupola ampia) e **Atmos** (verticalità precisa).

---

## Perché questo script?
- Per *spingere verso l’alto* la percezione verticale dei surround in stanze **senza** canali Height, ottenendo un effetto **AtmosX/NeuralX-like** riproducibile ovunque.
- Per **non toccare** la colonna portante del mix: i frontali e il centro restano “sacri”, salvo un **gentle presence** su FC/FL/FR (FC **+0.6 dB**, FL/FR **+0.3 dB** attorno ai **2.4 kHz**).
- Per **mantenere video e sottotitoli** intatti (copia diretta).

---

## Requisiti
- **FFmpeg** e **FFprobe** nel `PATH`. Lo script verifica le dipendenze.
- Sorgente con **prima traccia audio 5.1** (side o back; in quest’ultimo caso viene **normalizzata a 5.1(side)**).

### Installazione rapida FFmpeg
- **Windows 11 (Git Bash consigliato)**
  - Scarica FFmpeg “full build” (zip), scompatta in `C:\ffmpeg\bin` e aggiungi quella cartella al **PATH** di sistema.
  - Verifica: `ffmpeg -version` e `ffprobe -version` da un nuovo terminale.
- **Linux (esempi)**  
  - Ubuntu/Debian: `sudo apt-get update && sudo apt-get install -y ffmpeg`  
  - Fedora: `sudo dnf install -y ffmpeg`  
  - Arch: `sudo pacman -S ffmpeg`

### Clonare questo repo (esempio)
```bash
git clone https://github.com/Damocle77/Sonar_AC3D.git
cd Sonar_AC3D
chmod +x converti_2ac3_sonar_2x.sh convert_2AC3_sonar_2x_batch.sh convert_2AC3_audiocheck.sh
```

---

## Uso rapido
> Novità **dualx**: genera **due tracce** AC‑3 nello stesso MKV (**NeuralX default** + AtmosX).

```bash
./converti_2ac3_sonar_2x.sh <sonar|clean|dualx> <si|no> <file.mkv> [bitrate] [neuralx|atmosx]
```
- `sonar` = applica **virtual upfiring** solo a SL/SR; scegli il voicing (`neuralx` o `atmosx`).
- `clean` = **nessun upfiring**, solo boost controllato sui surround.
- `dualx` = crea **due tracce**: **NeuralX** (default) + **AtmosX** nello stesso file.
- `si|no` = **conserva o meno la traccia audio originale** nel container.
- `bitrate` (opz.): `320k|448k|640k` (default `640k`).
- `neuralx|atmosx` (opz., solo con `sonar`): **voicing** della cupola.

**Esempi**
```bash
# Sonar NeuralX (non conserva l'originale)
./converti_2ac3_sonar_2x.sh sonar no "Avengers.mkv" 640k neuralx

# Sonar AtmosX (conserva l'originale)
./converti_2ac3_sonar_2x.sh sonar si "Alien.mkv" 640k atmosx

# Clean (nessun upfiring), default 640k
./converti_2ac3_sonar_2x.sh clean no "Terminator.mkv"

# DualX (due tracce: NeuralX default + AtmosX)
./converti_2ac3_sonar_2x.sh dualx no "Fast_X.mkv" 640k
./converti_2ac3_sonar_2x.sh dualx si "Dune.mkv"   640k
```

---

## Naming d’uscita (fisso)
- `sonar + neuralx` → `<nome>_AC3_sonar_neuralx.mkv`  
- `sonar + atmosx`  → `<nome>_AC3_sonar_atmosx.mkv`  
- `clean`           → `<nome>_AC3_clean.mkv`  
- `dualx`           → `<nome>_AC3_sonar_dualx.mkv`  

La **traccia AC3 5.1** è sempre **48000 Hz**, video **copiato** (`-c:v copy`), **sottotitoli copiati** quando presenti.

---

## Che preset scegliere in un colpo d’occhio

| Tipo contenuto                               | Preset consigliato   | Perché                                           |
|----------------------------------------------|----------------------|--------------------------------------------------|
| Action “continua” (Fast & Furious, supereroi)| **sonar + neuralx**  | Cupola ampia, ambienze e score respirano         |
| Fantasy/avventura “cinematografica”          | **sonar + neuralx**  | Ampiezza e verticalità avvolgente                |
| Thriller/Noir/Horror “chirurgici”            | **sonar + atmosx**   | Verticalità più netta, dettagli scolpiti         |
| Serie molto dialogate                        | **clean**            | Niente upfiring, dialoghi comunque top           |

> Regola lampo: **NeuralX** = spettacolo e respiro “IMAX da salotto”. **AtmosX** = altezza precisa, contorni netti.  
> Se la cupola pare “spumosa” → AtmosX. Se sembra “stretta” → NeuralX.

---

## Come funziona (alto livello)
1. **Rilevamento layout** e **normalizzazione** a 5.1(side) quando necessario.  
2. **Split dei canali** → `[FL][FR][FC][LFE][SL][SR]`.  
3. **Voice EQ** su FL/FR/FC con **gentle presence** a **2.4 kHz** (FC +0.6 dB, FL/FR +0.3 dB).  
4. **LFE**: **HPF 22 Hz** sempre attivo (anti-rumble).  
5. **Surround**:  
   - `sonar` → **NeuralX/AtmosX** con *early reflections*, *upfiring bandpass + allpass (HRTF light)*, *late energy*, **boost +3.2 dB** e **limiter** in coda.  
   - `clean` → nessun upfiring, solo **boost +2.9 dB** e **limiter**.  
   - `dualx` → entrambe le pipeline in parallelo (**NeuralX** default + **AtmosX**).  
6. **Merge** a 5.1(side), resampling **soxr** alta precisione, **dither triangolare**.

---

## Altri script inclusi nel progetto

### `convert_2AC3_audiocheck.sh`
Tool da linea di comando per **elencare le tracce audio** di un `.mkv`: codec, canali, layout, bitrate, sample rate, lingua e `title`. Utile per verificare rapidamente che la **prima traccia sia 5.1** prima della conversione.  
**Uso:**
```bash
./convert_2AC3_audiocheck.sh <file.mkv>
```

### `convert_2AC3_sonar_2x_batch.sh`
Launcher batch che richiama `converti_2ac3_sonar_2x.sh` su **tutti i `.mkv` nella cartella corrente** (o su un singolo file passato come 5° argomento). Stampa progressi e tempo totale.  
**Uso tipico:**
```bash
# Esempio: modalità sonar, non conservare originale, voicing e bitrate
./convert_2AC3_sonar_2x_batch.sh sonar no 640k neuralx

# Esempio: modalità dualx su tutti i file
./convert_2AC3_sonar_2x_batch.sh dualx no 640k

# Esempio su singolo file specifico
./convert_2AC3_sonar_2x_batch.sh sonar si 640k atmosx "/percorso/Film.mkv"
```

---

## Limitazioni note
- Non trasforma un mix 5.1 in un vero mix **oggettuale**: simula **altezza percepita** con ritardi/filtri sui surround.  
- Si aspetta **6 canali** sulla prima traccia audio; stereo/mono non sono gestite.
- Output forzato in **AC‑3** per compatibilità ampia. Se serve E‑AC‑3/DTS, apri una PR.

---

## FAQ da sala di proiezione
**Perdo dettaglio sui frontali?** No: l’EQ è **delicata** e solo in *presence region*; niente bleed sui surround.  
**Il sub esplode?** Tranquillo: **HPF 22 Hz** sempre ON; nessun boost LFE indiscriminato.  
**Posso conservare la traccia originale?** Sì: `arg2=si` la copia come traccia non‑default.

---

## Licenza
MIT. Usa, remix, proietta. Se ti va, lascia una ⭐ e dimmi come suona la *Kessel Run* nel tuo salotto.

---

## Ringraziamenti
Per riportare ordine nel caos nella forza del suono non servono spade laser: basta un terminale e questo script. **Questa è la via.**


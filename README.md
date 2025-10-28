# Sonar AC3D - Virtual upfiring + EQ Voce sartoriale

> "Non tutti i supereroi indossano il mantello…alcuni usano filter_complex per salvare il mondo del 5.1!"  
> "Da un maniaco del suono con la passione per i cinecomic"      

Questo repository contiene **una suite bash peculiare** che ricodifica l’audio di un file **5.1** in **AC3 5.1** con due focus primari:  
1) **EQ “sartoriale” della voce** sempre attiva su **FL/FR/FC** per massima intelligibilità.  
2) **Upfiring virtuale** **solo** sui surround **SL/SR** quando richiesto.

---

## Perché questo script?
- Per *spingere verso l’alto* l’informazione spaziale dei surround in stanze senza canali Height, con un effetto **AtmosX/NeuralX-like** ma riproducibile ovunque.
- Per **non toccare** la colonna portante del mix (frontali e centro), a parte un **micro-boost chirurgico** della voce (FC **+0,6 dB**, FL/FR **+0,3 dB** attorno ai **2,4 kHz**).
- Per **mantenere il video intatto** e **copiare i sottotitoli** senza complicazioni.

---

## Requisiti
- **FFmpeg** e **FFprobe** nel `PATH`. Lo script verifica le dipendenze all’avvio.
- Sorgente con **prima traccia audio 5.1** (side o back; in quest’ultimo caso viene **normalizzata a 5.1(side)**).

---

## Uso rapido
```bash
./converti_2ac3_sonar_2x.sh <sonar|clean|dualx> <si|no> <file.mkv> [bitrate] [neuralx|atmosx]
```
- `sonar` = applica **virtual upfiring** solo a SL/SR  
- `clean` = **no upfiring**, solo boost controllato sui surround  
- `dualx` = crea due tracce audio, la prima con neurox sonar e la seconda con atmosx sonar
- `si|no` = **conserva o meno la traccia audio originale** nel container  
- `bitrate` (opz.): `320k|448k|640k` (default `640k`)  
- `neuralx|atmosx` (opz., solo con `sonar`): **voicing** della cupola

**Esempi**
```bash
# Sonar NeuralX (non conserva l'originale)
./converti_2ac3_sonar_2x.sh sonar no "Avengers.mkv" 640k neuralx

# Sonar AtmosX (conserva l'originale)
./converti_2ac3_sonar_2x.sh sonar si "Alien.mkv" 640k atmosx

# Clean (nessun upfiring), default 640k
./converti_2ac3_sonar_2x.sh clean no "Terminator.mkv"
```

Se lanci senza argomenti o con `--help`, lo script stampa la **guida iniziale**.

---

## Naming d’uscita (fisso)
- `sonar + neuralx` → `<nome>_AC3_sonar_neuralx.mkv`  
- `sonar + atmosx`  → `<nome>_AC3_sonar_atmosx.mkv`  
- `clean`           → `<nome>_AC3_clean.mkv`

La **traccia AC3 5.1** è sempre **48 kHz**, video **copiato** (`-c:v copy`), **sottotitoli copiati** quando presenti.

---

## Quando scegliere NeuralX o AtmosX?

| Voicing  | Carattere sonoro                  | Contenuti consigliati                                          |
|----------|-----------------------------------|----------------------------------------------------------------|
| NeuralX  | Cupola **ampia** e spettacolare   | Action / space-opera / cinecomic: *Star Wars*, MCU, *Transformers*, *Fast & Furious*, *Pacific Rim* |
| AtmosX   | Cupola **focalizzata** e precisa  | Noir / thriller / horror / sci-fi atmosferico: *Alien*, *Blade Runner 2049*, *Dune*, *The Batman*, *Tenet* |

> Mini-nota da nerd: entrambi implementano **ritardi early/late**, **passa-banda** nella regione **1,5–5 kHz**, **allpass** per una HRTF “gentile” e un **mix a pesi fissi**; **limiter** in uscita per evitare clip. Il tutto solo sui **surround**; i **front/center** restano sostanzialmente “sacri”.

---

## Come funziona (alto livello)
1. **Rilevamento layout** e, se necessario, **normalizzazione** a 5.1(side).  
2. **Split dei canali** → `[FL][FR][FC][LFE][SL][SR]`.  
3. **Voice-EQ** su FL/FR/FC con un *presence boost* attorno a **2,4 kHz**.  
4. **LFE**: **HPF 22 Hz** sempre attivo (anti-rumble).  
5. **Surround**:  
   - `sonar` → **NeuralX/AtmosX** con *early reflections*, *upfiring bandpass + allpass (HRTF light)*, *late energy* e **boost +3,2 dB**; **limiter** in coda.  
   - `clean` → nessun upfiring, solo **boost +2,9 dB** e **limiter**.  
6. **Merge** a 5.1(side) + resampling **soxr** alta precisione + **dither triangolare**.

---

## Installazione / Setup
- Metti lo script in una cartella del progetto (es. `tools/`) e rendilo eseguibile:
  ```bash
  chmod +x converti_2ac3_sonar_2x.sh
  ```
- Funziona su **Linux/macOS** e **Windows 11 con Git Bash**. Su Windows, se l’editor introduce CRLF:
  ```bash
  sed -i 's/\r$//' converti_2ac3_sonar_2x.sh
  ```

---

## Installazione FFmpeg

### Windows (Win10/11)
- **Winget** (consigliato, nativo):
  ```powershell
  winget install --id Gyan.FFmpeg -e
  # poi chiudi e riapri il terminale
  ffmpeg -version
  ```
- **Chocolatey**:
  ```powershell
  choco install ffmpeg
  ```
- **Scoop**:
  ```powershell
  scoop install ffmpeg
  ```
> In alternativa puoi scaricare gli zip “full” da build note (Gyan/BtbN), scompattare e aggiungere la cartella `bin` al `PATH` di Windows.

### Linux
- **Debian/Ubuntu/derivate**:
  ```bash
  sudo apt update && sudo apt install -y ffmpeg
  ```
- **Fedora** (consigliato attivare RPM Fusion):
  ```bash
  sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
  sudo dnf install -y ffmpeg
  ```
- **Arch/Manjaro**:
  ```bash
  sudo pacman -Syu ffmpeg
  ```
Verifica sempre con:
```bash
ffmpeg -version
ffprobe -version
```
Se i filtri `equalizer`, `allpass`, `aecho`, `alimiter`, `asplit` non compaiono, aggiorna FFmpeg.

---

## Clonare il repository e lanciare lo script

```bash
git clone https://github.com/Damocle77/Sonar_AC3D.git
cd Sonar_AC3D

# Rendi eseguibile lo script
chmod +x converti_2ac3_sonar_2x.sh

# Uso rapido
./converti_2ac3_sonar_2x.sh <sonar|clean|dualx> <si|no> <file.mkv> [bitrate] [neuralx|atmosx]
```
Esempi:
```bash
./converti_2ac3_sonar_2x.sh sonar no "Avengers.mkv" 640k neuralx
./converti_2ac3_sonar_2x.sh sonar si "Alien.mkv" 640k atmosx
./converti_2ac3_sonar_2x.sh clean no "Terminator.mkv" 
./converti_2ac3_sonar_2x.sh dualx no "Fast & Furious"

```

## Troubleshooting veloce
- **Errore “La prima traccia non è 5.1”** → verifica che l’audio sorgente sia 5.1 e sia la traccia `a:0`.  
- **Filtri non trovati** → aggiorna FFmpeg (serve `equalizer`, `allpass`, `alimiter`, `aecho`, `asplit`).  
- **Clip/distorsione** → i limiter sono inseriti, ma se il materiale è già hot potresti ridurre il gain globale.

---

## Limitazioni note
- Non trasforma un mix 5.1 in oggettuale: simula **altezza percepita** con ritardi/filtri sui surround.  
- Si aspetta **6 canali** sulla prima traccia audio; stereo/mono non sono gestiti.  
- Output in **AC3** per compatibilità ampia.

---

## Che preset scegliere in un colpo d’occhio

| Tipo contenuto                               | Preset consigliato   | Perché                                           |
|----------------------------------------------|----------------------|--------------------------------------------------|
| Action “continua” (Fast & Furious, supereroi)| **sonar + neuralx**  | Cupola ampia, ambienze e score respirano         |
| Fantasy/avventura “cinematografica”          | **sonar + neuralx**  | Ampiezza e verticalità avvolgente                |
| Thriller/Noir/Horror “chirurgici”            | **sonar + atmosx**   | Verticalità più netta, dettagli scolpiti         |
| Serie molto dialogate                        | **clean**            | Niente upfiring, dialoghi comunque top           |

---

## Altri script inclusi nel progetto

### `convert_2AC3_audiocheck.sh`
Piccolo tool da linea di comando per **elencare le tracce audio** di un file `.mkv`: codec, canali, layout, bitrate, sample rate, lingua e `title`. Utile per verificare rapidamente che la **prima traccia sia 5.1** prima di lanciare la conversione.  
**Uso:**
```bash
./convert_2AC3_audiocheck.sh <file.mkv>
```
Output ordinato, una scheda per traccia. (Vedi script nel repo.)

### `convert_2AC3_sonar_2x_batch.sh`
Launcher batch che richiama `convert_2AC3_sonar.sh` su **tutti i file `.mkv` nella cartella corrente** (o su un singolo file passato come quinto argomento). Stampa progressi e tempo totale.  
**Uso tipico:**
```bash
# Esempio: modalità sonar, non conservare originale, preset e bitrate
./convert_2AC3_sonar_2x_batch.sh sonar no eac36 640k

# Esempio su singolo file specifico
./convert_2AC3_sonar_2x_batch.sh sonar no eac36 640k "/percorso/Film.mkv"
```
Il batch verifica la presenza dello script principale prima di partire e scansiona la directory corrente per i `.mkv`. (Vedi script nel repo.)

---

## Licenza
MIT. Usa, remix, proietta. Se ti va, lascia una ⭐ e raccontami come suona la *Kessel Run* nel tuo salotto.

---

## Ringraziamenti
Per riportare ordine nel caos della Forza sonora non servono spade laser: basta un terminale e questo script…     
**Questa è la via!**

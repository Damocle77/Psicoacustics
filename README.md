<p align="left">
  <img src="psico_logo.png" width="700" alt="Sonary Suite Logo">
</p>

# 🎧 Psychoacoustic Suite - Novembre 2026

Suite di script **Bash AWK + FFmpeg** per analizzare, normalizzare, correggere e trasformare tracce audio stereo, 5.1 ed EAC3 Atmos/JOC in modo offline, ripetibile e controllato.

>Non tutti gli eroi indossano un mantello. Alcuni impugnano `ffmpeg` e riscrivono le leggi del suono. **Perché nel multiverso del caos sonoro, ogni voce merita di essere ascoltata**.

## Indice degli argomenti

- [Schema di riferimento](#schema-di-riferimento)
- [Requisiti](#requisiti)
- [Installazione](#installazione)
- [Script inclusi](#script-inclusi)
- [Controlli dopo l'elaborazione](#controlli-dopo-lelaborazione)
- [Quick Start](#quick-start-comandi-manuali)
- [1. Analyzer: analisi e classificazione 5.1](#1-audio_analyzer_volamp_psychosh)
- [2. Aegis / Sonar / Wide / Aura / Voiceita: processing 5.1](#2-aegis_sonar_wide_aura_voice_volamp_psychosh)
- [3. Upmix stereo → 5.1](#3-stereo251_upmix_psychosh)
- [4. ASMR / VR: processing per cuffie](#4-asmr_vr_intimate_psychosh)
- [5. Atmos: preparazione EAC3 5.1](#5-atmos_to_51_dynaudnorm_psichosh)
- [Workflow consigliati](#workflow-consigliati)
- [Benchmark orientativo](#benchmark-orientativo)
- [Troubleshooting](#troubleshooting)
- [Cosa la suite non fa](#cosa-la-suite-non-fa)
- [Licenza](#licenza)
- [Autore](#autore)

La filosofia è semplice: **misurare prima, processare dopo**. Il Classifier dell'analyzer misura scena full-band, prominenza della voce, mascheramento e width dei surround; sceglie quindi il preset per-file più adatto e può generare un batch riproducibile. Gli altri script coprono upmix stereo, preparazione Atmos/EAC3 e processing binaurale per cuffie.

La taratura 5.1 è pensata per un impianto domestico con frontali, centrale e surround compatti, tutti configurati **Small** con crossover AVR unico intorno a **110 Hz**, uno o due subwoofer attivi gestiti dall'AVR, ascolto medio/basso e priorità all'intelligibilità della voce in generale ed italiana in particolare.

La pipeline 5.1 (preparatore Atmos, analyzer e processore Aegis/Sonar/Wide/Aura/Voiceita) disattiva la **DRC dei metadati Dolby** nella decodifica AC3/EAC3 con l'opzione di input `-drc_scale:<indice_stream> 0`, posta prima di `-i` nel comando FFmpeg. L'opzione è applicata allo stream selezionato; gli altri codec mantengono la propria decodifica. Il DRC dell'AVR è indipendente e non può annullare una compressione già incorporata nei campioni di un render precedente. Le tracce originali conservate con stream copy mantengono dati e metadati originali.

Setup di riferimento: **Yamaha RX-V4A**, frontali **Harman Kardon 3 vie**, centrale/surround **JBL SCS200**, 2x subwoofer **Kenwood ST40**, bass management AVR a **110 Hz**.

I frontali a torre vengono comunque utilizzati come diffusori **Small**: il loro vantaggio è principalmente nella maggiore capacità dinamica e nella migliore riproduzione della gamma medio-alta, mentre il contenuto sotto il crossover resta affidato al bass management dell'AVR.

## Schema di riferimento

<p align="left">
  <img src="sonar_room_layout.png" width="700" alt="Schema layout stanza 5.1 Sonary Suite">
</p>

Obiettivi principali:

- dialoghi intelligibili senza effetto megafono;
- surround presenti ma non invadenti;
- basso controllato, con gestione principale demandata ad AVR e subwoofer;
- processing selettivo: SONAR non viene applicato indiscriminatamente;
- make-up gain finale coerente fra analyzer e processore;
- batch ripetibili su film, episodi e cartelle intere;
- conservazione separata del percorso Atmos originale quando richiesta.

---

## Requisiti

### Software

- **FFmpeg 8.x** richiesto e supportato;
- **ffprobe**;
- **Bash 4.x+**;
- **awk** per analisi e controlli audio;
- **mktemp** per i temporanei di tutti e cinque gli script;
- **GNU coreutils** per l’analyzer (`sha256sum`, `stat -c`, `realpath`, `mv -T`), oltre alle normali utility shell;
- build FFmpeg con **libsoxr** per `stereo251_upmix...`;
- build FFmpeg con **libbs2b** per `asmr_vr_intimate...`.

Gli script audio non richiedono Python.

La suite è sviluppata e verificata con **FFmpeg/ffprobe 8.1.2**. Non usare release con major superiore a 8 (`9.x` o successive) finché la suite non viene nuovamente validata: output testuale di `astats`/`ebur128`, opzioni dei filtri e semantica dei channel layout possono cambiare. Anche FFmpeg 7.x e precedenti sono fuori dal perimetro supportato. È consigliato usare `ffmpeg` e `ffprobe` provenienti dalla stessa build.

L’upmix richiede `resampler=soxr` e controlla SOXR all’avvio, senza fallback automatico. Lo script ASMR verifica invece `bs2b` all'avvio e termina con un errore esplicito se il filtro non è disponibile.

Verifiche utili:

```bash
ffmpeg -version
ffprobe -version
ffmpeg -hide_banner -filters 2>/dev/null | grep -w bs2b
ffmpeg -hide_banner -h filter=aresample 2>&1 | grep -i soxr
```

### Sistemi operativi

- Linux;
- macOS con Bash 4+ e GNU coreutils nel `PATH` (la dotazione di sistema non basta per l’analyzer);
- Windows tramite MSYS2, Git Bash o WSL2.

AC3/EAC3 vengono codificati via CPU. L'accelerazione hardware, quando disponibile, riguarda normalmente il video, che in questa suite viene copiato senza ricodifica.

---

## Installazione

```bash
git clone https://github.com/Damocle77/Sonary_Suite.git
cd Sonary_Suite
chmod +x *.sh
```

Se si scarica lo ZIP, estrarlo completamente prima di eseguire gli script.
La versione di lavoro è costituita dai cinque script principali `.sh` e dal README nella cartella principale, senza copie sperimentali di test. Il processore 5.1 e il preparatore Atmos usano la taratura aggiornata descritta sotto, con DRC Dolby disattivata in decodifica. Gli archivi `.rar` rimasti sono copie precedenti: non vengono aggiornati insieme ai file attivi e non vanno estratti sopra questi ultimi senza un confronto.

I comandi di questa guida vanno eseguiti in Bash (su Windows: Git Bash, MSYS2
o WSL). Per esempio, in Git Bash `cd /e/Download` apre `E:\Download`.
Usare `bash nome_script.sh` oppure `./nome_script.sh`; racchiudere tra virgolette
i percorsi dei file che contengono spazi.

Controllo sintattico rapido:

```bash
for f in *.sh; do
  bash -n "$f" || exit 1
done
```

---

## Script inclusi

| Script | Scopo |
|---|---|
| `audio_analyzer_volamp_psycho.sh` | Classifier per 5.1: Delta surround/centro, banda voce, mascheramento, width, target `-21 LUFS`, volamp automatico **2.0–3.0 dB** e batch opzionale |
| `aegis_sonar_wide_aura_voice_volamp_psycho.sh` | Processore 5.1 con preset `aegis`, `sonar`, `wide`, `aura`, `voiceita`, EQ voce, surround psicoacustici nei preset spaziali, controllo LFE e compensazione FC/LFE attivata dal profilo EAC3 Atmos o dal marker originale |
| `stereo251_upmix_psycho.sh` | Upmix V10 stereo → 5.1: matrice L-R, centro assist, rear bed adattivo in `to51`, LFE minimo, output atomico/verificato e preset `quad` dedicato alla musica |
| `asmr_vr_intimate_psycho.sh` | Processing stereo per cuffie/ASMR/VR con BS2B, ITD opzionale, loudnorm post-DSP, LFO e output atomico/verificato |
| `atmos_to_51_dynaudnorm_psicho.sh` | Prepara un MKV con EAC3 5.1 normalizzata come primaria e traccia Atmos/EAC3 originale copiata come secondaria |

> Nota naming: il file Atmos mantiene il nome storico `psicho`. Il README usa il nome reale del file.

---

## Controlli dopo l'elaborazione

| Processore | Controllo mantenuto | Possibile correzione automatica |
|---|---|---|
| Aegis / Sonar / Wide / Aura / Voiceita | Formato della traccia primaria con ffprobe | Nessuna |
| Preparatore Atmos | Formato della traccia primaria con ffprobe | Nessuna |
| Upmix TO51 / QUAD | True Peak integrale post-codec, soglia −0,1 dBTP | Un retry con attenuazione fino a 3 dB |
| ASMR | True Peak integrale post-codec, soglia del preset | Un retry con attenuazione fino a 3 dB |

Nei quattro processori sono state rimosse le scansioni comparative integrali della sorgente e dell'output per RMS, sample peak e numero di campioni. Restano gli errori FFmpeg, i controlli preventivi e la pubblicazione tramite file temporaneo. L'analyzer conserva le misure necessarie alle proprie decisioni.

I messaggi finali specificano **«formato traccia verificato»** oppure **«True Peak verificato»**: nessuno dei due indica un confronto completo con il segnale sorgente. Le caratteristiche dell'upmix V10 sono documentate nella sezione dedicata sotto.

## Quick Start: comandi manuali

Analizzare un file senza generare il batch:

```bash
./audio_analyzer_volamp_psycho.sh eac3 no 768k no "film.mkv"
```

Elaborare un file scegliendo preset e volume (qui SONAR, 2,0 dB):

```bash
./aegis_sonar_wide_aura_voice_volamp_psycho.sh eac3 si 768k sonar 2.0 "film.mkv"
```

Elaborare tutti i file compatibili nella cartella corrente:

```bash
./aegis_sonar_wide_aura_voice_volamp_psycho.sh eac3 si 768k sonar 2.0 ""
```

Il contributo verticale aumentato è già predefinito per SONAR e AEGIS. La compensazione Atmos si attiva sulle sorgenti riconosciute. I comandi diretti qui mostrati non trasferiscono automaticamente i gain LFE/Bass trim calcolati dall'analizzatore: queste due correzioni restano a zero. Il flusso con batch che le applica è descritto nella sezione dell'analizzatore.

---

# 1. `audio_analyzer_volamp_psycho.sh`

Analyzer per tracce **5.1**. Non modifica i file audio.

Il classificatore separa la scena full-band dalla banda utile alla voce:

```text
DeltaSur   = RMS(SL/SR) - RMS(FL/FR/FC)
DeltaFC    = RMS(FC) - RMS(FL/FR)
VoiceDelta = RMS 250-5000 Hz(FC) - RMS 250-5000 Hz(FL/FR)
VoiceMask  = RMS 250-5000 Hz(SL/SR) - RMS 250-5000 Hz(FC)
```

`VoiceDelta` misura la prominenza del centrale nella banda del parlato;
`VoiceMask` aumenta quando effetti e ambienza posteriori possono mascherarlo.
Le metriche full-band restano dedicate alla scelta del trattamento spaziale.

**Limite VoiceBand:** queste metriche misurano energia fra 250 e 5000 Hz, non
riconoscono il parlato. Musica, motori o altri effetti nel centrale possono far
apparire favorevoli `VoiceDelta` e `VoiceMask` anche quando coprono i dialoghi.
`CENTER_FULL_SAFETY_GATE` controlla invece il bilanciamento full-band: nessuna
di queste soglie separa voce ed effetti nello stesso canale. Le medie sull'intera
traccia possono inoltre nascondere singole scene problematiche. Il preset
suggerito resta un'indicazione di bilanciamento, non una misura certificata
dell'intelligibilità.

Il preset **VOICEITA** dà priorità ai dialoghi italiani con una taratura dedicata
del canale centrale e surround senza espansione spaziale. È una scelta manuale
da provare quando il parlato sembra impastato o poco in primo piano.
L'analyzer misura il bilanciamento dei canali, ma non determina quanto siano
comprensibili le parole: per questo non seleziona automaticamente VOICEITA.
La scelta si basa sull'ascolto del film e sulle preferenze personali.

## Caratteristiche

- selezione del 5.1 score-based: lingua italiana e flag default, senza confronto con la durata del container;
- decodifica AC3/EAC3 con DRC Dolby disattivata, coerente con il processore;
- misura in un'unica decodifica full-duration `I(full)`, `LRA`, sample peak,
  full-band, banda voce, `Width MS` e finestre LFE/bassi;
- indicatore di avanzamento durante la scansione completa;
- cache persistente delle metriche, invalidata automaticamente quando cambia il file, lo stream o lo schema analitico;
- discriminante Atmos tramite profilo E-AC-3 ufficiale esposto da FFprobe, con marker stabile del pre-processore come fallback;
- target loudness interno: **`-21.0 LUFS`**;
- fake-5.1 gate: surround virtualmente muti, centrale silenzioso o SL/SR sbilanciati bloccano la pubblicazione del batch;
- debolezza e mascheramento del centrale restano diagnostici; i preset automatici sono solo AEGIS, SONAR, WIDE e AURA;
- `sonar` per surround molto arretrati, `aura` per arretramento moderato;
- `wide` quando SL/SR risultano stretti o collassati, `aegis` per mix equilibrati;
- verdetto stagionale modale con almeno **2/3 di consenso**; altrimenti `MIXED`;
- `MIXED` anche quando lo spread di `DeltaSur` supera `4 dB`;
- volamp automatico con base **2.0 dB** e massimo **3.0 dB**;
- cap del volamp a **2.0 dB** quando `LRA >= 18 LU`;
- `run_processing.sh` opzionale tramite parametro `run=si|no`;
- colori distinti in console:
  - SONAR rosso;
  - AEGIS arancione;
  - WIDE verde;
  - AURA viola/magenta;

## Sintassi

```bash
./audio_analyzer_volamp_psycho.sh <codec> <keep> <bitrate> <run> <file|directory|"">
./audio_analyzer_volamp_psycho.sh --files <codec> <keep> <bitrate> [run] <file1> [file2 ...]
```

Compatibilità: resta accettato il vecchio ordine `<file|directory|""> [codec] [keep] [bitrate] [run]`.

## Parametri

| Parametro | Valori | Default | Note |
|---|---|---:|---|
| `codec` | `eac3`, `ac3` | `eac3` | codec scritto nel batch |
| `keep` | `si`, `no` | `no` | indica al processore se conservare la traccia sorgente selezionata |
| `bitrate` | `256k–640k` AC3; `256k–768k` EAC3, step da `64k` | `640k` AC3, `768k` EAC3 | accetta anche il numero senza suffisso; valori fuori range o fuori step vengono rifiutati |
| `run` | `si`, `no` | `si` | crea/aggiorna oppure non tocca `run_processing.sh` |
| `file|directory|""` | file, directory o stringa vuota | obbligatorio | `""` usa la cartella corrente |

## Bilanciamento LFE automatico

L'analyzer calcola e applica nel batch un **gain statico per file entro ±2 dB**. Non usa AGC, non cambia la scelta di preset/VOLAMP e non modifica i limiter. Il preparatore Atmos non riceve processing LFE dedicato; il mux diretto e l'opzione del passa-alto restano invariati.

Le misure LFE condividono la decodifica integrale già usata per loudness, RMS e banda voce. Un ramo solo analitico filtra i sei canali a **20–120 Hz** e li divide in finestre coincidenti da **0,5 secondi**, senza padding dell'ultima finestra. Questo filtro di misura non modifica il file né introduce un passa-alto nel processing finale.

- **Active RMS:** media energetica LFE, pesata per campioni, delle finestre sopra la maggiore fra `−60 dBFS` e il massimo RMS di finestra meno `30 dB`.
- **P95:** percentile 95 delle stesse finestre attive, pesato per campioni, con istogramma a risoluzione 0,1 dB.
- **Peak:** massimo sample peak LFE full-band, compresa l'energia fuori dalla banda analitica; non è True Peak.
- **Bass mains:** somma delle energie FL/FR/FC/SL/SR sulle medesime finestre attive LFE, mediata nel tempo. Non è una somma dei segnali e non simula fase, crossover o acustica dell'AVR.
- **Delta:** Active RMS meno Bass mains. Non si assume che zero rappresenti equilibrio acustico.

Le soglie nella sezione `LFE_*` valgono per **tutte le sorgenti 5.1 supportate**, Atmos e non Atmos. La classe descrive il delta originale:

| Delta LFE − bass mains | Classe |
|---|---|
| `< −18 dB` | VERY_WEAK |
| `−18 .. < −14 dB` | WEAK |
| `−14 .. −6 dB` | BALANCED |
| `> −6 .. −2 dB` | HOT |
| `> −2 dB` | VERY_HOT |

### Attenuazione: eccesso e persistenza

Per applicare un taglio servono almeno **30 secondi di LFE attivo** e un riferimento mains medio superiore a `−60 dBFS`. Per i tagli non è più richiesto che l'attività copra il 5% dell'intero file.

La **persistenza** è la percentuale del tempo LFE attivo in cui il delta della singola finestra supera una soglia, pesata per campioni. Le finestre senza bassi mains sopra `−60 dBFS` non confermano l'eccesso, ma restano nel denominatore. Una finestra finale parziale pesa soltanto per i campioni effettivi.

| Condizione dopo l'eventuale compensazione Atmos | Gain LFE candidato |
|---|---:|
| Delta medio `> −2 dB` e almeno il **50%** del tempo attivo con delta `> −2 dB` | **−2 dB** |
| Altrimenti, delta medio `> −6 dB` e almeno il **25%** del tempo attivo con delta `> −6 dB` | **−1 dB** |
| Eccesso occasionale o già compensato | **0 dB** |

Le soglie di delta sono strette (`>`); durata minima e percentuali includono il valore di soglia (`>=`). Se non è confermato il taglio di −2 dB, viene comunque valutato quello di −1 dB. Il gain resta fisso per tutto il file: non segue le singole scene.

```bash
LFE_CUT_MIN_ACTIVE_SECONDS=30.0
LFE_HOT_MIN_PERSISTENCE=0.25
LFE_VERY_HOT_MIN_PERSISTENCE=0.50
LFE_ATMOS_COMPENSATION_DB=-0.5
```

Queste sono costanti nello script, non opzioni CLI. Per le sorgenti Atmos verificate, delta e persistenza usati per il taglio includono il **−0,5 dB LFE già previsto dal processore**. Per le altre sorgenti l'offset è zero. La cache conserva entrambe le coppie di persistenza, prima e dopo la compensazione. VOLAMP è comune a LFE e principali e si cancella nel rapporto.

La classe può quindi restare `VERY_HOT` mentre il gain è −1 o 0 dB. Il report mostra delta originale, delta dopo compensazione, offset Atmos, persistenza come frazione (`0.43` = 43%), attività, classe, gain e motivo. Il successivo coordinamento con Bass trim può ridurre ulteriormente il taglio LFE.

### Aumenti e dati insufficienti

Gli aumenti mantengono i controlli precedenti: almeno **10 secondi** di LFE attivo e il **5%** dei campioni del file, con mains sopra `−60 dBFS`. `VERY_WEAK` propone +2 dB e `WEAK` +1 dB. Prima di consentire il boost si considera la somma nominale di VOLAMP, compensazione Atmos e nuovo gain: P95 non oltre `−18 dBFS` e sample peak full-band non oltre `−2 dBFS`. Il boost può essere ridotto in passi di 0,5 dB o azzerato.

LFE assente, layout non confermabile, dati insufficienti o override di sicurezza del 5.1 producono `INSUFFICIENT_DATA` e **0 dB**. Il probe può estendere l'analisi iniziale a 20 MB / 20 secondi per confermare il layout.

Le soglie sono sperimentali, da tarare all'ascolto. Per i tagli non è stata introdotta una nuova soglia assoluta RMS/P95. Il gain Dolby di riproduzione non viene aggiunto al file. La correzione riguarda il **canale LFE**: il subwoofer riceve anche i bassi dei principali tramite bass management. Un LFE a gain zero può comunque essere attenuato dal Bass trim. I margini sui picchi non costituiscono una verifica True Peak post-codec.

### Batch e cache

Rigenerare `run_processing.sh` per usare le nuove decisioni: i batch esistenti conservano i gain espliciti già calcolati. Il batch passa `--lfe-gain` e `--bass-trim` al processore; le singole righe restano modificabili entro i range consentiti.

La cache usa lo schema **`classifier-rms-voiceband-ebur-lfe-bass-v6-no-dolby-drc`**, con 38 campi. Conserva le misure LFE e Bass, quattro frazioni di persistenza LFE, attività e ultime decisioni. Le strutture precedenti vengono invalidate automaticamente, comprese le metriche ottenute prima della disattivazione della DRC Dolby. Finestra, gate di misura, soglie HOT/VERY_HOT LFE, offset Atmos e soglia HOT Bass entrano nella chiave perché cambiano le misure. Durata minima e percentuali richieste per decidere il taglio vengono ricalcolate anche su cache HIT.

## Bass trim automatico: bassi complessivi

LFE balance corregge il rapporto fra LFE e principali. **Bass trim** affronta invece un mix ricco di bassi anche nei principali: applica un **low-shelf a 100 Hz, Q 0,707, da 0 a −3 dB su tutti e sei i canali**, prima dei limiter. Non modifica preset o VOLAMP, non introduce un passa-alto e non aumenta mai i bassi.

L'analyzer riusa le finestre 20–120 Hz da 0,5 s e aggiunge, nella stessa decodifica, un riferimento sincronizzato 250–5000 Hz. Il confronto usa:

- bassi: somma delle energie dei cinque principali più energia LFE pesata di un fattore 10 (+10 dB **solo nel calcolo**, mai aggiunti al file);
- riferimento: somma delle energie medio-alte dei cinque principali, sulle medesime finestre;
- finestre valide: riferimento sopra la maggiore fra −60 dBFS e il massimo RMS di riferimento meno 30 dB;
- Bass Delta: rapporto in dB fra le medie energetiche dei bassi e del riferimento, pesate per campioni;
- persistenza: frazione dei campioni validi nelle finestre con rapporto bassi/riferimento superiore a +6 dB;
- P95 Delta: percentile diagnostico del rapporto per finestra, con risoluzione 0,1 dB.

È una **stima energetica**, non una ricostruzione del segnale fisico del sub: non comprende fase, crossover, calibrazione, modi della stanza o la risposta dei diffusori. Il livello assoluto da solo non decide il trim. Il filtro di analisi non viene applicato al file audio.

Servono almeno 10 secondi validi, il 5% del file e layout affidabile senza override di sicurezza del 5.1. In caso contrario: `INSUFFICIENT_DATA`, trim zero. Una persistenza inferiore al 25% lascia trim zero anche in presenza di picchi forti. Con evidenza sufficiente:

| Bass Delta | Classe | Trim |
|---|---|---:|
| ≤ +6 dB | BALANCED | 0 dB |
| > +6 .. +9 dB | HOT | −1 dB |
| > +9 .. +12 dB | VERY_HOT | −2 dB |
| > +12 dB | EXTREME | −3 dB |

Le costanti `BASS_*` dell'analyzer sono soglie iniziali euristiche, da tarare con confronti d'ascolto; non sono uno standard di mastering. L'attenuazione è fissa per tutto il file: nessun AGC. Il report mostra riferimento, delta, P95, persistenza, durata valida, classe, trim e motivo.

**Coordinamento automatico:** quando Bass trim è negativo, un eventuale boost LFE viene azzerato. Se gain LFE + Bass trim scenderebbe sotto −3 dB, viene ridotto il taglio LFE. Il budget vale per le nuove correzioni automatiche nel basso profondo e non include VOLAMP o compensazione Atmos. Vicino a 100 Hz il low-shelf è in transizione, quindi la somma non rappresenta un gain piatto su tutta la banda.

Il processore accetta anche la scelta manuale:

```bash
./aegis_sonar_wide_aura_voice_volamp_psycho.sh eac3 no 768k sonar 2.0 --lfe-gain 0 --bass-trim -2 "film.mkv"
./aegis_sonar_wide_aura_voice_volamp_psycho.sh --files eac3 no 768k sonar 2.0 --bass-trim -1 -- "ep 1.mkv" "ep 2.mkv"
```

`--bass-trim` accetta decimali con punto fra −3 e 0; default 0, nessun filtro aggiunto. Il parser rifiuta valori positivi, non numerici, fuori range, mancanti o opzioni ripetute. Il processore applica i valori manuali indicati: il coordinamento del budget viene effettuato dall'analyzer, non sovrascrive una scelta manuale esplicita.

Ordine finale: **processing preset → Bass shelf su ciascun canale → gain VOLAMP/LFE/Atmos previsti → limiter di canale → join → limiter master**. Le impostazioni dei limiter non cambiano. Nei log la somma dei gain LFE è indicata separatamente dal low-shelf, che dipende dalla frequenza.

Rigenerare il batch con `run=si` per ottenere entrambe le correzioni automatiche. I comandi preesistenti senza `--bass-trim` mantengono il risultato precedente. Il preparatore Atmos e il suo mux diretto restano invariati. Il nuovo schema cache invalida automaticamente i record precedenti.

## Cache e avanzamento

La prima analisi resta full-duration. Le metriche validate vengono salvate nella
cartella `.clearvoice_analyzer_cache`; una successiva analisi dello stesso file
le riutilizza senza decodificare nuovamente l'episodio. La chiave comprende
percorso canonico, dimensione, data di modifica, indice dello stream e versione
dell'algoritmo.

```bash
ANALYZER_CACHE=0 ./audio_analyzer_volamp_psycho.sh eac3 no 768k si ""
ANALYZER_PROGRESS_INTERVAL=5 ./audio_analyzer_volamp_psycho.sh eac3 no 768k si ""
ANALYZER_CACHE_DIR=/percorso/cache ./audio_analyzer_volamp_psycho.sh eac3 no 768k si ""
```

`ANALYZER_CACHE=0` disattiva la cache; l'intervallo di avanzamento predefinito è
10 secondi. Eliminare `.clearvoice_analyzer_cache` forza un ricalcolo completo.

Dopo un cambio di taratura, rigenerare `run_processing.sh`: i batch già creati conservano i volamp, i gain LFE e i Bass trim espliciti precedenti. La cache contiene metriche audio e può essere riutilizzata quando cambiano solo le soglie decisionali.

Con `run=no`, un eventuale `run_processing.sh` già esistente **non viene sovrascritto né cancellato**.

Nella modalità `--files`, il token dopo il bitrate viene interpretato come `run` solo se è esattamente `si` o `no`; altrimenti è trattato come primo filename, mantenendo la compatibilità con la sintassi precedente.

## Esempi

```bash
# Singolo file, EAC3 768k, batch abilitato
./audio_analyzer_volamp_psycho.sh eac3 no 768k si "film.mkv"

# Solo analisi
./audio_analyzer_volamp_psycho.sh eac3 si 768k no "film.mkv"

# Cartella corrente + batch
./audio_analyzer_volamp_psycho.sh eac3 no 768k si ""

# Lista esplicita, nessun batch
./audio_analyzer_volamp_psycho.sh --files eac3 si 768k no \
  "ep01.mkv" "ep02.mkv" "ep03.mkv"

# Sintassi compatibile: run=si implicito
./audio_analyzer_volamp_psycho.sh --files eac3 si 768k \
  "ep01.mkv" "ep02.mkv"
```

## Decisione → preset

| Priorità | Condizione principale | Preset | Interpretazione |
|---:|---|---|---|
| 1 | `DeltaSur < -13 dB` | `sonar` | surround molto arretrati, trattamento Atmos-like più energico |
| 2 | `Width MS < -7 dB` | `wide` | surround stretti/collassati, allargamento laterale |
| 3 | `DeltaSur < -7 dB` | `aura` | surround moderatamente arretrati, intervento posteriore morbido |
| 4 | altrimenti | `aegis` | scena equilibrata, trattamento DTS:X-like bilanciato |

Nel ramo `SONAR`, `DeltaSur < -13 dB` continua a selezionare `SONAR`: se nello stesso caso `Width MS < -7 dB`, `WIDE` viene riportato come alternativa diagnostica e la confidence diventa bassa, con motivo "surround molto arretrati e contemporaneamente stretti/collassati". Questa alternativa ha precedenza su `AURA` per SONAR borderline; non viene applicato alcun processing combinato.

Surround virtualmente muti (RMS < −65 dBFS o un canale a −inf), centrale silenzioso (−inf) o sbilanciamento SL/SR ≥ 10 dB bloccano il batch con un warning e richiedono controllo manuale. Le metriche restano nel report; nessun comando CHECK viene generato. Le soglie voce restano diagnostiche, anche vicino ai confini; se la banda è vuota vengono indicate N/A.

Il discriminante Atmos dell'analyzer usa il profilo E-AC-3 esposto da FFprobe oppure il marker affidabile della traccia originale. Se il classifier ha scelto `AURA`, applica queste regole:

| Condizione | Risultato |
|---|---|
| `DeltaSur < -10.0 dB` e `Width MS >= -7 dB` | promozione a `SONAR`, confidenza bassa, alternativa `AURA` |
| promozione non applicabile e `DeltaSur < -8.5 dB` | resta `AURA`, confidenza bassa, alternativa `SONAR` |
| altrimenti | resta `AURA` |
| preset misurato `AEGIS` | resta `AEGIS`, alternativa di ascolto `SONAR` |

`WIDE` e la sua alternativa impediscono gli override Atmos. Le anomalie gravi bloccano il batch prima della pubblicazione. La compensazione di volume FC/LFE del processore è indipendente dagli override del preset: viene attivata dal profilo EAC3 Atmos oppure dal marker completo della traccia originale, come descritto in [Compensazione del bed Atmos](#compensazione-del-bed-atmos). `bias preset=no` non disabilita gli offset.

Il riepilogo di tutti i preset separa `Audio` (layout della traccia selezionata, ad esempio `5.1(side)`) da `Atmos` (`verificato` o `non verificato`). Nei commenti del batch, `OutputAudio=5.1(side)` indica il layout prodotto dal processore.

## Width MS

```text
Width MS = RMS(SIDE) - RMS(MID)
```

| Width MS | Diagnosi |
|---:|---|
| `< -12 dB` | collassato |
| `-12 / -7 dB` | stretto |
| `-7 / -3 dB` | medio |
| `>= -3 dB` | largo |

## Volamp automatico

La base è ridotta a 2,0 dB per limitare quanto il secondo stadio spinge contro i limiter. Se necessario, compensare il livello di ascolto sul Volume Trim dell’ingresso AVR (indicativamente +1,5–2 dB), verificando il risultato all’ascolto. I batch già generati mantengono i gain espliciti precedenti: rigenerarli per adottare la nuova taratura.

Il volamp è il make-up gain applicato dal processore ai singoli canali prima del join 5.1. Sul canale LFE viene applicato prima del limiter dedicato, così i picchi del sub vengono controllati prima del master limiter multicanale. L'analyzer usa la loudness integrata del file rispetto al target `-21 LUFS`.

| Deficit rispetto al target | Volamp |
|---:|---:|
| `< 1.8 dB` | `2.0 dB` |
| `1.8 / <3.0 dB` | `2.5 dB` |
| `>= 3.0 dB` | `3.0 dB` |

Protezione per mix molto dinamici:

| LRA | Cap |
|---:|---:|
| `>= 18 LU` | massimo `2.0 dB` |

Il minimo automatico è **2.0 dB**, allineato al default del processore, ed è usato anche quando la misura di loudness manca o non è valida. I valori della tabella sono gain totali, non incrementi da sommare alla base. Con LRA `>= 18 LU`, gli eventuali recuperi a `2.5` o `3.0 dB` vengono limitati alla base di `2.0 dB`.

## `run_processing.sh`

Quando `run=si`, il batch contiene righe simili a:

```bash
"$PROC" "$CODEC" "$KEEP" "$BITRATE" sonar 2.0 --lfe-gain 0.0 --bass-trim 0.0 -- film.mkv || BATCH_FAILURES=$((BATCH_FAILURES + 1))  # DeltaSur=-14.2 dB | DeltaFC=1.0 dB | VoiceDelta=2.3 dB | VoiceMask=-12.0 dB | Width=-4.1 dB | I=-21.9 LUFS
```

Il valore subito dopo il preset (`2.0` nell'esempio) è il volamp realmente passato al processore. Seguono i gain LFE e Bass trim calcolati per il file; `--` separa le opzioni dal percorso. Il batch conta gli eventuali fallimenti tramite `BATCH_FAILURES`. Il commento è abbreviato nell'esempio: le righe generate includono anche layout, stato Atmos, confidenza e altre metriche. Il batch usa:

```bash
PROC="${PROC:-./aegis_sonar_wide_aura_voice_volamp_psycho.sh}"
```

Il processore controlla il profilo EAC3 Atmos e il marker direttamente nel file di input a ogni esecuzione, anche quando viene chiamato dal batch. Gli offset Atmos non sono incorporati nel valore `volamp` scritto dall'analyzer e non richiedono nuovi argomenti.

I messaggi Atmos e di mapping visualizzati durante `run_processing.sh` provengono dal processore indicato da `PROC`. Per aggiornare queste descrizioni basta aggiornare lo script del processore usato dal batch; non serve rigenerare il batch.

Il batch usa sempre il preset per-file, derivato dalla classificazione spaziale `DeltaSur` e `Width MS`, con diagnostica `DeltaFC`, `VoiceDelta`, `VoiceMask` e controllo di sicurezza balance. Il P25 di `DeltaSur` è soltanto diagnostico; il verdetto stagionale richiede almeno 2/3 di consenso e non sostituisce mai il preset scritto nelle singole righe del batch.

---

# 2. `aegis_sonar_wide_aura_voice_volamp_psycho.sh`

Motore principale per tracce **5.1 esistenti**.

## Caratteristiche

- input 5.1, output AC3/EAC3 5.1(side);
- DRC Dolby disattivata nel decoder AC3/EAC3 prima dei filtri; nessuna opzione Dolby sugli altri codec;
- preset `aegis`, `sonar`, `wide`, `aura`, `voiceita`; `voiceita` è solo manuale, escluso dalla selezione dell'analyzer;
- selezione stream score-based: entrano solo tracce a 6 canali; lingua italiana `+300`, flag default `+200`; la durata del container non entra nel punteggio;
- layout gestiti: `5.1`, `5.1(back)`, `5.1(side)`;
- con sei canali e layout assente o `unknown`, il log mostra `5.1(side)`, indicando il mapping posizionale adottato (`FC=c2`, `SL=c4`, `SR=c5`); questa descrizione non modifica i metadati della sorgente. La stessa convenzione è usata dall'analyzer e dal preparatore Atmos;
- EQ voce dedicato per ogni preset;
- limiter sul centrale dopo il volamp e l’eventuale compensazione Atmos, senza auto-level;
- processing surround differenziato per preset;
- air/decorrelation layer controllato;
- microboost finale sui soli SL/SR: bell a 3200 Hz, Q 1,2, +0,1 dB nei preset spaziali e +0,2 dB in VOICEITA;
- Bass trim opzionale: low-shelf a 100 Hz sui sei canali prima dei limiter, da −3 a 0 dB;
- trattamento LFE: volamp, correzione statica `--lfe-gain` ed eventuale compensazione Atmos prima del limiter dedicato; filtraggio dedicato affidato all’hardware;
- compensazione del bed **FC +0,5 dB / LFE −0,5 dB**, con profilo EAC3 Atmos o marker originale, per tutti i preset;
- diffusori mantenuti `Small`, con bass management e crossover a circa `110 Hz` affidati all'AVR; lo script applica ai canali principali solo un high-pass di sicurezza a `20 Hz`;
- `FRONT_EQ` leggermente adattato alle torri senza widening o alterazioni della scena frontale;
- volamp manuale `0–5.0 dB`, default **2.0 dB** se omesso; un valore esplicito prevale sempre;
- warning sopra `2.0 dB`;
- video, sottotitoli, capitoli e allegati copiati;
- keep opzionale della traccia 5.1 selezionata;
- DSP, codifica audio e mux in un unico processo FFmpeg, verso un MKV temporaneo;
- nessuna scansione comparativa integrale sorgente/output dopo il DSP;
- controllo della traccia primaria: codec richiesto, 6 canali, `5.1(side)`, 48 kHz e flag default;
- pubblicazione del file finale soltanto dopo encode/mux e controllo di formato riusciti;
- nessuna misura True Peak post-codec o retry;
- contatori finali ed exit code non zero se almeno un file fallisce.

## Definizione del surround diretto

| Preset | Canali | Filtro | Frequenza | Gain | Q |
|---|---|---|---:|---:|---:|
| AEGIS, SONAR, WIDE, AURA | SL e SR | Bell (peaking EQ) | 3200 Hz | +0,1 dB | 1,2 |
| VOICEITA | SL e SR | Bell (peaking EQ) | 3200 Hz | +0,2 dB | 1,2 |

AEGIS, SONAR, WIDE e AURA mantengono il passa-alto a **20 Hz, Q 0,707** sui rami diretti `SLd_in` e `SRd_in`. Il microboost di presenza è un filtro a campana a **3200 Hz, Q 1,2** (valore storico), applicato una sola volta ai soli `SL_final` e `SR_final`: **+0,1 dB** nei quattro preset psicoacustici e **+0,2 dB** in VOICEITA.

Ordine effettivo: blocco surround del preset → decorrelazione/ambienza finale (bypass in VOICEITA) → microboost SL/SR → bass trim e VOLAMP → join 5.1, highshelf e limiter finali. Il filtro interviene sul segnale già elaborato senza modificare gli ingressi o i parametri degli algoritmi spaziali. Non introduce aumenti del guadagno generale dei surround; la riduzione manuale di circa 1 dB sull'impianto resta un dato del contesto di ascolto. Il beneficio percettivo di incrementi così piccoli non è garantito e richiede un confronto d'ascolto controllato.

In WIDE resta il **highshelf a 3500 Hz, +0,1 dB, Q 0,8** dopo gli `amix` SL/SR: è indipendente dal microboost finale. La verticalità continua a dipendere dai rami HEIGHT e la larghezza dai delay, dagli allpass e dai rami decorrelati dei preset.

Restano invariati i delay diretti (**0 ms** in AEGIS/SONAR, **1 ms** in WIDE/AURA), tutti i valori di volume e i rami di presenza, HEIGHT, riflessione tardiva, decorrelazione e ambienza. La decorrelazione finale mantiene la catena e i parametri esistenti. Nessuna modifica a FL/FR, FC, LFE, limiter, VOLAMP, gestione Atmos o controlli di pubblicazione.

### VOICEITA — priorità ai dialoghi italiani

<p align="left">
  <img src="voceita_diagram.png" width="900" alt="Diagramma del processing audio del preset VOICEITA">
</p>

**VOICEITA è un preset manuale pensato per favorire la leggibilità del parlato italiano.**
Sul centrale riduce parte delle medio-basse e aggiunge una presenza moderata
nella gamma vocale, con l'obiettivo di rendere le parole più distinguibili
mantenendo il corpo della voce. I surround ricevono il passa-alto a 20 Hz
e il microboost finale a 3200 Hz di +0,2 dB, senza espansione spaziale aggiunta.

È una variante da confrontare con gli altri preset quando i dialoghi risultano
impastati o poco in primo piano, soprattutto nell'ascolto domestico a volume
medio/basso. AEGIS, SONAR, WIDE e AURA combinano l'EQ del centrale con diverse
elaborazioni spaziali dei surround; VOICEITA concentra la propria taratura sul
parlato e mantiene invariato il guadagno generale dei surround, aggiungendo
solo la lieve enfasi di presenza descritta sopra.

La taratura è fissa e agisce su **tutto il canale centrale**, inclusi musica ed
effetti presenti: non separa la voce. Il nome indica la destinazione della
taratura, non un riconoscimento della lingua o del doppiaggio. Il risultato
va valutato su dialoghi reali, confrontando i preset a volume percepito
pareggiato; un miglioramento non è garantito su ogni mix.

**Livello del centrale.** Il gain dedicato è `volume=3.7dB`, seguito da
`volume=0.95`: circa **+3,25 dB netti esclusa l'EQ, prima dei guadagni condivisi**.
Il sostegno è aumentato di **0,6 dB** per portare il centrale più in primo piano,
a EQ invariata, incluso il bell a 150 Hz di +0,2 dB. È una correzione statica:
non recupera selettivamente le battute deboli e il beneficio va verificato
nei passaggi critici; sui picchi può aumentare l'intervento del limiter.
Questo parametro è distinto dal **VOLAMP**, che regola il guadagno comune ai
canali. Restano attivi i limiter e le eventuali compensazioni Atmos condivise.

**EQ del centrale (FC).** Catena autonoma, senza sommare `VOICE_EQ_BASE`:

| Filtro | Frequenza | Gain | Q |
|---|---:|---:|---:|
| Passa-alto | 20 Hz | — | 0,707 |
| Bell | 150 Hz | +0,2 dB | 1,1 |
| Bell | 300 Hz | −1,0 dB | 1,0 |
| Bell | 450 Hz | −0,6 dB | 1,2 |
| Bell | 1650 Hz | +0,7 dB | 1,6 |
| Bell | 2450 Hz | +1,4 dB | 1,3 |
| Bell | 3800 Hz | +0,9 dB | 2,0 |

I tagli a **300 e 450 Hz** mirano a mitigare il parlato gonfio e impastato
(effetto "patata"); i rialzi a **1650, 2450 e 3800 Hz** favoriscono
l'articolazione e la presenza delle consonanti. La catena dedicata non
aggiunge filtri a 1100, 5200, 6800 o 7200 Hz.

**Surround (SL/SR).** Passa-alto a 20 Hz Q 0,707 e microboost finale
a campana a 3200 Hz, +0,2 dB, Q 1,2, senza aumento del guadagno generale
(senza `volume=0.88`). `DECORR_GAIN_VOICEITA="0"`: nessuna espansione, delay,
allpass o decorrelazione aggiuntiva.
Restano applicati VOLAMP, bass trim e processing finale condiviso.

**Selezione manuale.** Scegliere `voiceita` nel processore oppure sostituire
solo il nome del preset in una riga del batch generato dall'analyzer,
conservando VOLAMP, `--lfe-gain` e `--bass-trim` calcolati per il file.
L'analyzer continua a selezionare esclusivamente AEGIS, SONAR, WIDE o AURA:
le sue metriche non misurano direttamente la comprensibilità delle parole.

`voiceita` usa la propria taratura FC e il processing finale condiviso. Gli output `_AC3_Voiceita.mkv` e `_EAC3_Voiceita.mkv` vengono riconosciuti per lo skip automatico.

## Contributo verticale SONAR / AEGIS

Il processore usa **`HEIGHT_MODE=increased` per impostazione predefinita**: moltiplica per **1,15** il livello dei soli rami verticali `SLh` e `SRh`, prima della somma con gli altri rami surround. Il valore vale per l'intera elaborazione, su sorgenti Atmos e non Atmos; l'analyzer non lo seleziona in base alle misure.

| Variabile di ambiente | Moltiplicatore del ramo verticale |
|---|---|
| `HEIGHT_MODE=reduced` | 0,75 |
| `HEIGHT_MODE=normal` | 1,00; nessun filtro aggiunto, livello precedente |
| `HEIGHT_MODE=increased` | **1,15; default** |

Il controllo riguarda solo **SONAR e AEGIS**. WIDE, AURA e VOICEITA mantengono il proprio processing. Ritardi, EQ e ramo di ambienza non vengono regolati da questa variabile. L'output resta 5.1: il fattore non indica una percentuale di altezza percepita né un aumento del volume dell'intero surround.

```bash
# Usa increased automaticamente, salvo una variabile HEIGHT_MODE già esportata
./aegis_sonar_wide_aura_voice_volamp_psycho.sh eac3 si 768k sonar 2.0 "film.mkv"

# Ripristina il contributo verticale precedente per questa esecuzione
HEIGHT_MODE=normal ./aegis_sonar_wide_aura_voice_volamp_psycho.sh eac3 si 768k sonar 2.0 "film.mkv"

# Applica la scelta ai processi avviati dal batch
HEIGHT_MODE=reduced ./run_processing.sh
```

Il batch non registra una scelta HEIGHT_MODE per file: eredita la variabile di ambiente o usa il default del processore. Anche i batch precedenti che richiamano il processore aggiornato usano il nuovo default; per aggiornare invece i gain LFE calcolati occorre rigenerare il batch. Il nome del file prodotto non include HEIGHT_MODE: conservare le varianti con nomi distinti durante i confronti.

## Correzione statica LFE

`--lfe-gain <dB>` accetta numeri decimali con punto da `-2.0` a `+2.0`, default `0.0`. Non cambia VOLAMP, preset, filtri o limiter. Un valore zero non aggiunge alcun filtro al percorso precedente. Le opzioni duplicate, incomplete o fuori intervallo vengono rifiutate; `--` termina le opzioni per proteggere i nomi dei file.

```bash
./aegis_sonar_wide_aura_voice_volamp_psycho.sh eac3 no 768k sonar 2.0 --lfe-gain -1.0 "film.mkv"
./aegis_sonar_wide_aura_voice_volamp_psycho.sh --files eac3 no 768k sonar 2.0 --lfe-gain -0.5 -- "ep 1.mkv" "ep 2.mkv"
```

Ordine: **LFE → eventuale Bass shelf → VOLAMP → LFE gain → compensazione Atmos → limiter LFE → join → limiter master**. Per esempio, `+4.0 -1.5 -0.5 = +2.0 dB` nominali prima del limiter. Il guadagno effettivo nei picchi può essere inferiore; l’eventuale Bass shelf introduce inoltre un’attenuazione dipendente dalla frequenza. Nei log le tre componenti e la loro somma sono separate. I vecchi comandi senza opzione mantengono gain LFE zero.

## Sintassi

```bash
./aegis_sonar_wide_aura_voice_volamp_psycho.sh \
  <ac3|eac3> <si|no> <bitrate> <preset> <volamp> <file|"">
./aegis_sonar_wide_aura_voice_volamp_psycho.sh --files \
  <ac3|eac3> <si|no> <bitrate> <preset> <volamp> <file1> [file2 ...]
```

Compatibilità: resta accettato il vecchio ordine `<codec> <keep> <file|""> [bitrate] [preset] [volamp]`. Nel vecchio formato il parsing è flessibile: l'ultimo valore numerico fra `0` e `5.0` è il volamp; un numero `>=32` può essere interpretato come bitrate senza suffisso.

## Parametri

| Parametro | Valori | Default | Note |
|---|---|---:|---|
| `codec` | `ac3`, `eac3` | obbligatorio | codec in uscita |
| `keep` | `si`, `no` | obbligatorio | conserva la traccia sorgente selezionata |
| `bitrate` | `256k–640k` AC3; `256k–768k` EAC3, step da `64k` | `640k` AC3, `768k` EAC3 | valori fuori range vengono rifiutati prima dell'encoding |
| `preset` | `aegis`, `sonar`, `wide`, `aura`, `voiceita` | `sonar` | modalità DSP; `voiceita` solo manuale |
| `volamp` | `0–5.0` | `2.0` | gain per-canale prima del join e dei limiter dedicati; un valore esplicito prevale sul default |
| `file` | file o stringa vuota | cartella corrente | `""` usa la cartella corrente |

## Versione principale

La versione corrente è **Novembre 2026**, con DRC Dolby disattivata in decodifica e gain staging aggiornato: dynaudnorm con i parametri originali `peak=0.92` e `maxgain=4`, seguito dal limiter in coda, passa-alto subsonico a 20 Hz sui canali principali, VOLAMP base 2,0 dB e limiter FC/master a 0,89 con release 80 ms. EQ, rami spaziali e compensazioni Atmos mantengono la taratura esistente.

I tempi dei limiter del processore sono: **FC 1,5 / 80 ms**, **LFE 2 / 120 ms** e **master 2,5 / 80 ms** (attack / release). Processore e preparatore Atmos verificano il formato della traccia primaria, senza scansioni True Peak post-codec o retry. Gli output mantengono i nomi consueti, per esempio `film_EAC3_Sonar.mkv` e `film-0.mkv`; il batch dell'analyzer richiama il processore principale.

I controlli True Peak e gli eventuali retry già presenti nell'upmix e nell'ASMR restano quelli descritti nelle rispettive sezioni. Non sono copie sperimentali del processore 5.1 o del preparatore Atmos.

## Catena finale

Tutti i preset usano:

```text
split 5.1
→ EQ frontali / EQ centrale / processing surround (HEIGHT_MODE su SONAR/AEGIS)
→ eventuale Bass shelf sui sei canali
→ volamp individuale FL/FR/FC/SL/SR
→ FC: eventuale offset Atmos +0,5 dB → limiter dedicato
→ LFE: volamp → --lfe-gain → eventuale offset Atmos −0,5 dB → limiter dedicato
→ join 5.1(side)
→ high-shelf finale sui canali non-LFE
→ master limiter 5.1
→ formato finale 48 kHz / fltp
→ encoding AC3/EAC3 e mux nello stesso processo FFmpeg
→ MKV temporaneo
→ verifica codec / 6 canali / 5.1(side) / 48 kHz / default
→ pubblicazione MKV dopo encode/mux e controllo di formato riusciti
```

Parametri principali:

```text
FRONT_EQ:
  -0.4 dB @ 320 Hz
  +0.4 dB @ 5 kHz
  +0.4 dB high-shelf @ 11 kHz

FC (dopo il volamp):
  volume +0,5 dB con profilo EAC3 Atmos o marker originale
  alimiter limit=0.89, attack=1.5 ms, release=80 ms, level=0, latency=1

LFE:
  eventuale Bass shelf
  volamp
  correzione --lfe-gain
  volume −0,5 dB con profilo EAC3 Atmos o marker originale
  alimiter limit=0.94, attack=2 ms, release=120 ms, level=0, latency=1

Master:
  high-shelf +0.4 dB @ 12 kHz sui canali non-LFE
  alimiter limit=0.89, attack=2.5 ms, release=80 ms, level=0, latency=1
  output 48 kHz / fltp / 5.1(side)
```

I limiter FC, LFE e master usano tutti `level=0`: non aggiungono auto-level al volamp impostato. FC e master limitano a `0.89` (circa −1,01 dBFS); il limiter LFE resta a `0.94`, prima del master comune.

Il margine sui campioni riduce il rischio di overshoot, ma non garantisce un tetto True Peak dopo AC3/EAC3: la ricodifica lossy può generare nuovi picchi. Il passa-alto a 20 Hz riduce l’intervento vicino al crossover rispetto a 40 Hz, ma non elimina ogni rotazione di fase né garantisce l’allineamento con subwoofer e AVR. Occorrono misure e ascolto sul sistema reale.

## Compensazione del bed Atmos

La taratura richiesta nasce dal design del preset **Atmos Original** usato in questo workflow, che prevede una maggiore presenza del canale LFE. La compensazione riduce leggermente il LFE e sostiene il centrale nel bed elaborato, per riequilibrare il rapporto tra basso e dialoghi. Il workflow estende questa taratura alle sorgenti verificate tramite profilo EAC3 Atmos. Resta una scelta di taratura del progetto, non una proprietà generale attribuita al formato Dolby Atmos.

Il processore aggiunge **+0,5 dB al FC** e **−0,5 dB al LFE**, dopo il volamp e prima dei rispettivi limiter, quando una traccia EAC3 del contenitore espone un profilo FFprobe contenente «Atmos», oppure, come fallback, una traccia audio porta uno dei marker affidabili. Il confronto usa il titolo completo, senza distinzione tra maiuscole e minuscole, e gestisce i terminatori CRLF di FFprobe su Windows.

| Prova rilevata sulle tracce audio dell'input | Compensazione |
|---|---|
| Profilo EAC3 Atmos, anche senza marker | attiva |
| `EAC3 Atmos Original` | attiva |
| `EAC3 Atmos (Original)` (legacy) | attiva |
| Solo `EAC3 Original`, senza profilo EAC3 Atmos | disattivata |
| Nessun profilo EAC3 Atmos e nessun marker esatto | disattivata |

Il marker può essere sulla traccia originale secondaria mentre viene elaborata la 5.1 normalizzata primaria. Questa regola vale per `aegis`, `sonar`, `wide`, `aura` e `voiceita`. Il profilo EAC3 Atmos ha priorità sul marker. Il nome del file o un titolo generico contenente «Atmos» non attivano gli offset.

Valori configurabili in testa a `aegis_sonar_wide_aura_voice_volamp_psycho.sh`:

```bash
ATMOS_FC_GAIN_DB="0.5"
ATMOS_LFE_GAIN_DB="-0.5"
```

Il centrale è già impostato a +0,5 dB. Per cambiare la taratura, modificare `ATMOS_FC_GAIN_DB` e `ATMOS_LFE_GAIN_DB` nel processore e mantenere `LFE_ATMOS_COMPENSATION_DB` in analyzer allineato al valore LFE. Questi parametri non sono argomenti CLI né override da variabili d'ambiente.

Gli offset si sommano al volamp anche quando `volamp=0`. Per esempio, con `volamp=2.0`, `--lfe-gain 0` e `--bass-trim 0`, gli stadi di volume finale valgono complessivamente **+2,5 dB sul FC** e **+1,5 dB sul LFE**; EQ, gain del preset e intervento dei limiter concorrono al livello audio effettivo.

Il controllo viene ripetuto per ogni file: nessuna prova Atmos disponibile (profilo o marker) lascia entrambi gli offset disattivati, senza ereditare lo stato del file precedente. Il log riporta l'attivazione con i valori applicati oppure la disattivazione.

Analyzer, processore e preparatore usano descrizioni uniformi per l'esito del controllo:

```text
[ATMOS] Atmos verificato nella traccia audio originale.
[ATMOS] Atmos non verificato nella traccia audio originale.
```

Il messaggio positivo non specifica il numero dello stream né la prova utilizzata. Nell'analyzer e nel processore può derivare dal profilo FFprobe oppure dal marker affidabile; il preparatore verifica il profilo. Il messaggio negativo indica che non è stata trovata una prova riconosciuta. Il processore aggiunge i valori della compensazione o ne segnala la disattivazione; il preparatore indica il fallback EAC3 quando necessario. Le regole di riconoscimento restano quelle descritte sopra.

La compensazione viene applicata nel processore finale; il preparatore Atmos non applica questi due offset. Passare al processore il contenitore intermedio completo: estraendo soltanto il bed si perdono le prove della seconda traccia; in assenza di un profilo EAC3 Atmos sul bed, la compensazione resta disattivata.

Il file prodotto resta **5.1 con un solo canale LFE**. Un eventuale impianto **5.2** distribuisce il canale `.1` ai due subwoofer tramite l'AVR; lo script non crea due canali LFE separati.

## Codifica e pubblicazione

Il DSP, la codifica AC3/EAC3 e il mux avvengono in un unico processo FFmpeg, verso `mux.mkv` nella directory univoca `.<nome_output>.partial.<casuale>/`, riservata con `mktemp` accanto all'output. Vengono copiati il primo stream video non allegato, sottotitoli, allegati, metadati e capitoli, oltre alla traccia originale selezionata se `keep=si`.

Sono state rimosse le due scansioni comparative integrali, una della sorgente e una dell'output, con RMS, sample peak e conteggio campioni. Rimane il controllo strutturale della prima traccia: **codec richiesto (`ac3` o `eac3`), 6 canali, `5.1(side)`, 48 kHz e flag default**. Il probe usa fino a 20 MB / 20 secondi di analisi iniziale; non percorre tutta la traccia.

Il candidato sostituisce il file finale solo dopo encode/mux e controllo di formato riusciti. Gli errori FFmpeg sono fatali (`-xerror`). Errori o interruzioni conservano `mux.mkv` e `filter_complex.txt` per il debug; dopo la pubblicazione i temporanei vengono rimossi. `INT` e `TERM` terminano con codice `130` e `143`.

I limiter FC, LFE e master restano invariati. Il True Peak post-codec non viene misurato e non sono previsti retry. Senza confronto audio integrale, un contenitore formalmente corretto con segnale muto, canali persi o durata anomala potrebbe superare il controllo di formato.

## Decorrelazione

**Downmix stereo:** i ritardi e i rami decorrelati possono cambiare il timbro
quando i surround vengono sommati ai frontali. Nelle prove sintetiche con
segnali coerenti, `wide` e `aura` mostrano un'attenuazione marcata a 500 Hz,
alla quale contribuisce il ritardo di 1 ms sul ramo surround diretto. Questo
risultato non descrive tutti i mix reali e non indica un errore di decodifica,
ma richiede un controllo dedicato se l'output sarà ascoltato soprattutto in
stereo. `voiceita` non aggiunge questi ritardi né decorrelazione.
Il microboost a 3200 Hz viene applicato dopo questo blocco, sui segnali
`SL_final` e `SR_final`, e non modifica i parametri di decorrelazione.

Per valutare la decorrelazione restano necessari confronti su estratti reali con volume pareggiato, anche in downmix stereo.

| Preset | `DECORR_GAIN` |
|---|---:|
| `sonar` | `0.055` |
| `aura` | `0.048` |
| `wide` | `0.042` |
| `aegis` | `0.034` |
| `voiceita` | `0` |

## Esempi

```bash
./aegis_sonar_wide_aura_voice_volamp_psycho.sh \
  eac3 no 768k sonar 2.0 "film.mkv"

./aegis_sonar_wide_aura_voice_volamp_psycho.sh \
  eac3 no 768k wide 2.0 "film.mkv"

./aegis_sonar_wide_aura_voice_volamp_psycho.sh \
  ac3 si 640k voiceita 2.0 "film.mkv"

# Batch nella cartella corrente
./aegis_sonar_wide_aura_voice_volamp_psycho.sh eac3 no 768k sonar 2.0 ""
```

## Output

```text
<nome>_EAC3_Sonar.mkv
<nome>_EAC3_Aegis.mkv
<nome>_EAC3_Wide.mkv
<nome>_EAC3_Aura.mkv
<nome>_EAC3_Voiceita.mkv
<nome>_AC3_Voiceita.mkv
```

---

# 3. `stereo251_upmix_psycho.sh`

Upmix offline da **stereo 2.0 a 5.1**, progettato per ottenere una scena multicanale plausibile senza simulare informazioni discrete che non esistono nella sorgente.

Il preset principale è `to51`:

- FL/FR restano full-band e mantengono il ruolo principale, con `FRONT_VOL=0.96` per creare headroom;
- il centrale è un assist ricavato da `L+R`, non sostituisce completamente il phantom center;
- i surround derivano soprattutto dalla componente laterale `L-R`;
- il rear bed mono è fortemente attenuato e filtrato nella banda vocale; V10 ne riduce ulteriormente il livello quando L/R sono correlati;
- il LFE sintetico è quasi nullo, perché il bass management resta affidato all'AVR;
- delay asimmetrici e all-pass producono una decorrelazione leggera senza attività posteriore artificiale costante.

Su una traccia stereo con L/R identici (mono duplicato sui due canali) o molto simili, surround quasi silenziosi sono un risultato previsto: la matrice `L-R` si annulla o si riduce e il bed adattivo viene attenuato. Una vera traccia a un solo canale viene invece saltata, perché lo script elabora soltanto ingressi a due canali.

Il preset `quad` replica invece FL verso SL e FR verso SR con banda limitata e delay Haas. È destinato soprattutto a **musica e concerti**; non è consigliato come default per film, serie, anime o cartoon perché può trascinare dialoghi nei posteriori.

## Sintassi

```bash
./stereo251_upmix_psycho.sh \
  <ac3|eac3> <si|no> [file|""] [bitrate] [to51|quad]
```

## Parametri

| Parametro | Valori | Default | Note |
|---|---|---:|---|
| `codec` | `ac3`, `eac3` | obbligatorio | codec in uscita; la disponibilità dell'encoder viene verificata prima del processing |
| `keep` | `si`, `no` | obbligatorio | conserva la traccia stereo originale come secondaria |
| `file` | file o `""` | cartella corrente | batch se omesso o vuoto |
| `bitrate` | step da `256k` a `640k` per AC3; fino a `768k` per EAC3 | `448k` | incrementi di `64k` |
| `preset` | `to51`, `quad` | `to51` | tipo di upmix |

Il parser accetta anche `448`, `448K` o valori con suffisso `M`, poi normalizza in kbps. Gli zeri iniziali vengono interpretati in base decimale: `0448K` equivale a `448k`. Valori fuori range o non allineati agli step previsti vengono rifiutati prima dell'encoding.

La selezione della traccia è score-based:

```text
stereo:   +1000
italiano: +300
default:  +200
```

Il parsing di `ffprobe` usa coppie chiave/valore e non dipende dall'ordine posizionale dei campi. Un errore di lettura viene contato come fallimento e produce exit code `1`; un contenitore valido senza audio stereo viene saltato.

Per ingressi AC3/EAC3, il decoder usa `drc_scale=0` per preservare la dinamica senza applicare la compressione dei metadata Dolby. Anche la misura True Peak del candidato usa `drc_scale=0`. Per gli altri codec non viene passata questa opzione privata del decoder.

## Preset

| Preset | Filosofia | Uso indicativo |
|---|---|---|
| `to51` | side matrix `L-R`, centro assist e rear bed mono appena percettibile | film, serie, anime, cartoon e fiction stereo |
| `quad` | FL→SL e FR→SR con Haas delay e banda limitata | musica e concerti stereo |

Valori principali:

```text
COMUNE:
  FRONT_VOL=0.96

TO51:
  FC_MIX=0.28
  FC_VOL=0.86
  FC_HP=60 Hz
  FC_LP=6500 Hz
  LFE_VOL=0.035

  SUR_PAN=0.50
  SUR_VOL=0.86
  SUR_BED_VOL=0.06
  SUR_ADAPTIVE=1

  delay side L/R=14/20 ms
  delay bed  L/R=24/33 ms

  banda side=170–8500 Hz
  banda bed=320–5600 Hz
  attenuazione marcata del bed nella banda vocale

QUAD:
  FC_MIX=0.28
  FC_VOL=0.78
  FC_HP=60 Hz
  FC_LP=5200 Hz
  LFE_VOL=0.03

  QUAD_VOL=0.58
  delay L/R=16/19 ms
  banda rear=250–8000 Hz
  air layer=0.035
```

Il filtro del centrale parte da `60 Hz`, invece dei precedenti `102 Hz`, per evitare una doppia attenuazione quando l'AVR applica già il crossover globale intorno a `110 Hz`.

In V10 il centrale `to51` passa da `FC_MIX=0.32` a `0.28` (circa −1,16 dB); `FC_VOL` resta `0.86`. Il preset `quad` mantiene la propria taratura.

Con `SUR_ADAPTIVE=1`, il bed usa la correlazione full-band `r = E[L·R] / sqrt(E[L²]·E[R²])`, con medie esponenziali da circa 80 ms e protezione dalla divisione per zero. Il gain aggiuntivo è `0.35 + 0.65·clip(1-r, 0, 1)`: con L/R identici il bed scende di circa 9,1 dB, con correlazione nulla o negativa resta al livello impostato da `SUR_BED_VOL`. Calcolo e applicazione avvengono nello stesso filtro, senza una scansione preliminare o ritardi aggiuntivi. La side matrix resta invariata. Non è un riconoscitore di dialoghi e non crea canali posteriori indipendenti. `SUR_ADAPTIVE=0` ripristina il bed fisso; l'opzione riguarda solo `to51`.

## Catena finale

```text
selezione stereo score-based
→ SOXR 48 kHz / precision 28 (se serve ricampionare l'ingresso)
→ split FL/FR
→ centro assist L+R
→ LFE sintetico minimo
→ surround matrix/decorrelati
→ join 5.1(side)
→ SOXR 192 kHz / precision 28
→ alimiter limit=0.97, attack=3 ms, release=60 ms, level=0, latency=1
→ SOXR 48 kHz / precision 28 / cutoff 0.91
→ AC3/EAC3 con dialnorm -31
```

Il limiter è una protezione finale dei picchi, non un auto-level: `level=0`.

Prima del processing vengono verificati SOXR, l'encoder scelto e i filtri richiesti dal percorso selezionato. Sono state rimosse le scansioni comparative integrali stereo/5.1 della sorgente e del candidato.

Rimane la misura **True Peak post-codec integrale**, con soglia `-0.1 dBTP`. Se viene superata, viene eseguito un solo retry dalla sorgente: l'attenuazione finale vale `min(TP - (-0.1) + 0.2, 3.0) dB`, applicata dopo il ritorno a 48 kHz. Il secondo candidato deve superare nuovamente il controllo True Peak; misure non conclusive e altri errori bloccano la pubblicazione senza attivare retry. Il limiter 4x e la soglia True Peak restano invariati.

I temporanei `audio.mka`, eventuale `audio.retry.mka` e `mux.mkv` sono riservati con `mktemp` nella directory nascosta `.<nome_output>.partial.<casuale>/`. Dopo il controllo True Peak viene eseguito un unico mux completo con audio in copia e timestamp sorgente conservati. Il file finale viene sostituito solo a mux riuscito. Errori o interruzioni conservano i temporanei; `INT` e `TERM` terminano con codice `130` e `143`.

Il controllo True Peak comprende la decodifica completa del candidato e ne intercetta gli errori, ma non confronta durata, RMS o presenza dei canali con la sorgente.

## Output

```text
<nome>_UPMIX_5.1_V10_TO51.mkv
<nome>_UPMIX_5.1_V10_QUAD.mkv
```

La lingua viene propagata sia alla traccia processata sia, quando `keep=si`, alla traccia stereo originale. Il suffisso V10 distingue i nuovi risultati dai file V9; gli output con i suffissi riconosciuti dallo script, V10 compresa, vengono esclusi dal batch. Lo script mantiene i contatori `OK/FALLITI/SALTATI` e restituisce exit code `1` se almeno un file fallisce durante probe, encoding, verifica, mux o pubblicazione. Se tutti i file vengono saltati senza errori, termina con codice `0` e il messaggio «Nessun file elaborato».

## Esempi

```bash
# Film, serie, anime o cartoon: preset raccomandato
./stereo251_upmix_psycho.sh eac3 si "episodio.mkv" 448k to51

# Musica o concerto
./stereo251_upmix_psycho.sh eac3 si "concerto.mkv" 640k quad

# Batch nella cartella corrente
./stereo251_upmix_psycho.sh ac3 no "" 448k to51

# Default: EAC3, 448k, TO51
./stereo251_upmix_psycho.sh eac3 no
```

## Limiti della matrice e downmix stereo

Il preset `to51` usa una matrice `L+R` per il centrale, `L-R` e `R-L` per i surround, più un bed mono con livello adattivo. Non riconosce i dialoghi e non isola soltanto il contenuto comune ai due canali. Un suono presente solo a sinistra contribuisce quindi anche al centrale e a entrambi i surround. In dual-mono la componente laterale si annulla e il piccolo rear bed viene ulteriormente attenuato; con `L=-R` si annullano centrale e LFE sintetici, mentre i surround restano attivi.

La somma successiva in stereo dei canali filtrati e ritardati può modificare timbro e bilanciamento rispetto alla sorgente. Per ascolto stereo conservare la traccia originale con `keep=si`. Valutare eventuali modifiche a centrale, rear bed e ritardi con confronti a volume pareggiato sia in 5.1 sia in downmix: aumentare indiscriminatamente i surround non risolve i limiti della matrice.

## Tuning tramite ambiente

Riduzione moderata del centrale assist:

```bash
FC_VOL=0.82 FC_MIX=0.26 \
  ./stereo251_upmix_psycho.sh eac3 no "film.mkv" 448k to51
```

Incremento prudente dei surround laterali, senza aumentare subito il bed mono:

```bash
SUR_VOL=0.92 \
  ./stereo251_upmix_psycho.sh eac3 no "film.mkv" 448k to51
```

Riduzione dei posteriori nel preset musicale:

```bash
QUAD_VOL=0.50 \
  ./stereo251_upmix_psycho.sh eac3 no "concerto.mkv" 448k quad
```

Confronto del solo bed di `to51` con la modalità fissa:

```bash
SUR_ADAPTIVE=0 \
  ./stereo251_upmix_psycho.sh eac3 no "film.mkv" 448k to51
```

L'opzione cambia soltanto il bed; il centrale e le altre impostazioni restano quelli V10. L'output mantiene lo stesso nome V10: per conservare entrambe le varianti del confronto usare copie dell'ingresso con nomi diversi.

Variabili principali:

| Variabile | Effetto |
|---|---|
| `FRONT_VOL` | livello FL/FR e headroom preventiva |
| `FC_VOL` | livello del centrale assist |
| `FC_MIX` | quantità di `L+R` inviata al centrale |
| `FC_HP`, `FC_LP` | banda del centrale |
| `SUR_PAN`, `SUR_VOL` | componente laterale `L-R` del preset `to51` |
| `SUR_BED_VOL` | livello del rear bed mono |
| `SUR_ADAPTIVE` | `1` (default): attenua il bed correlato; `0`: bed fisso, solo in `to51` |
| `SUR_DELAY_L`, `SUR_DELAY_R` | delay asimmetrici della componente side |
| `BED_DELAY_L`, `BED_DELAY_R` | delay asimmetrici del rear bed |
| `QUAD_VOL` | livello rear del preset `quad` |
| `QUAD_DELAY_L`, `QUAD_DELAY_R` | delay rear del preset `quad` |
| `QUAD_HP`, `QUAD_LP` | banda rear del preset `quad` |
| `QUAD_AIR_VOL` | livello dell'air layer del preset `quad` |
| `LFE_VOL` | quantità di LFE sintetico |

## Controlli dell'upmix

Questa distribuzione non include una suite di regressione automatizzata. Per il controllo sintattico usare `bash -n stereo251_upmix_psycho.sh`. Il controllo True Peak integrale e l'eventuale retry vengono eseguiti dallo script sui candidati prodotti, come descritto sopra; non confrontano durata o identità dei canali con la sorgente. Verificare inoltre all'ascolto routing dei canali, sincronizzazione A/V e risultato dei preset su materiale reale.

---

# 4. `asmr_vr_intimate_psycho.sh`

Processing stereo per cuffie, ASMR, VR e sorgenti ravvicinate.

## Funzioni

- selezione stream stereo score-based;
- parser `ffprobe` chiave/valore e verifica preventiva dell'encoder scelto;
- high-pass a due poli e low-pass differenziati per preset;
- loudnorm post-DSP con target per distanza;
- crossfeed **BS2B J. Meier**;
- regolazione Mid/Side e crosstalk controllato;
- ITD tramite delay in campioni;
- EQ psicoacustico di prossimità;
- LFO opzionale `tremolo + flanger`;
- ITD disattivabile indipendentemente con `-t`;
- limiter finale posizionato **dopo ITD e LFO**;
- codec `aac`, `opus` tramite `libopus`, oppure `flac`;
- keep opzionale della traccia stereo originale;
- True Peak post-codec sull'intera traccia, senza scansione comparativa stereo;
- un solo retry dalla sorgente con trim finale fino a `3.0 dB`;
- candidato solo audio, mux completo unico e pubblicazione atomica;
- contatori ed exit code reali.

Lo script verifica `bs2b` e la disponibilità dell'encoder scelto prima di iniziare. Il filtro è obbligatorio per questo workflow.

## Sintassi

```bash
./asmr_vr_intimate_psycho.sh [opzioni] <file1> [file2 ...]
```

## Opzioni

```text
-o <dir>     directory di output
-d <mode>    whisper | near | center
-k           conserva la traccia originale
-l           abilita Breathing LFO
-t           disattiva ITD; consigliato per sorgenti gia' binaurali
-c <codec>   aac | opus | flac
-b <rate>    bitrate, default 320k; ignorato con FLAC
-f           forza overwrite
-h           help
```

La directory indicata con `-o` viene creata se non esiste; un errore di creazione interrompe lo script.

## Preset

| Preset | Target | Distanza | Limiter finale |
|---|---:|---:|---|
| `whisper` | `-20 LUFS`, `TP=-2.0`, `LRA=13` | 20–30 cm | `limit=0.96`, attack `2`, release `40`, `level=0`, `latency=1` |
| `near` | `-19 LUFS`, `TP=-1.8`, `LRA=12` | 30–50 cm | `limit=0.97`, attack `2.5`, release `45`, `level=0`, `latency=1` |
| `center` | `-18 LUFS`, `TP=-1.5`, `LRA=11` | frontale | `limit=0.97`, attack `3`, release `50`, `level=0`, `latency=1` |

Sequenza:

```text
band-pass
→ 48 kHz
→ BS2B
→ Mid/Side
→ crosstalk
→ EQ
→ ITD
→ LFO opzionale
→ loudnorm sul segnale gia' processato
→ 48 kHz
→ limiter finale
→ eventuale trim del retry
→ encoding AAC/Opus/FLAC in un candidato solo audio
→ True Peak post-codec integrale
→ mux unico con audio in copia dopo il controllo True Peak
```

Nota: il processing è progettato per materiale stereo. Su una sorgente già binaurale, BS2B e crosstalk possono modificare gli indizi interaurali originali; usare `-t` per evitare anche il ritardo ITD aggiuntivo e verificare con confronto A/B.

Sono state rimosse le scansioni comparative integrali della sorgente e del candidato con RMS e numero di campioni.

Rimane la decodifica integrale del candidato con `ebur128=peak=true`. Il **ceiling post-codec coincide con il TP del preset**: `-2.0 dBTP` per `whisper`, `-1.8 dBTP` per `near`, `-1.5 dBTP` per `center`, per AAC, Opus e FLAC. Un errore di decodifica o una misura mancante/non conclusiva blocca la pubblicazione.

Solo se il True Peak supera il ceiling viene effettuato un secondo e ultimo encode dalla sorgente, con attenuazione `min(TP misurato - ceiling + 0.2, 3.0) dB`. Il trim segue `loudnorm`, ritorno a 48 kHz e limiter. Il secondo candidato deve superare nuovamente il controllo True Peak. EQ, BS2B, ITD, LFO e preset restano invariati; il trim puo' ridurre la loudness rispetto al target nominale.

I temporanei `audio.mka`, eventuale `audio.retry.mka` e `mux.mkv` vengono riservati nella directory nascosta `.<nome_output>.partial.<casuale>/`, accanto all'output anche con `-o`. Il mux completo viene eseguito una sola volta dopo il controllo True Peak, copiando l'audio e conservando i timestamp. Il file finale viene sostituito solo a mux riuscito; errori e interruzioni conservano i temporanei. `INT` e `TERM` terminano con codice `130` e `143`.

Il True Peak non confronta durata, RMS o presenza dei canali con la sorgente.

## Esempi

```bash
./asmr_vr_intimate_psycho.sh \
  -d whisper -c aac -b 320k "asmr.mkv"

./asmr_vr_intimate_psycho.sh \
  -d near -k -l -o output "clip01.mkv" "clip02.mkv"

./asmr_vr_intimate_psycho.sh \
  -d center -c flac "voce.wav"
```

## Output

```text
<nome>_INTIMATE_WHISPER.mkv
<nome>_INTIMATE_NEAR.mkv
<nome>_INTIMATE_CENTER.mkv
<nome>_INTIMATE_WHISPER_NOITD.mkv
<nome>_INTIMATE_WHISPER_LFO.mkv
<nome>_INTIMATE_WHISPER_NOITD_LFO.mkv
```

---

# 5. `atmos_to_51_dynaudnorm_psicho.sh`

Pre-stadio per materiale **EAC3 Atmos/JOC**.

Lo scopo non è sostituire Atmos, ma creare due percorsi nello stesso MKV:

1. **EAC3 5.1 normalizzata**, primaria e `default`, destinata all'analyzer e agli script psicoacustici;
2. **EAC3 Atmos/EAC3 originale**, copiata bit-perfect come seconda traccia non default.

In termini tecnici FFmpeg decodifica il bed multicanale disponibile; non esegue il rendering degli oggetti Atmos come farebbe un AVR.

## Workflow previsto

```text
EAC3 Atmos/JOC originale
├─ decode bed/core multicanale con DRC Dolby disattivata
│  → 5.1(side)
│  → dynaudnorm (high-pass 20 Hz opzionale, disattivato di default)
│  → EAC3 5.1 normalizzata, traccia 1/default
└─ stream copy
   → traccia originale, traccia 2/non-default
```

Da qui si può scegliere:

```text
A. Riproduzione Atmos originale:
   selezionare la seconda traccia del file intermedio.

B. Percorso psicoacustico:
   passare il MKV intermedio completo ad analyzer/processore;
   viene elaborata la 5.1 normalizzata, con offset FC/LFE se presente il marker originale.
```

Lo script non tenta di reinserire automaticamente l'Atmos originale nei file prodotti da `aegis`; i due percorsi restano distinti.

## Sintassi

```bash
./atmos_to_51_dynaudnorm_psicho.sh [bitrate] <file|directory|"">
./atmos_to_51_dynaudnorm_psicho.sh --files <bitrate> <file1> [file2 ...]
```

Resta accettato il vecchio ordine `<file|directory|""> [bitrate]`.

## Parametri

| Parametro | Valori | Default | Note |
|---|---|---:|---|
| `file|directory|""` | file, directory o stringa vuota | obbligatorio | `""` usa la cartella corrente |
| `bitrate` | `256k–768k` in step da `64k` | `640k` | bitrate della EAC3 5.1 normalizzata |

## Selezione della traccia

Lo script:

- considera solo stream EAC3 con **esattamente 6 canali**; gli altri vengono esclusi con un avviso per evitare di scartare canali nel mapping `c0..c5`;
- riconosce Atmos tramite il profilo E-AC-3 ufficiale `Dolby Digital Plus + Dolby Atmos` esposto da FFprobe;
- usa un unico probe chiave/valore per indice, profilo, canali, layout, lingua e flag default;
- fra le tracce Atmos idonee assegna `+300` alla lingua italiana e `+200` al flag default;
- se Atmos non è rilevabile, usa il miglior EAC3 a 6 canali con lo stesso punteggio come fallback;
- invia il warning di fallback su `stderr`, senza contaminare il valore restituito dalla funzione di probe.

Se il fallback non è verificato come Atmos, il titolo della seconda traccia diventa:

```text
EAC3 Original
```

Questo titolo da solo non attiva la compensazione FC/LFE del processore. Quando la sorgente è riconosciuta come Atmos, il preparatore scrive invece `EAC3 Atmos Original`: è il marker che abilita gli offset nel successivo processing del bed.

La conferma interattiva legge dal terminale dello script: premere `s` per sovrascrivere, `n` per saltare o `t` per sovrascrivere tutti gli output successivi, senza Invio. Senza input interattivo, i file esistenti vengono saltati senza attese.

## Dynaudnorm

```text
dynaudnorm=
  framelen=500:
  gausssize=31:
  peak=0.92:
  maxgain=4:
  targetrms=0:
  compress=0:
  coupling=1:
  altboundary=0,
alimiter=level_in=1:level_out=1:limit=0.89:attack=10:level=0:latency=1
```

I valori `peak=0.92` e `maxgain=4` restano quelli originali: non sono disponibili misure che giustifichino una loro ritaratura. Il limiter aggiunto è uno stadio successivo e distinto.

Interpretazione:

- Passa-alto disattivato di default: nessun taglio fisso del basso prima della normalizzazione. Con `ATMOS_HIGHPASS_HZ=20` viene anteposto `highpass=f=20:t=q:w=0.707`, su tutti i canali incluso LFE; attenua anche il contenuto utile vicino a 20 Hz.
- `framelen=500`: finestra da 500 ms;
- `gausssize=31`: smoothing ampio;
- `peak=0.92`: target di picco con headroom;
- `maxgain=4`: **fattore lineare massimo**, non `4 dB`; nominalmente equivale a circa `+12.04 dB` di ampiezza;
- `targetrms=0`: target RMS disabilitato;
- `compress=0`: compressione aggiuntiva disabilitata;
- `coupling=1`: stesso fattore di gain sui canali, preservando il bilanciamento surround;
- `altboundary=0`: modalità boundary standard;
- limiter finale a `0.89` (circa −1,01 dBFS), lookahead `attack=10` ms, release predefinito 50 ms, `level=0` e `latency=1`. In FFmpeg il lookahead si configura con `attack`, non con un’opzione `lookahead`.

Il preparatore non applica gli offset FC/LFE né un trattamento specifico al solo LFE: dynaudnorm coinvolge tutti i canali, mentre il passa-alto generale a `20 Hz` viene applicato solo se richiesto. Il successivo processore applica volamp e limiter al canale `.1`, oltre a FC +0,5 dB e LFE −0,5 dB quando trova il profilo EAC3 Atmos o il marker originale. Il filtraggio dedicato dell’LFE è affidato all’hardware.

## Passa-alto: comportamento allineato della suite

| Script | Comportamento |
|---|---|
| Atmos → 5.1 | Nessun passa-alto per default; `ATMOS_HIGHPASS_HZ=20` abilita 20 Hz su tutti i canali, LFE incluso. |
| Stereo → 5.1 | Il passa-alto a 20 Hz resta sul solo LFE sintetico, sia in `to51` sia in `quad`. |
| Aegis / Sonar / Wide / Aura / Voiceita | Restano i passa-alto a 20 Hz dei canali principali. Bass trim opzionale sui sei canali. Nessun passa-alto dedicato sul LFE. |
| ASMR | Restano i passa-alto vocali dei preset a 60/70/80 Hz. |
| Analyzer | Misura il segnale; non applica un passa-alto al file da pubblicare. |

Per preservare il basso originale nel preparatore Atmos usare il default:

```bash
./atmos_to_51_dynaudnorm_psicho.sh 640k "film.mkv"
```

Per scegliere esplicitamente il filtro subsonico:

```bash
ATMOS_HIGHPASS_HZ=20 ./atmos_to_51_dynaudnorm_psicho.sh 640k "film.mkv"
```

Sono accettati solo `0` (default, disattivato) e `20`; altri valori vengono rifiutati. Se si prosegue con Aegis, il filtro opzionale si somma ai 20 Hz dei canali principali. Il bass management dell'AVR non recupera frequenze gia' attenuate nel file. La traccia Atmos originale in copia non viene filtrata.

## Verifica e pubblicazione

L'encoder EAC3 viene verificato prima di elaborare i file. Encoding e mux usano un solo processo FFmpeg con `-xerror`: sorgente, `aformat`, mapping posizionale e dynaudnorm, quindi candidato MKV con video, sottotitoli, allegati, audio normalizzato e audio originale. Nessun MKA intermedio e nessuna forzatura di `copyts` o `avoid_negative_ts`.

Le scansioni comparative integrali della sorgente e del candidato sono state rimosse per ridurre i tempi. Restano il controllo degli errori FFmpeg e il controllo strutturale della prima traccia: **EAC3, 6 canali, `5.1(side)`, 48 kHz e default**. Il probe usa una finestra iniziale fino a 20 MB / 20 secondi di analisi, utile anche dopo il buffering del filtro. Non viene misurato il True Peak post-codec e non sono previsti retry.

Il candidato `mux.mkv` viene creato nella directory univoca `.<nome_output>.partial.<casuale>/`. Il file finale viene sostituito solo dopo encoding/mux e controllo di formato riusciti. Errori o interruzioni conservano il candidato; `INT` e `TERM` terminano con codice `130` e `143`.

Il controllo di formato non rileva da solo audio muto, canali persi o durate anomale in un contenitore formalmente corretto.

## Output

```text
<nome>-0.mkv
```

Con:

```text
Traccia 1: EAC3 5.1 Normalized
           default, dialnorm -31

Traccia 2: EAC3 Atmos Original
           oppure EAC3 Original
           stream copy, non default
```

Lingua e metadata principali vengono propagati. Lo script mantiene contatori `OK/FALLITI/SALTATI` e restituisce exit code `1` se almeno un file fallisce.

## Esempi

```bash
./atmos_to_51_dynaudnorm_psicho.sh "film.mkv"
./atmos_to_51_dynaudnorm_psicho.sh "film.mkv" 768k
./atmos_to_51_dynaudnorm_psicho.sh /path/to/folder
./atmos_to_51_dynaudnorm_psicho.sh "" 768k
```

---

# Workflow consigliati

## Sorgente 5.1 già utilizzabile

```text
AC3/EAC3 5.1
→ audio_analyzer_volamp_psycho.sh
→ run_processing.sh
→ aegis/sonar/wide/aura (VOICEITA selezionabile solo manualmente)
```

## Sorgente Atmos/JOC

```text
Atmos/JOC
→ atmos_to_51_dynaudnorm_psicho.sh
→ file dual-track:
   - 5.1 normalizzata default
   - Atmos originale secondaria con titolo EAC3 Atmos Original
→ analyzer sul contenitore completo
→ processing psicoacustico opzionale con il preset scelto
   - marker presente: FC +0,5 dB / LFE −0,5 dB prima dei limiter
```

Il file dual-track resta il riferimento per la riproduzione Atmos non alterata. Il file psicoacustico è un'alternativa separata.

## Sorgente stereo destinata al 5.1

```text
Stereo
→ stereo251_upmix_psycho.sh
→ EAC3/AC3 5.1 plausibile
```

Per film, serie, anime e cartoon usare normalmente `to51`. Il risultato dell'upmix è già un prodotto finale: un successivo passaggio con Aegis non è raccomandato come default, perché rischia di amplificare nuovamente surround sintetici e decorrelazione. Analyzer e Aegis vanno usati solo dopo misure e confronto A/B, senza boost manuali aggiuntivi non giustificati.

## Sorgente stereo per cuffie

```text
Stereo
→ asmr_vr_intimate_psycho.sh
→ AAC/Opus/FLAC stereo processato
```

---

# Benchmark orientativo

| Script | Costo relativo | Motivo principale |
|---|---:|---|
| `audio_analyzer_volamp_psycho.sh` | Medio/Alto | una sola decodifica con rami EBU R128, RMS full-band/voice-band, width e finestre LFE/bassi; cache per le analisi successive |
| `stereo251_upmix_psycho.sh` | Medio/Alto | upmix, SOXR, True Peak integrale e possibile retry audio; mux unico |
| `asmr_vr_intimate_psycho.sh` | Medio/Alto | loudnorm, BS2B, True Peak integrale e possibile retry audio; mux unico |
| `atmos_to_51_dynaudnorm_psicho.sh` | Medio | dynaudnorm e mux unico; controllo rapido codec/layout |
| `aegis_sonar_wide_aura_voice_volamp_psycho.sh` | Medio/Alto | DSP 5.1, codifica audio e mux in un unico processo; controllo rapido codec/layout |

Il costo effettivo dipende da durata, codec sorgente, CPU, storage e build FFmpeg.

---

# Troubleshooting

## Gestione degli errori e limiti residui

L’analyzer distingue i file senza una traccia 5.1 idonea (saltati) dai fallimenti di probe/analisi. Restituisce `1` se almeno un file fallisce oppure se non ottiene alcun risultato valido. Una lista mista con file 5.1 validi e file non idonei può completarsi; una lista con errori non pubblica un batch parziale.

Con `run=si`, il batch viene scritto in un temporaneo nella stessa directory e pubblicato solo dopo scrittura e `chmod` riusciti. In caso di errore il vecchio batch resta intatto, con un avviso esplicito: non usarlo come risultato dell’analisi appena fallita. Per concatenare analisi ed esecuzione usare `&&`:

```bash
./audio_analyzer_volamp_psycho.sh eac3 no 768k si . && ./run_processing.sh
```

Con `run=no`, il batch esistente resta sempre intatto. `INT` e `TERM` fermano il decoder dell’analyzer, rimuovono i temporanei e terminano con codice `130` e `143`. Analyzer e Aegis usano `-xerror`. Lo schema attuale della cache dell’analyzer ricalcola le vecchie metriche con il controllo degli errori attivo e la DRC Dolby disattivata; rigenerare il batch per aggiornare anche preset e gain espliciti già salvati.

Restano possibili miglioramenti di manutenzione: uniformare i parser CSV di analyzer/Aegis ai parser chiave/valore degli altri script e completare i preflight. Il batch usa ancora percorsi relativi: eseguirlo dalla directory di generazione con il processore presente, oppure impostare `PROC` con un percorso assoluto.

Questa distribuzione contiene script eseguiti direttamente: non è presente una fase di compilazione né una configurazione CI GitLab. Prima della pubblicazione verificare repository e branch di destinazione; l’URL di installazione sopra è quello storico GitHub.

## Lo script non parte

```bash
chmod +x *.sh
bash -n nome_script.sh
ffmpeg -version
ffprobe -version
```

Su Windows/MSYS2/Git Bash:

```bash
which bash
which ffmpeg
which ffprobe
which awk
```

## `soxr` non disponibile

Sintomo tipico: errore nel filtro `aresample`.

Verifica:

```bash
ffmpeg -hide_banner -h filter=aresample 2>&1 | grep -i soxr
```

Serve un build FFmpeg compilato con libsoxr.

## `bs2b` non disponibile

Lo script ASMR termina prima dell'encoding.

```bash
ffmpeg -hide_banner -filters 2>/dev/null | grep -w bs2b
```

Serve un build con libbs2b.

## Non voglio creare `run_processing.sh`

```bash
./audio_analyzer_volamp_psycho.sh eac3 no 768k no .
```

Il file esistente resta intatto.

## Voglio analizzare solo alcuni episodi

```bash
./audio_analyzer_volamp_psycho.sh --files eac3 no 768k si \
  "ep01.mkv" "ep04.mkv" "ep08.mkv"
```

## `run_processing.sh` punta al processore sbagliato

Controlla:

```bash
grep -n '^PROC=' run_processing.sh
```

Valore previsto:

```bash
PROC="${PROC:-./aegis_sonar_wide_aura_voice_volamp_psycho.sh}"
```

## Il file è stereo, non 5.1

```bash
./stereo251_upmix_psycho.sh eac3 no "film_stereo.mkv" 448k to51
```

Oppure:

```bash
./stereo251_upmix_psycho.sh eac3 no "film_stereo.mkv" 448k quad
```

## Il file è Atmos/EAC3

```bash
./atmos_to_51_dynaudnorm_psicho.sh "film_atmos.mkv" 768k
```

Il risultato contiene la 5.1 normalizzata come traccia default e l'originale come seconda traccia. Per Atmos non alterato selezionare la seconda. Per il processing passare il MKV completo: la prima traccia viene elaborata e il marker `EAC3 Atmos Original` sulla seconda abilita gli offset FC/LFE con qualsiasi preset. Il solo fallback `EAC3 Original`, senza profilo EAC3 Atmos nel contenitore, lascia la compensazione disattivata.

## L'analyzer blocca il processing automatico

```text
Surround virtualmente muti: processing automatico bloccato.
```

Controllare il mix manualmente. Il batch non viene aggiornato; non eseguire un batch precedente per questa analisi.

## Il volamp sembra alto

Il processore usa `2.0 dB` come default se VOLAMP viene omesso, e accetta valori da `0` a `5.0 dB`. Un valore esplicito prevale sul default. L'analyzer sceglie un valore esplicito fra `2.0` e `3.0 dB` per i soli preset automatici AEGIS/SONAR/WIDE/AURA; `voiceita` resta manuale. I valori automatici possibili sono:

```text
2.0 = make-up DSP standard
2.5 = sorgente molto bassa
3.0 = sorgente estremamente bassa
```

Sopra `2.0 dB` il processore mostra un warning perché il limiter può lavorare in modo più percepibile. Il gain nominale non coincide necessariamente con l'aumento LUFS finale: dipende da picchi, EQ e intervento del limiter.

## Il centrale dell'upmix ruba scena

Ridurre prima `FC_MIX`, poi eventualmente `FC_VOL`:

```bash
FC_MIX=0.26 FC_VOL=0.82 \
  ./stereo251_upmix_psycho.sh eac3 no "film.mkv" 448k to51
```

## I surround TO51 sono troppo timidi

Aumentare prima la componente laterale `L-R`, senza alzare subito il bed mono:

```bash
SUR_VOL=0.92 \
  ./stereo251_upmix_psycho.sh eac3 no "film.mkv" 448k to51
```

Solo se l'ambienza resta insufficiente:

```bash
SUR_VOL=0.92 SUR_BED_VOL=0.08 \
  ./stereo251_upmix_psycho.sh eac3 no "film.mkv" 448k to51
```

Valori molto più alti di `SUR_BED_VOL` aumentano il rischio di udire dialoghi nei posteriori. In V10 il controllo adattivo continua ad attenuare il bed quando L/R sono correlati, anche aumentando questa variabile.

## I surround sono quasi muti su una sorgente mono

Su una traccia a due canali con contenuto identico è il comportamento previsto: la matrice `L-R` si annulla e, con `SUR_ADAPTIVE=1`, il piccolo bed viene attenuato di circa 9,1 dB rispetto alla modalità fissa. Una traccia realmente a un solo canale viene saltata. Per film o serie mono o molto stretti mantenere `to51`.

## Si sentono dialoghi nei posteriori

Verificare innanzitutto di usare `to51`, non `quad`. Per ridurre ulteriormente il rear bed:

```bash
SUR_BED_VOL=0.03 \
  ./stereo251_upmix_psycho.sh eac3 no "film.mkv" 448k to51
```

## Il QUAD è troppo presente dietro

```bash
QUAD_VOL=0.50 \
  ./stereo251_upmix_psycho.sh eac3 no "concerto.mkv" 448k quad
```

## Output già esistente

Gli script principali usano:

```text
[s/n/t]
```

- `s`: sovrascrive il singolo file;
- `n`: salta;
- `t`: sovrascrive tutti i successivi.

In sessione non interattiva, un output già esistente viene normalmente saltato.

---

# Cosa la suite non fa

- non crea Atmos reale da materiale non Atmos;
- non renderizza gli oggetti Atmos come un AVR;
- non sostituisce calibrazione, distanze, livelli e bass management dell'AVR;
- non ricostruisce informazioni assenti dalla sorgente;
- non garantisce lo stesso risultato su casse, stanza e volume differenti;
- non usa AI o DSP opachi;
- non elimina la necessità di un confronto A/B.

---

# Licenza

MIT License

---

# Autore

**Sandro (D@mocle77) Sabbioni**

> Per riportare ordine nella Forza Sonora serve solo uno script Bash. Questa è la via!

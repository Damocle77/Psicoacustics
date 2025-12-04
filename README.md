<p align="left">
  <img src="sonary_logo.png" width="600" alt="Sonary Suite Logo">
</p>

# 🎧 Sonary Suite – Yamaha V4A Edition  
DSP avanzato per tracce 5.1 con Surround **Clean** e **Sonar** Upfiring  
Testato ed ottimizzato su AVR **Yamaha RX‑V4A** in modalità *Straight*.

---

# ✅ Requisiti

### Software necessari
- **FFmpeg** 7+ con supporto SOXR  
- **Bash** 4.x+  
- **MKVToolNix** *(opzionale, per gestione tracce)*  

### Sistema operativo
- Linux / macOS  
- Windows tramite **WSL2** o Git‑Bash  

### Hardware di riferimento
- Yamaha **RX‑V4A**  
- Impianto **5.1** con surround simmetrici  
- Distanza ascolto 3–4 m  
- Stanza 4×5 m  

---

# 🚀 Installazione

## 1️⃣ Clona il repository
```
git clone https://github.com/Damocle77/Sonar_AC3D.git
```

## 2️⃣ Entra nella cartella
```
cd Sonar_AC3D
```

## 3️⃣ Rendi eseguibile lo script
```
chmod +x convert_sonary.sh
```

---

# ✨ EQ Voce

Profilo dedicato al canale Centrale (FC), pensato per aumentare intelligibilità senza stravolgere il timbro:

- +2.5 dB @ 1 kHz  
- +3.5 dB @ 2.5 kHz  
- +1.0 dB @ 6.3 kHz  

Estratto:

```
[FC]equalizer=f=1000:t=q:w=1.0:g=2.5,
     equalizer=f=2500:t=q:w=1.0:g=3.5,
     equalizer=f=6300:t=q:w=1.0:g=1.0[FCv];
```

---

# 🔊 Modalità Surround

## **1) Clean**
Effetto arioso, ampio ma non invasivo.

```
High-shelf 3.5 kHz
Delay 3 ms
Limiter 0.97
Boost lineare 1.26
```

Estratto:
```
[SL]adelay=3,highshelf=f=3500:g=0.8:t=q:w=0.8,volume=1.26,alimiter=limit=0.97[SL_out];
```

---

## **2) Sonar**
Effetto “upfiring virtuale” che simula altezza sonora e profondità laterale.

```
Split triplo (base / verticale / late)
34 ms + 78 ms delay
Presenza 6.5 kHz
HPF 1600 Hz
Mix 1 : 0.70 : 0.40
Limiter 0.99
```

Estratto:
```
[SL]asplit=3[SLm][SLv_in][SLlate_in];
[SLv_in]adelay=34,highpass=f=1600,equalizer=f=6500:t=q:w=1.2:g=3.5 ...
```

---

# 📐 Speaker Layout Consigliato

<p align="left">
  <img src="Sonar_Room_Layout.png" width="650" alt="Sonary Room Layout">
</p>

- Surround a 110–120°  
- Center a ~140 cm  
- Stanza ideale: 4×5 m  

---

# 🔁 Modalità Batch

Lo script può elaborare *tutti i video nella cartella* lasciando vuoto il parametro del file:

### Sonar su tutti i video
```
./convert_sonary.sh eac3 no "" 640k sonar
```

### Clean su tutti i video
```
./convert_sonary.sh ac3 no "" 448k clean
```

Lo script include automaticamente:  
`*.mkv *.mp4 *.m2ts`

---

# 🎥 Compatibilità AVR

- Progettato e testato su AVR **Yamaha V4A**  
- Massima resa in modalità **Straight**  
- Nessun conflitto con analizzatore YPAO  
- LFE invariato  

---

# 📄 Licenza
MIT License.

**Per riportare ordine nella Forza sonora serve solo uno script Bash...questa è la via!**

# 🎧 Sonary Suite – Yamaha V4A Edition  
DSP avanzato per tracce 5.1 con Surround **Clean** e **Sonar** Upfiring

La **Sonary Suite** è un sistema di elaborazione audio progettato per migliorare tracce 5.1 mantenendo il video originale intatto.  
Testato su AVR **Yamaha RX‑V4A** in modalità *Straight* e per stanze di dimensioni medio‑grandi.

> “Non tutti i supereroi indossano un mantello... a volte usano `filter_complex` per salvare il mondo del 5.1.”  
> ⚡by Sandro "D@mocle77" Sabbioni - Keeper of the Sonic Force ⚡

---

## ✨ Caratteristiche principali

### ✔ EQ Voce Sartoriale  
Applicata al canale centrale (FC). Migliora la chiarezza dei dialoghi senza stravolgere il timbro.

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

## 🔊 Modalità Surround

### **1) Clean**  
Surround più ariosi, chiari e definiti, senza enfatizzare verticalità o riflessioni (Widening).

- Ritardo 3 ms  
- High‑shelf a 3.5 kHz  
- Boost lineare 1.26  
- Limiter 0.97  

Estratto:

```
[SL]adelay=3,highshelf=f=3500:g=0.8:t=q:w=0.8,volume=1.26,alimiter=limit=0.97[SL_out];
```

---

### **2) Sonar**  
Tecnica di “upfiring virtuale” che crea percezione di altezza e profondità nei surround (Atmos).

- Split in 3 componenti (base, verticale, riflessione tarda)  
- Delay 34 ms e 78 ms  
- High‑pass 1600 Hz  
- Boost presenza +3.5 dB @ 6500 Hz  
- Mix 1 : 0.70 : 0.40  
- Limiter 0.99  

Estratto:

```
[SL]asplit=3[SLm][SLv_in][SLlate_in];
[SLv_in]adelay=34,highpass=f=1600,equalizer=f=6500:t=q:w=1.2:g=3.5 ...
[SLlate_in]adelay=78,lowpass=f=1500,volume=0.79[SLlate];
```

---

## 📐 Speaker Layout Consigliato (TEstato su Yamaha V4A)

Impostazione ottimale per ottenere il massimo da Clean e Sonar.

![Room Layout](Sonar_Room_Layout.png)

- Surround L/R a 110–120°  
- Distanze simmetriche 3.5–4 m  
- Center a 140 cm circa  
- Stanza 4×5 m → ideale per Sonar  

---

## 🛠 Esempi d'uso

### Sonar
```
./convert_sonary.sh eac3 no "film.mkv" 640k sonar
```

### Clean
```
./convert_sonary.sh ac3 si "" 448k clean
```

---

## 🎥 Compatibilità AVR

- Yamaha V4A in modalità **Straight** o AVR simile 
- Nessun conflitto con analizzatore YPAO  
- LFE invariato  
- Il crossover resta gestito dal sintoamplificatore  

---

## 📄 Licenza
MIT License.

---

## 🌀 Chiusura mistica  
**Per riportare ordine nella Forza sonora serve solo Bash... e questo script.  
Questa è la via!**

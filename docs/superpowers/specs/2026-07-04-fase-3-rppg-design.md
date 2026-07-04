# Fase 3 — rPPG condiviso (CHROM) — Design

**Goal (dal roadmap CLAUDE.md):** ROI dai landmark, algoritmo CHROM in isolate Dart, stima HR con indice di qualità del segnale. DoD: HR entro ~±10 bpm dal riferimento (smartwatch/pulsossimetro) in condizioni buone; qualità segnalata onestamente quando il segnale degrada (mai inventare valori — NFR3, NFR10).

## Contesto

Fase 2 ha consegnato `CameraSensingSource` (Android): stream camera → canale Pigeon throttled (~5fps) → MediaPipe Face/Pose Landmarker nativo → `VisualSampleAggregator` produce `SensingSample` con `facialTension`/`postureScore` reali e `hr: null, hrQuality: 0` (placeholder). La debug screen (`lib/features/debug/sensing_debug_screen.dart`) mostra già questi campi con nota "— (Fase 3)".

Fase 3 riempie `hr`/`hrQuality` con una stima reale, condivisa (stesso codice per Android/iOS, nessuna dipendenza nativa aggiuntiva) via CHROM, elaborato in un isolate Dart dedicato.

## 1. Data flow

```
CameraImage (ogni frame nativo, ~15-30fps)
  → _onFrame (già esistente in CameraSensingSource)
    → estrazione RGB media su ROI (inline, Dart, main isolate — costo O(pixel ROI), non full-frame)
       ROI (poligono normalizzato) aggiornata solo ai keyframe landmark (~5Hz, throttle Fase 2 esistente);
       riusata per i frame intermedi (il viso si muove poco tra un keyframe e l'altro)
  → RGB triplet + timestamp inviato a RppgIsolate (persistent, via SendPort)
    → buffer circolare ~10s
    → ogni hop (~1s): CHROM → HR bpm + quality
  → risultato rispedito al main isolate (ReceivePort)
  → merge in VisualSampleAggregator → SensingSample.hr / hrQuality
```

Nessun frame lascia mai il processo Dart (NFR1/NFR2 invariati — la RGB averaging avviene sugli stessi byte YUV già in mano a `CameraSensingSource` per il canale Pigeon esistente).

## 2. ROI extraction

Nuovo `lib/sensing/rppg/roi_extractor.dart`.

- Value object `YuvFrame` (plane bytes + stride, Dart puro): astrazione testabile equivalente al `FramePacket` nativo, ma lato Dart — costruibile da `CameraImage` o da byte array sintetici nei test.
- ROI = poligoni fronte + guancia sinistra + guancia destra, indici FaceMesh (478 punti) presi da pattern standard di letteratura rPPG, centralizzati in `RppgConfig` (stesso principio di `VisualMetricsConfig`: pesi/costanti in config, non hardcoded sparsi):
  - Fronte: `{10, 108, 151, 337}`
  - Guancia sinistra: `{205, 50, 118, 101}`
  - Guancia destra: `{425, 280, 347, 330}`
  - Questi indici sono un punto di partenza empirico: durante la validazione manuale (§5) si verifica visivamente che la ROI ricada sulla pelle (overlay poligono su debug screen) e si correggono se necessario — stesso approccio empirico già usato per le costanti di `postureScoreFromPose` in Fase 2.
- Solo i pixel dentro i poligoni vengono convertiti YUV→RGB e mediati (stessa formula di conversione già in `LandmarkAnalyzer.kt`, riscritta in Dart). Nessuna conversione full-frame per ogni frame: costo limitato al numero di pixel ROI.
- Landmark mancanti (nessun volto) → ROI resta quella dell'ultimo keyframe valido per un timeout breve, poi considerata stale → vedi §7.

## 3. CHROM processing

Nuovo `lib/sensing/rppg/chrom.dart` — puro, senza dipendenze da camera/isolate, unit-testabile con segnali RGB sintetici a frequenza nota.

Per finestra scorrevole (~10s, hop 1s, come da CLAUDE.md):

1. Detrend (rimozione drift/illuminazione — media mobile o linear detrend)
2. Normalizzazione per canale sulla media di finestra: `Rn=R/mean(R)`, idem G, B
3. `Xs = 3·Rn − 2·Gn`; `Ys = 1.5·Rn + Gn − 1.5·Bn`
4. `alpha = std(Xs)/std(Ys)`; `S = Xs − alpha·Ys`
5. Band-pass 0.7–3 Hz su `S`
6. FFT di `S`, picco in banda → `HR_bpm = peakFreq · 60`
7. **Quality** = potenza del picco / potenza totale in banda (purezza spettrale). Sotto soglia configurabile → segnale inaffidabile.

## 4. Isolate plumbing

`RppgProcessor`: isolate persistente (`Isolate.spawn`, non `compute()` per hop — evita lo spawn ogni secondo). Riceve stream di `(r, g, b, timestampMs)` via `SendPort`, mantiene un `RppgWindow` (classe pura: buffer + chiamate a `chrom.dart`), ogni hop calcola e rispedisce `{hrBpm, quality, timestampMs}` via `ReceivePort`.

Split identico a Fase 2 (`VisualSampleAggregator` puro vs `CameraSensingSource` plumbing): `RppgWindow` testabile senza isolate reale; il boilerplate di spawn/porte non è unit-testato, verificato a mano (come il `CameraController` in Fase 2).

## 5. Debug screen + validazione manuale

Estende `sensing_debug_screen.dart` esistente (niente schermata nuova): sostituisce il placeholder "— (Fase 3)" con HR bpm live + barra/etichetta qualità. Aggiunge overlay poligono ROI (fronte/guance) sopra la preview, riusando il `CustomPainter` esistente.

Task di validazione manuale (stesso schema del Task 6 di Fase 2): sessione reale con smartwatch o pulsossimetro come riferimento, buona luce, confronto HR ±10 bpm, esito registrato in `docs/decisions.md`.

## 6. Testing

- `chrom_test.dart`: segnali RGB sintetici sinusoidali a frequenza nota (es. 1.2 Hz → atteso ~72 bpm), rumore aggiunto per verificare degrado di quality.
- `roi_extractor_test.dart`: `YuvFrame` sintetico con regioni a colore noto → media RGB attesa.
- `rppg_window_test.dart`: aggregazione/hop timing, buffer circolare.
- Nessun test automatico sullo spawn dell'isolate (plumbing, verifica manuale).

## 7. Error handling / graceful degradation

- Nessun volto rilevato o ROI stale oltre timeout → quality forzata a 0, `hr` non mostrato come numero (mai fabbricare un valore — NFR3/NFR10).
- Luce scarsa / movimento → purezza spettrale bassa naturalmente → quality bassa → stesso percorso di degradazione onesta, nessun ramo speciale aggiuntivo.
- Il flusso sessione utente (simulatore) resta invariato: `CameraSensingSource`/rPPG restano raggiungibili solo dalla debug screen fino al Fase 4 (switch sim/reale).

## Fuori scope (rimandato)

- Switch sim/reale in UI utente → Fase 4.
- iOS → Fase 5 (stesso `chrom.dart`/`roi_extractor.dart` condivisi, nessuna modifica prevista qui).
- Test automatizzati di hardening estesi (rumore realistico, casi limite) → Fase 7 (qui solo i test minimi che guidano il TDD dell'implementazione).

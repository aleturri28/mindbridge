# Decisioni di progetto

## Fase 3 — Esito validazione manuale (Task 7) e gate di affidabilità

- **DoD raggiunto:** su device Android, buona luce, volto fermo, l'HR mostrato
  è entro ~±10 bpm dal riferimento (smartwatch/polso). Percorso che ci ha
  portati lì, in ordine: POS al posto di CHROM (accuratezza), risoluzione
  `low → medium` (SNR), e — decisivo — gate di affidabilità temporale.
- **Il gate non usa più la purezza spettrale come soglia primaria.** Quella
  metrica satura ~0.5 anche su un tono pulito (griglia di scan sovracampionata
  vs risoluzione di Rayleigh), quindi la soglia 0.35 scartava segnali reali
  validi (bpm corretto, quality 0.10–0.30). Ora l'HR è mostrato solo se ≥3
  stime recenti (entro 5s) concordano — almeno altrettante entro 8 bpm dalla
  loro mediana — e si mostra **la mediana** (robusta ai picchi occasionali).
  Rumore/movimento → stime sparpagliate → non affidabile → hr nascosto. È la
  degradazione onesta del DoD, e regge meglio del numero istantaneo di purezza.
- **`qualityThreshold` declassata a pavimento anti-rumore (0.12):** scarta solo
  le stime da rumore puro (~0.09) prima che entrino nello storico di consistenza.
- **Strumenti di diagnostica lasciati nella debug screen** (tile «rPPG grezzo»
  con bpm/quality non gated + contatori frame/stime): utili per future
  rivalidazioni, dentro l'eccezione NFR10 delle schermate di debug.

## Fase 3 (seguito) — Passaggio a POS come algoritmo attivo

- **POS (Wang et al. 2017) sostituisce CHROM nella pipeline attiva**
  (`RppgWindow` → `estimateHeartRatePos`). Motivo: nella validazione manuale
  su device (Task 7) CHROM produceva quality 0.10–0.25 e bpm instabile
  (±15 quando andava bene) — SNR del polso basso a `ResolutionPreset.low`.
  Il debugging sistematico ha escluso: ROI fuori pelle (overlay corretto),
  stallo pipeline (3434 frame → 130 stime), detrend mancante (CHROM cancella
  la deriva common-mode per costruzione — test di regressione aggiunto).
  POS è l'alternativa sanzionata da CLAUDE.md («CHROM, in alternativa POS»),
  più robusta al movimento.
- **CHROM resta nel codebase, testato**, come alternativa documentata: lo
  scan spettrale condiviso vive in `spectral.dart`, entrambi gli algoritmi
  lo riusano. Tornare a CHROM = una riga in `rppg_window.dart`.
- **Limite dichiarato che resta:** il rumore di quantizzazione da bassa
  risoluzione non si risolve cambiando algoritmo. Se POS non basta per il
  DoD ±10 bpm, prossima leva: `ResolutionPreset.low → medium` (4x pixel ROI)
  e/o finestra 10s → 15s, poi rivalidare. In ogni caso l'app degrada
  onestamente (hr null sotto soglia — NFR3), quindi un rPPG marginale non
  compromette il flusso utente.

## Fase 3 — rPPG condiviso (CHROM)

- **rPPG interamente in Dart puro condiviso** (`lib/sensing/rppg/`): nessun
  import da camera/Pigeon/piattaforma, così Android e il futuro port iOS
  (Fase 5) usano lo stesso `chrom.dart`/`roi_extractor.dart`/`rppg_window.dart`
  senza modifiche. La conversione YUV→RGB è riscritta in Dart (duplicata
  rispetto a `LandmarkAnalyzer.kt` di Fase 2) proprio per rispettare questo
  vincolo di condivisione.
- **Campionamento colore su OGNI frame camera (~15-30fps), non ai soli
  keyframe landmark (~5fps).** Serve per Nyquist su HR alti (>150bpm → >5Hz).
  La ROI (poligoni fronte/guance) è aggiornata solo ai keyframe landmark e
  riusata per i frame intermedi: costo limitato alla media RGB sui pixel ROI,
  nessuna inferenza MediaPipe extra.
- **CHROM con scan in frequenza discreto in banda 0.7–3Hz al posto di una
  FFT.** La restrizione di banda funge da band-pass ed evita una dipendenza
  di charting/FFT (principio CLAUDE.md: 50 righe di Dart prima di una lib).
  Qualità = purezza spettrale (potenza picco / potenza totale in banda).
- **Elaborazione in isolate persistente** (`Isolate.spawn` una volta, non
  `compute()` per hop): evita lo spawn ogni secondo. `RppgWindow` puro
  (buffer + hop) testabile senza isolate; il plumbing delle porte è verificato
  a mano.
- **Degradazione onesta a tre cancelli (NFR3/NFR10):** `hr` diventa null con
  `hrQuality` 0 quando (a) qualità < `RppgConfig.qualityThreshold`, (b) l'ultima
  stima è più vecchia di `RppgConfig.estimateStaleAfter` (5s), o (c) la cache
  dei landmark è stale (volto assente a lungo → niente estrazione). Mai un bpm
  fabbricato; i numeri grezzi compaiono solo nella debug screen.
- **Fixture sintetico con sfasamento per canale.** Una singola sinusoide in
  fase su R/G/B si annulla per costruzione sotto CHROM (Xs e Ys proporzionali,
  `combined ≈ 0`): i test devono sfasare i canali (fisicamente reale) perché la
  fondamentale sopravviva. La prima implementazione aveva mascherato il difetto
  allargando le tolleranze; corretto con tolleranze strette (72±5, 120±6).
- **Metrica di qualità: un tono pulito satura ~0.5, non ~1.0.** La griglia di
  scan (0.05Hz) è più fitta della risoluzione di Rayleigh della finestra 10s
  (0.1Hz), quindi la potenza del picco si distribuisce sui bin adiacenti.
  L'invariante che conta: pulito (~0.50) supera comodamente la soglia 0.35,
  rumore (<0.35) no. La soglia 0.35 è ciò che effettivamente gate l'HR.

### Validazione manuale (Task 7 — da eseguire su device fisico)

- Confronto HR stimato vs smartwatch/pulsossimetro indossato in simultanea,
  buona luce, telefono sul tavolo, volto fermo → target DoD ±10 bpm.
- L'overlay ROI sulla debug screen mostra la stessa regione che l'estrattore
  campiona (spazi di coordinate diversi ma coerenti, vedi commento
  `_RoiPainter`): usarlo per verificare che i poligoni cadano sulla pelle e,
  se necessario, correggere gli indici FaceMesh in `RppgConfig`.
- **Leva se ±10 bpm è difficile:** non c'è un detrend esplicito (lo scan in
  banda esclude già la deriva <0.7Hz); sotto deriva d'illuminazione lenta,
  aggiungere un detrend lineare/media mobile (spec §3 step 1) è il primo
  intervento.

## Fase 2 — Camera + MediaPipe landmark (Android)

- **Frames cross the Dart→Kotlin channel, never the reverse.** The camera
  plugin owns capture (per CLAUDE.md); MediaPipe runs natively. YUV planes
  are passed in-process to Kotlin and the channel returns only landmarks
  and blendshapes. No frame is stored, encoded or transmitted (NFR1/NFR2).
- **Models bundled in Android assets** (face_landmarker.task,
  pose_landmarker_lite.task): no runtime download keeps the app
  network-free (NFR1).
- **VIDEO running mode + serial background TaskQueue + ~5 fps throttling
  with frame dropping**: bounded battery/CPU cost; landmark cadence is far
  above what the classifier needs (1 Hz samples).
- **Missing signal falls back to rest values** (no face/pose → tension
  0.15, posture 0.9 targets via EMA): absence of signal must never push
  the classifier toward ALTO (NFR3, conservative-thresholds principle).
- **Session flow untouched**: `sensingSourceProvider` still returns the
  simulator; the camera pipeline is reachable only from the hidden debug
  screen. The sim/real switch lands in Fase 4 as planned.

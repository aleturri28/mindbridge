# MindBridge — CLAUDE.md

## Cos'è questo progetto

MindBridge è un'app mobile cross-platform (Android + iOS) che usa la fotocamera frontale come sensore passivo per stimare lo stress di uno studente durante le sessioni di studio e proporre micro-pause guidate (respirazione 4-7-8, stretching, musica). Nasce da un progetto HCI (Università di Trento) di cui esiste un report completo con requisiti, personas, design library e due iterazioni di prototipazione validate con heuristic evaluation e test SUS. Il prototipo Axure medium-fi (17 schermate) è la specifica UI di riferimento.

**Obiettivo di questa codebase:** trasformare il prototipo in un prodotto reale e dimostrabile, con sensing on-device funzionante nei limiti del realistico.

## Vincoli non negoziabili (dal report)

- **Privacy on-device (NFR1/NFR2):** nessun frame video né dato biometrico lascia il dispositivo. Nessuna chiamata di rete per il sensing. Si salvano solo dati aggregati (livelli di stress, timestamp, sessioni), mai video o immagini.
- **Etichette, mai numeri (NFR10):** durante la sessione l'utente vede solo Basso/Medio/Alto, mai valori numerici di stress o battito.
- **Discrezione (NFR4/FR3):** notifiche di default a vibrazione; nessun suono senza cuffie; modalità biblioteca (solo aptica) attivabile in 1 tap.
- **Frizione minima:** dalla notifica all'avvio pausa massimo 2 tap. La pausa è sempre proposta, mai imposta: Accetta / Posticipa 20 min / Ignora (FR4, NFR13).
- **Efficienza (NFR9):** notifica entro ~2 s dal riconoscimento di stress alto sostenuto; micro-pause ≤ 5 minuti.
- **Learnability (NFR8):** onboarding che spiega il rilevamento passivo e la privacy in linguaggio semplice; prima sessione avviabile entro 3 minuti.

## Limiti dichiarati (non provare a superarli in silenzio)

- La classificazione dello stress è una **stima euristica**, non una misura clinica. Il linguaggio in-app resta supportivo e ipotetico («Potresti beneficiare di una pausa»), mai diagnostico («Sei stressato»).
- Distinguere distress da eustress/flow non è risolvibile con questi segnali: mitighiamo con snooze/ignora facili e soglie conservative, non fingendo di saperlo fare.
- Il monitoraggio funziona **solo con app in foreground** su entrambe le piattaforme (su iOS la camera in background è vietata dal sistema). Scenario supportato: telefono sul tavolo, app aperta, schermo attivo con dimming (wakelock).
- rPPG è fragile con luce scarsa e movimento: serve gating della qualità del segnale e graceful degradation (NFR3) — se il segnale non è affidabile, l'app lo dice e degrada a soli segnali visivi (postura/espressione), senza inventare valori.

## Stack tecnico

- **Framework:** Flutter (Dart, ultima stable), target Android (minSdk 26) e iOS (15+). Android è la piattaforma di sviluppo primaria; iOS viene portato a parità in una fase dedicata.
- **UI:** Material 3 con tema custom dai design token (vedi sotto). Un solo codebase per tutte le schermate.
- **Camera:** plugin `camera` con `startImageStream` — fornisce frame grezzi (YUV420 su Android, BGRA su iOS) in Dart su entrambe le piattaforme, a risoluzione contenuta (`ResolutionPreset.low/medium`).
- **rPPG (condiviso, in Dart):** algoritmo CHROM (in alternativa POS) su ROI fronte/guance; media RGB per frame → detrend → band-pass 0,7–3 Hz → stima HR via FFT/peak detection su finestre scorrevoli (~10 s, hop 1 s). Elaborazione in un **isolate dedicato** per non bloccare la UI; passare a FFI/C solo se il profiling lo giustifica.
- **Landmark facciali e postura (nativo, due volte):** MediaPipe Tasks — Face Landmarker (con blendshapes per la tensione facciale, e per derivare le ROI dell'rPPG) e Pose Landmarker — integrati nativamente in Kotlin (Android) e Swift (iOS), esposti a Dart via platform channel / Pigeon. Il canale trasmette **solo landmark e metriche derivate**, mai frame.
- **Persistenza:** `drift` (SQLite) per sessioni, campioni aggregati di stress, pause e diario; `shared_preferences` per preferenze e baseline di calibrazione.
- **Sessione attiva:** `wakelock_plus` (schermo acceso con dimming); su Android `flutter_foreground_task` per la notifica persistente di sessione; notifiche locali con `flutter_local_notifications`, vibrazione via `HapticFeedback`/`vibration`.
- **Audio pause:** `just_audio` per musica rilassante e guida respirazione.
- **Grafici diario:** CustomPaint — niente librerie di charting pesanti.

## Architettura

```
lib/
  core/        → tema, design token, routing, util
  data/        → drift, repository, modelli (Session, StressSample, Pause, DiaryEntry)
  sensing/     → SensingSource (interfaccia) + SimulatedSensingSource + CameraSensingSource
                 + rppg/ (CHROM in isolate) + canale verso MediaPipe nativo
  classifier/  → baseline, fusione segnali, isteresi → StressLevel. Puro Dart, testabile
  features/    → onboarding, session, pause, diary, settings (UI + state)
android/ , ios/ → codice nativo MediaPipe (Kotlin / Swift), speculare
```

Interfaccia chiave (il cuore della strategia di sviluppo):

```dart
abstract class SensingSource {
  Stream<SensingSample> get signals;
  // SensingSample: hr?, hrQuality, breathingRate?, facialTension, postureScore, timestamp
}
// Implementazioni: SimulatedSensingSource (con controlli debug) e CameraSensingSource
```

Tutta l'app viene costruita contro `SensingSource`. Il simulatore resta per sempre selezionabile da un menu debug: serve per demo affidabili, screenshot e sviluppo UI senza camera.

`classifier/` riceve `SensingSample` e produce `StressLevel { basso, medio, alto }`:
- Baseline personale da calibrazione iniziale di ~60 s (FR8): media e deviazione di HR, tensione, postura a riposo.
- Score pesato delle deviazioni dalla baseline; pesi in un file di configurazione, non hardcoded sparsi.
- **Isteresi e persistenza:** ALTO scatta solo se lo score resta sopra soglia per ≥ 60 s continuativi; cooldown ≥ 15 min tra notifiche. Mai flapping.
- Duty cycle per la batteria: analisi a finestre (es. 15 s di sensing ogni 90 s), configurabile.

## Design tokens (dal medium-fi — rispettarli alla lettera)

- Primario `#4A90D9` · Successo/Basso `#2ECC71` · Accent/Medio `#F39C12` · Alert/Alto `#E74C3C` · Sfondo `#F8F9FA`
- Font: Roboto (UI), Roboto Mono (timer). Griglia 8 dp, card radius 12 dp, pill button 24 dp.
- Semaforo verde/arancio/rosso per lo stato di stress, sempre accompagnato dall'etichetta testuale (WCAG AA, mai solo colore).
- Gerarchia bottoni: un solo primario pieno per schermata; secondari outline blu; grigio riservato agli elementi non interattivi.
- Notifica stress come bottom sheet asimmetrico: «PAUSA GUIDATA» primario largo, «Posticipa 20 min» e «Ignora» outline stretti.
- Correzioni già note dalla heuristic evaluation da applicare subito: «Stop» sessione differenziato con Alert `#E74C3C`; card di scelta pausa con stato selezionato visibile (bordo/sfondo); schermata calibrazione che elenca esplicitamente i segnali rilevati e il perché.

## Schermate (riferimento medium-fi)

Onboarding (3 step + permessi camera con spiegazione privacy) · Home/avvio sessione · Calibrazione · Sessione in corso (donut colorato + etichetta, timer, Sospendi/Riprendi/Stop) · Bottom sheet notifica stress · Scelta pausa (3 card con icone) · Respirazione 4-7-8 (cerchio doppio animato espandi/contrai sincronizzato col countdown + barra avanzamento) · Stretching guidato · Musica · Pausa completata (header verde, «RIPRENDI LO STUDIO» primario) · Diario emotivo (barre colorate giorno/settimana, log sessioni con badge, insight testuali) · Impostazioni (notifica preferita, modalità biblioteca, toggle on-device bloccato con sottotitolo esplicativo, gestione dati).

## Roadmap a fasi — lavorare UNA fase alla volta

Ogni fase si chiude con: app che compila, funzionalità dimostrabile, commit. Non iniziare la fase successiva finché la corrente non è verificata a mano.

**Fase 0 — Scaffold.** Progetto Flutter, struttura cartelle come da architettura, tema Material 3 con i design token, routing vuoto, lint (`flutter_lints` strict). DoD: app vuota con tema corretto avviabile su Android e iOS/simulatore.

**Fase 1 — App completa con sensing simulato.** Tutte le schermate, flusso sessione end-to-end con `SimulatedSensingSource` (slider debug per forzare i livelli), drift, notifiche/vibrazione, diario funzionante, wakelock + foreground task Android. DoD: è il medium-fi reso funzionante su entrambe le piattaforme; demo completa possibile senza camera.

**Fase 2 — Pipeline camera + landmark (Android).** `camera` image stream → canale nativo → MediaPipe Face/Pose Landmarker in Kotlin; schermata debug nascosta con overlay dei landmark, FPS, valori grezzi. Nessun impatto sul flusso utente. DoD: segnali visivi (tensione, postura) reali e stabili sulla debug screen Android.

**Fase 3 — rPPG (condiviso).** ROI dai landmark, CHROM in isolate Dart, stima HR con indice di qualità del segnale; validazione manuale confrontando con smartwatch/pulsossimetro in buona luce. DoD: HR entro ~±10 bpm dal riferimento in condizioni buone; qualità segnalata onestamente quando degrada.

**Fase 4 — Classificatore reale.** Calibrazione FR8, fusione segnali, isteresi, cooldown; switch sim/reale nel menu debug. DoD: sessione reale di 30+ min su Android con notifiche sensate e nessun falso positivo raffica.

**Fase 5 — Port sensing iOS.** Implementazione speculare del canale MediaPipe in Swift; stessa interfaccia Pigeon, stessi output. rPPG e classificatore sono già condivisi e non si toccano. DoD: parità funzionale del sensing su iOS.

**Fase 6 — Rifinitura prodotto.** Duty cycle batteria misurato su entrambe le piattaforme, modalità biblioteca, insight settimanali (pattern per giorno/ora, confronto pausa accettata vs ignorata), gestione permessi negati, empty states. DoD: uso quotidiano credibile.

**Fase 7 — Hardening.** Unit test su `classifier/` e sull'rPPG (segnali sintetici noti → HR atteso), widget test sul flusso sessione, protocollo di validazione documentato in `docs/validation.md`.

## Convenzioni di lavoro

- Dart idiomatico, null-safety rigorosa; state management semplice e uniforme (Riverpod o ChangeNotifier — sceglierne uno in Fase 0 e non cambiarlo).
- Il codice nativo (Kotlin/Swift) fa il minimo indispensabile: camera già gestita da Flutter, MediaPipe, ritorno landmark. Tutta la logica sta in Dart.
- Commit piccoli e frequenti con messaggi in inglese convenzionali (`feat:`, `fix:`, `refactor:`).
- Ogni scelta che tocca i vincoli del report va motivata nel commit o in `docs/decisions.md`.
- Testi in-app in **italiano**, tono supportivo e non clinico; stringhe centralizzate (l10n/arb), mai hardcoded.
- Se un requisito del report è in conflitto con un limite tecnico, fermarsi e chiedere: non silenziare il requisito.
- Prima di aggiungere una dipendenza, chiedersi se 50 righe di Dart la sostituiscono.

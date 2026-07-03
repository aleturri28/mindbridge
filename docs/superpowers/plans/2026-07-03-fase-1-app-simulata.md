# Fase 1 — App completa con sensing simulato: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rendere funzionante il medium-fi completo (tutte le schermate, flusso sessione end-to-end) con `SimulatedSensingSource`, drift, notifiche/vibrazione, diario, wakelock + foreground task Android — demo completa possibile senza camera.

**Architecture:** Tutta l'app è costruita contro `SensingSource` (stream di `SensingSample`). Il `SessionController` (Riverpod) orchestra sensing → `StressClassifier` (puro Dart: baseline, score pesato, isteresi, cooldown) → stato UI + notifica bottom sheet. La persistenza (drift) registra sessioni/campioni/pause; il diario legge solo dati aggregati.

**Tech Stack:** Flutter stable, Riverpod (scelto in Fase 0), drift + sqlite3_flutter_libs, shared_preferences, flutter_local_notifications, wakelock_plus, flutter_foreground_task, just_audio, flutter_localizations/intl (arb, it-only), CustomPaint per i grafici.

## Global Constraints (dal CLAUDE.md — valgono per ogni task)

- Privacy on-device: nessuna chiamata di rete; si salvano solo aggregati (livelli, timestamp), mai frame/immagini.
- NFR10: in sessione solo etichette Basso/Medio/Alto, mai numeri di stress o HR (i numeri sono ammessi SOLO nella debug screen).
- NFR4/FR3: default vibrazione, nessun suono senza scelta esplicita; modalità biblioteca (solo aptica) in 1 tap dalle impostazioni.
- FR4/NFR13: pausa sempre proposta, mai imposta — bottom sheet con «PAUSA GUIDATA» (primario largo) / «Posticipa 20 min» / «Ignora» (outline stretti); max 2 tap da notifica ad avvio pausa.
- Isteresi: ALTO scatta solo se score sopra soglia per ≥ 60 s continuativi; cooldown ≥ 15 min tra notifiche; pesi/soglie in `classifier/classifier_config.dart`, non sparsi.
- Design token: solo `AppColors/AppSpacing/AppRadii/AppFonts/StressColors` — nessun valore hardcoded. Un solo FilledButton primario per schermata; «Stop» sessione con Alert `#E74C3C`; card scelta pausa con stato selezionato visibile; calibrazione elenca esplicitamente i segnali rilevati e il perché.
- Testi in-app in italiano, tono supportivo/ipotetico («Potresti beneficiare di una pausa»), centralizzati in `lib/l10n/app_it.arb` — mai hardcoded.
- Linguaggio mai diagnostico, mai clinico.
- Commit piccoli e frequenti, messaggi convenzionali in inglese.
- `flutter analyze` a zero issue a fine di ogni task.

**Nota esecuzione:** eseguito inline nella stessa sessione dall'autore del piano (contesto pieno). I test unitari formali sono in Fase 7 da CLAUDE.md; qui si testano comunque `classifier/` e sensing simulato (puro Dart, economico) + widget test del flusso base. Verifica manuale a fine fase.

---

### Task 1: Repo git + dipendenze + l10n scaffold

**Files:**
- Create: `.gitignore` (già generato da Flutter — verificare), `l10n.yaml`, `lib/l10n/app_it.arb`
- Modify: `pubspec.yaml`, `lib/app.dart`

**Interfaces:**
- Produces: `AppLocalizations` accessibile via `AppLocalizations.of(context)!` (getter `l10n` helper in `lib/core/util/l10n_ext.dart`: `extension L10nX on BuildContext { AppLocalizations get l10n => AppLocalizations.of(this)!; }`).

**Steps:**
- [ ] `git init` + commit baseline Fase 0 (`chore: phase 0 scaffold baseline`).
- [ ] `pubspec.yaml` dependencies: `drift`, `sqlite3_flutter_libs`, `path_provider`, `path`, `shared_preferences`, `flutter_local_notifications`, `wakelock_plus`, `flutter_foreground_task`, `just_audio`, `flutter_localizations (sdk)`, `intl`; dev: `drift_dev`, `build_runner`. `flutter: generate: true`.
- [ ] `l10n.yaml`: arb-dir `lib/l10n`, template `app_it.arb`, output-class `AppLocalizations`, `output-dir: lib/l10n/gen`, `synthetic-package: false` se richiesto dalla versione.
- [ ] `app_it.arb` con le stringhe iniziali (home, livelli stress, bottoni comuni); si estende nei task successivi.
- [ ] `lib/app.dart`: `localizationsDelegates: AppLocalizations.localizationsDelegates`, `supportedLocales: AppLocalizations.supportedLocales`, `locale: Locale('it')`, `onGenerateTitle`.
- [ ] `flutter pub get` + `flutter gen-l10n` + `flutter analyze` → 0 issue.
- [ ] Commit `feat: add phase 1 dependencies and italian l10n scaffold`.

### Task 2: Modelli dominio + SensingSource + SimulatedSensingSource

**Files:**
- Create: `lib/classifier/stress_level.dart`, `lib/sensing/sensing_sample.dart`, `lib/sensing/sensing_source.dart`, `lib/sensing/simulated_sensing_source.dart`
- Test: `test/sensing/simulated_sensing_source_test.dart`

**Interfaces (Produces):**
```dart
enum StressLevel { basso, medio, alto }

class SensingSample {
  final double? hr;              // bpm, null se non affidabile
  final double hrQuality;        // 0..1
  final double? breathingRate;   // atti/min, null in Fase 1
  final double facialTension;    // 0..1
  final double postureScore;     // 0..1 (1 = postura a riposo)
  final DateTime timestamp;
}

abstract class SensingSource {
  Stream<SensingSample> get signals;
  Future<void> start();
  Future<void> stop();
  void dispose();
}

/// Simulatore: livello target pilotabile da debug menu.
class SimulatedSensingSource implements SensingSource {
  /// 0..1: 0 = riposo, 1 = massimo stress simulato. Con rumore gaussiano.
  double targetStress;
  Duration samplePeriod; // default 1s
}
```

**Steps:**
- [ ] Test: con `targetStress = 0` i campioni restano vicini alla baseline (hr ~65±, tensione ~0.15±); con `targetStress = 1` hr ~95+, tensione ~0.8+; stream emette a periodo configurato (usare `fakeAsync` o periodo corto).
- [ ] Implementazione: timer periodico → campione = interpolazione riposo→stress + rumore (Random con seed opzionale per testabilità).
- [ ] `flutter test test/sensing` PASS, analyze 0.
- [ ] Commit `feat: add sensing domain model and simulated source`.

### Task 3: Classificatore (baseline, score pesato, isteresi, cooldown)

**Files:**
- Create: `lib/classifier/classifier_config.dart`, `lib/classifier/baseline.dart`, `lib/classifier/stress_classifier.dart`
- Test: `test/classifier/stress_classifier_test.dart`

**Interfaces (Produces):**
```dart
class ClassifierConfig {
  final double hrWeight;            // default 0.4
  final double tensionWeight;       // default 0.35
  final double postureWeight;       // default 0.25
  final double mediumThreshold;     // score z-like ≥ 1.0 → medio
  final double highThreshold;       // ≥ 2.0 → alto
  final Duration highPersistence;   // 60 s
  final Duration notificationCooldown; // 15 min
  const ClassifierConfig({...tutti con default...});
}

class Baseline {
  final double hrMean, hrStd, tensionMean, tensionStd, postureMean, postureStd;
  factory Baseline.fromSamples(List<SensingSample> samples); // media+std, std minima 1e-3
  Map<String, double> toJson(); factory Baseline.fromJson(...); // per shared_preferences
}

class ClassifierOutput {
  final StressLevel level;
  final bool shouldNotify; // true solo su transizione a alto sostenuto + fuori cooldown
}

class StressClassifier {
  StressClassifier({required Baseline baseline, ClassifierConfig config, DateTime Function() now});
  ClassifierOutput process(SensingSample sample);
  void notifySnoozed(Duration snooze);  // posticipa: niente notifiche per snooze
  void reset();
}
```
Score = somma pesata delle deviazioni positive normalizzate (z-score clampato ≥ 0; postura invertita: deviazione = (mean − value)/std). hrQuality < 0.5 → contributo hr escluso e pesi rinormalizzati (graceful degradation).

**Steps:**
- [ ] Test: (1) campioni a baseline → basso, mai notify; (2) score alto per 59 s → non alto; ≥ 60 s → alto + shouldNotify una sola volta; (3) seconda salita entro 15 min → no notify; dopo cooldown → notify; (4) flapping attorno a soglia → nessun flip-flop (persistenza); (5) hrQuality bassa → classifica solo con tensione+postura.
- [ ] Implementazione pura Dart, iniettando `now()` per i test.
- [ ] `flutter test test/classifier` PASS, analyze 0.
- [ ] Commit `feat: add stress classifier with hysteresis and cooldown`.

### Task 4: Persistenza drift + preferenze

**Files:**
- Create: `lib/data/db/database.dart` (tabelle + `AppDatabase`), `lib/data/repositories/session_repository.dart`, `lib/data/repositories/diary_repository.dart`, `lib/data/preferences.dart`
- Test: `test/data/database_test.dart` (drift `NativeDatabase.memory()`)

**Interfaces (Produces):**
```dart
// Tabelle drift:
// Sessions(id, startedAt, endedAt?, plannedMinutes?, avgStressScore?, notes?)
// StressSamples(id, sessionId FK, at, level int 0/1/2)          // solo aggregati
// Pauses(id, sessionId FK, at, kind int {breathing,stretch,music}, outcome int {accepted,snoozed,ignored}, completed bool)
// DiaryEntries(id, day date unique, mood int 1..5?, note?)
class SessionRepository {
  Future<int> startSession({DateTime? startedAt, int? plannedMinutes});
  Future<void> endSession(int id, {DateTime? endedAt});
  Future<void> addSample(int sessionId, StressLevel level, DateTime at);
  Future<void> addPause(int sessionId, PauseKind kind, PauseOutcome outcome, {bool completed});
  Stream<List<SessionWithStats>> watchRecentSessions({int limit});
}
class DiaryRepository {
  Stream<List<DayStress>> watchWeek(DateTime anyDayOfWeek); // distribuzione livelli per giorno
  Future<void> upsertEntry(DateTime day, {int? mood, String? note});
}
class Preferences { // shared_preferences wrapper
  bool onboardingDone; NotificationMode notificationMode; bool libraryMode;
  Baseline? baseline; bool useSimulatedSensing (default true);
}
```

**Steps:**
- [ ] Definire tabelle + repos; `dart run build_runner build --delete-conflicting-outputs`.
- [ ] Test in-memory: start/end sessione, addSample, watchWeek aggrega per giorno.
- [ ] PASS + analyze 0. Commit `feat: add drift persistence and preferences`.

### Task 5: Route + Home + Impostazioni + provider globali

**Files:**
- Modify: `lib/core/routing/app_router.dart` (tutte le route nominate: `/onboarding`, `/`, `/calibration`, `/session`, `/pause-choice`, `/pause/breathing`, `/pause/stretching`, `/pause/music`, `/pause/done`, `/diary`, `/settings`, `/debug`)
- Create: `lib/core/providers.dart` (db, repos, preferences, sensingSource switch sim/reale), `lib/features/home/home_screen.dart`, `lib/features/settings/settings_screen.dart`
- Modify: `lib/app.dart` (initialRoute da `onboardingDone`)

**Comportamento:**
- Home: saluto, card «Avvia sessione di studio» (primario → `/calibration` se manca baseline, altrimenti `/session`), accessi a Diario e Impostazioni, long-press sul logo → `/debug`.
- Impostazioni: notifica preferita (vibrazione default/suono/silenziosa), toggle modalità biblioteca (1 tap), toggle «Elaborazione solo sul dispositivo» **bloccato ON** con sottotitolo esplicativo, gestione dati (cancella tutto con conferma), rifai calibrazione.
- [ ] Analyze 0, widget test home aggiornato. Commit `feat: add app routes, home and settings screens`.

### Task 6: Onboarding (3 step + permessi/privacy)

**Files:** Create: `lib/features/onboarding/onboarding_screen.dart` (PageView 3 step + pagina permessi)
- Step: (1) cos'è MindBridge, (2) come funziona il rilevamento passivo (linguaggio semplice), (3) privacy on-device; pagina finale: spiegazione permesso camera (in Fase 1 nessuna richiesta reale — bottone «Ho capito, inizia»). Salva `onboardingDone`, naviga a Home.
- [ ] Commit `feat: add onboarding flow with privacy explanation`.

### Task 7: SessionController + calibrazione + servizi piattaforma

**Files:**
- Create: `lib/features/session/session_controller.dart`, `lib/features/session/calibration_screen.dart`, `lib/core/services/notification_service.dart`, `lib/core/services/session_foreground_service.dart`
- Modify: `android/app/src/main/AndroidManifest.xml` (permessi foreground service + notifiche), `lib/main.dart` (init notifiche/foreground task)

**Interfaces (Produces):**
```dart
class SessionState {
  final SessionPhase phase; // idle, calibrating, running, paused(sospesa), inBreak, finished
  final StressLevel level; final Duration elapsed; final bool stressAlert; // → bottom sheet
}
class SessionController extends Notifier<SessionState> {
  Future<void> startCalibration(); // ~60s, raccoglie campioni → Baseline → preferences (FR8)
  Future<void> startSession();     // wakelock on + dimming, foreground task (Android), drift startSession
  void suspend(); void resume(); Future<void> stopSession();
  void onPauseAccepted(); void onPauseSnoozed(); /* 20 min */ void onPauseIgnored();
  void onBreakCompleted(PauseKind kind);
}
```
- Notifica stress: entro ~2 s dal `shouldNotify` (NFR9) → vibrazione secondo `NotificationMode` (`HapticFeedback.heavyImpact` ripetuto; suono solo se modalità suono; niente in biblioteca oltre aptica) + local notification se in background + `stressAlert = true` → la UI mostra il bottom sheet.
- Calibrazione screen: elenca esplicitamente i segnali rilevati e il perché (heuristic eval), progress 60 s, al termine salva baseline e va a `/session`.
- [ ] Commit `feat: add session controller, calibration and platform services`.

### Task 8: Schermata Sessione in corso

**Files:** Create: `lib/features/session/session_screen.dart`, `lib/features/session/widgets/stress_donut.dart`
- Donut CustomPaint colorato dal livello (StressColors) + etichetta testuale centrale (mai numeri), timer `AppTheme.timerStyle`, bottoni Sospendi/Riprendi (outline) e Stop (pieno Alert `#E74C3C` — unico primario), indicatore modalità sensing (Simulato).
- Bottom sheet stress (asimmetrico, FR4): «PAUSA GUIDATA» FilledButton largo → `/pause-choice`; «Posticipa 20 min» e «Ignora» OutlinedButton stretti. Mostrato da listener su `stressAlert`.
- [ ] Widget test: bottom sheet appare quando lo stato segnala alert; 2 tap dalla notifica all'avvio pausa. Commit `feat: add live session screen with stress donut and alert sheet`.

### Task 9: Flusso pause (scelta, respirazione 4-7-8, stretching, musica, completata)

**Files:** Create: `lib/features/pause/pause_choice_screen.dart`, `breathing_screen.dart`, `stretching_screen.dart`, `music_screen.dart`, `pause_done_screen.dart`, `assets/audio/` (loop ambient generato offline)
- Scelta: 3 card con icone, stato selezionato visibile (bordo primario + sfondo tinto), «Inizia» primario. Pause ≤ 5 min.
- Respirazione: cerchio doppio animato espandi(4 s)/hold(7 s)/contrai(8 s) sincronizzato col countdown mono + barra avanzamento cicli.
- Stretching: sequenza guidata di esercizi con timer per step.
- Musica: just_audio su asset locale loop, timer 5 min, stop automatico.
- Completata: header verde `stressLow`, «RIPRENDI LO STUDIO» primario → torna a `/session` e `onBreakCompleted`.
- [ ] Commit `feat: add guided pause flows (breathing, stretching, music)`.

### Task 10: Diario emotivo

**Files:** Create: `lib/features/diary/diary_screen.dart`, `lib/features/diary/widgets/stress_bar_chart.dart` (CustomPaint)
- Barre colorate giorno/settimana (distribuzione basso/medio/alto per giorno, StressColors + etichette), log sessioni con badge livello prevalente e pause, insight testuali semplici («Questa settimana hai accettato N pause»).
- [ ] Commit `feat: add emotional diary with custom bar charts`.

### Task 11: Debug menu

**Files:** Create: `lib/features/debug/debug_screen.dart`
- Slider `targetStress` 0..1 sul `SimulatedSensingSource`, bottoni preset Basso/Medio/Alto, valori grezzi visibili (solo qui), switch sim/reale (reale disabilitato «Fase 2»), forza notifica.
- [ ] Commit `feat: add hidden debug menu with simulator controls`.

### Task 12: Verifica finale Fase 1

- [ ] `flutter analyze` 0 · `flutter test` PASS · build Android debug + iOS simulator.
- [ ] Run manuale su simulatore: onboarding → home → calibrazione → sessione → debug slider ad alto → entro ~60 s+2 s bottom sheet → pausa respirazione → completata → riprendi → stop → diario mostra la sessione.
- [ ] Commit finale `feat: phase 1 complete — full app on simulated sensing`.

## Self-Review

- Spec coverage: tutte le schermate del medium-fi coperte (T5–T11); FR4/FR8/NFR4/9/10/13 mappati in T3/T7/T8; drift T4; wakelock+foreground T7; l10n T1. Gap noti e voluti: permesso camera reale rinviato (nessuna camera in Fase 1), breathingRate null.
- Placeholder: nessun TBD; codice completo per i contratti, spec di comportamento per le UI (eseguite inline dall'autore).
- Tipi coerenti: `StressLevel`, `SensingSample`, `Baseline`, `ClassifierOutput`, `SessionState` definiti una volta (T2/T3/T7) e riusati.

# Decisioni di progetto

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

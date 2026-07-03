/// Tipo di micro-pausa proposta (FR4). Indici stabili per la persistenza.
enum PauseKind {
  breathing,
  stretching,
  music;

  int get storageIndex => index;

  static PauseKind fromStorageIndex(int value) => PauseKind.values[value];
}

/// Esito della proposta di pausa: sempre proposta, mai imposta (NFR13).
enum PauseOutcome {
  accepted,
  snoozed,
  ignored;

  int get storageIndex => index;

  static PauseOutcome fromStorageIndex(int value) =>
      PauseOutcome.values[value];
}

/// Livello di stress mostrato all'utente.
///
/// NFR10: in sessione l'utente vede SOLO queste etichette (Basso/Medio/Alto),
/// mai valori numerici di stress o battito.
enum StressLevel {
  basso,
  medio,
  alto;

  /// Indice stabile per la persistenza (drift salva un int).
  int get storageIndex => index;

  static StressLevel fromStorageIndex(int value) => StressLevel.values[value];
}

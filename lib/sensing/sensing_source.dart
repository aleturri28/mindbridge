import 'sensing_sample.dart';

/// Sorgente dei segnali di sensing. Tutta l'app è costruita contro questa
/// interfaccia: `SimulatedSensingSource` (Fase 1, per sempre selezionabile
/// dal menu debug) e `CameraSensingSource` (Fase 2+) sono intercambiabili.
abstract class SensingSource {
  /// Stream broadcast dei campioni; emette solo tra [start] e [stop].
  Stream<SensingSample> get signals;

  Future<void> start();

  Future<void> stop();

  void dispose();
}

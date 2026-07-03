import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/database.dart';
import '../data/preferences.dart';
import '../data/repositories/diary_repository.dart';
import '../data/repositories/session_repository.dart';
import '../sensing/sensing_source.dart';
import '../sensing/simulated_sensing_source.dart';

/// Preferenze caricate in main() prima di runApp e iniettate via override.
final Provider<Preferences> preferencesProvider = Provider<Preferences>(
  (Ref ref) => throw UnimplementedError(
    'preferencesProvider va sovrascritto in main()',
  ),
);

final Provider<AppDatabase> databaseProvider = Provider<AppDatabase>(
  (Ref ref) {
    final AppDatabase db = AppDatabase.open();
    ref.onDispose(db.close);
    return db;
  },
);

final Provider<SessionRepository> sessionRepositoryProvider =
    Provider<SessionRepository>(
  (Ref ref) => SessionRepository(ref.watch(databaseProvider)),
);

final Provider<DiaryRepository> diaryRepositoryProvider =
    Provider<DiaryRepository>(
  (Ref ref) => DiaryRepository(ref.watch(databaseProvider)),
);

/// Il simulatore è un singleton di app: il menu debug ne pilota
/// [SimulatedSensingSource.targetStress] mentre la sessione lo ascolta.
final Provider<SimulatedSensingSource> simulatedSensingProvider =
    Provider<SimulatedSensingSource>(
  (Ref ref) {
    final SimulatedSensingSource source = SimulatedSensingSource();
    ref.onDispose(source.dispose);
    return source;
  },
);

/// Sorgente attiva. Fase 1: sempre il simulatore. In Fase 2+ qui entrerà
/// lo switch sim/reale del menu debug (CameraSensingSource).
final Provider<SensingSource> sensingSourceProvider = Provider<SensingSource>(
  (Ref ref) => ref.watch(simulatedSensingProvider),
);

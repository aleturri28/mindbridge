import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// Sessioni di studio. Solo dati aggregati: mai video, immagini o
/// valori biometrici grezzi (NFR1/NFR2).
class Sessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get plannedMinutes => integer().nullable()();
}

/// Campioni aggregati di stress: solo il livello (0=basso 1=medio 2=alto).
class StressSamples extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer().references(Sessions, #id)();
  DateTimeColumn get at => dateTime()();
  IntColumn get level => integer()();
}

/// Pause proposte e loro esito (kind/outcome: indici degli enum in
/// pause_types.dart).
class Pauses extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer().references(Sessions, #id)();
  DateTimeColumn get at => dateTime()();
  IntColumn get kind => integer().nullable()();
  IntColumn get outcome => integer()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
}

/// Voci del diario emotivo (una per giorno).
class DiaryEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get day => dateTime().unique()();
  IntColumn get mood => integer().nullable()();
  TextColumn get note => text().nullable()();
}

@DriftDatabase(tables: [Sessions, StressSamples, Pauses, DiaryEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  AppDatabase.open() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  /// Cancella tutto (Impostazioni → «Cancella tutti i dati»).
  Future<void> deleteAllData() async {
    await transaction(() async {
      await delete(stressSamples).go();
      await delete(pauses).go();
      await delete(sessions).go();
      await delete(diaryEntries).go();
    });
  }

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final Directory dir = await getApplicationDocumentsDirectory();
      return NativeDatabase.createInBackground(
        File(p.join(dir.path, 'mindbridge.db')),
      );
    });
  }
}

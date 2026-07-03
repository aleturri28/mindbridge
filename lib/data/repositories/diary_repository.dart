import 'package:drift/drift.dart';

import '../../classifier/stress_level.dart';
import '../db/database.dart';
import '../pause_types.dart';

/// Distribuzione dei livelli di stress in un giorno (per le barre del diario).
class DayStress {
  const DayStress({
    required this.day,
    required this.lowCount,
    required this.mediumCount,
    required this.highCount,
  });

  final DateTime day;
  final int lowCount;
  final int mediumCount;
  final int highCount;

  int get total => lowCount + mediumCount + highCount;
}

/// Statistiche pause della settimana (per gli insight testuali).
class WeekPauseStats {
  const WeekPauseStats({required this.accepted, required this.proposed});

  final int accepted;
  final int proposed;
}

class DiaryRepository {
  DiaryRepository(this._db);

  final AppDatabase _db;

  /// Lunedì della settimana che contiene [anyDay] (a mezzanotte locale).
  static DateTime weekStart(DateTime anyDay) {
    final DateTime day = DateTime(anyDay.year, anyDay.month, anyDay.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  /// Distribuzione dei livelli per ciascuno dei 7 giorni della settimana
  /// di [anyDay]. Giorni senza sessioni → conteggi a zero.
  Stream<List<DayStress>> watchWeek(DateTime anyDay) {
    final DateTime start = weekStart(anyDay);
    final DateTime end = start.add(const Duration(days: 7));
    final Stream<List<StressSample>> samples = (_db.select(_db.stressSamples)
          ..where(($StressSamplesTable s) =>
              s.at.isBiggerOrEqualValue(start) & s.at.isSmallerThanValue(end)))
        .watch();
    return samples.map((List<StressSample> rows) {
      final Map<int, List<int>> byDay = <int, List<int>>{
        for (int i = 0; i < 7; i++) i: <int>[0, 0, 0],
      };
      for (final StressSample row in rows) {
        final int dayIndex = row.at.difference(start).inDays;
        if (dayIndex >= 0 && dayIndex < 7) {
          byDay[dayIndex]![row.level] += 1;
        }
      }
      return <DayStress>[
        for (int i = 0; i < 7; i++)
          DayStress(
            day: start.add(Duration(days: i)),
            lowCount: byDay[i]![StressLevel.basso.storageIndex],
            mediumCount: byDay[i]![StressLevel.medio.storageIndex],
            highCount: byDay[i]![StressLevel.alto.storageIndex],
          ),
      ];
    });
  }

  /// Pause accettate/proposte nella settimana di [anyDay].
  Stream<WeekPauseStats> watchWeekPauseStats(DateTime anyDay) {
    final DateTime start = weekStart(anyDay);
    final DateTime end = start.add(const Duration(days: 7));
    final Stream<List<Pause>> pauses = (_db.select(_db.pauses)
          ..where(($PausesTable p) =>
              p.at.isBiggerOrEqualValue(start) & p.at.isSmallerThanValue(end)))
        .watch();
    return pauses.map(
      (List<Pause> rows) => WeekPauseStats(
        accepted: rows
            .where(
                (Pause p) => p.outcome == PauseOutcome.accepted.storageIndex)
            .length,
        proposed: rows.length,
      ),
    );
  }

  Future<void> upsertEntry(DateTime day, {int? mood, String? note}) async {
    final DateTime normalized = DateTime(day.year, day.month, day.day);
    await _db.into(_db.diaryEntries).insertOnConflictUpdate(
          DiaryEntriesCompanion.insert(
            day: normalized,
            mood: Value<int?>(mood),
            note: Value<String?>(note),
          ),
        );
  }
}

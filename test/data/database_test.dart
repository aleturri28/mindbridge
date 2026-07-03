import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindbridge/classifier/stress_level.dart';
import 'package:mindbridge/data/db/database.dart';
import 'package:mindbridge/data/pause_types.dart';
import 'package:mindbridge/data/repositories/diary_repository.dart';
import 'package:mindbridge/data/repositories/session_repository.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessions;
  late DiaryRepository diary;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sessions = SessionRepository(db);
    diary = DiaryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('ciclo sessione: start, campioni, pausa, end, statistiche', () async {
    final DateTime start = DateTime(2026, 7, 1, 10);
    final int id = await sessions.startSession(startedAt: start);
    await sessions.addSample(id, StressLevel.basso, start);
    await sessions.addSample(
        id, StressLevel.alto, start.add(const Duration(minutes: 5)));
    await sessions.addSample(
        id, StressLevel.alto, start.add(const Duration(minutes: 6)));
    await sessions.addPause(
      id,
      PauseOutcome.accepted,
      kind: PauseKind.breathing,
      completed: true,
      at: start.add(const Duration(minutes: 7)),
    );
    await sessions.endSession(id,
        endedAt: start.add(const Duration(minutes: 30)));

    final List<SessionWithStats> recent =
        await sessions.watchRecentSessions().first;
    expect(recent, hasLength(1));
    final SessionWithStats stats = recent.single;
    expect(stats.duration, const Duration(minutes: 30));
    expect(stats.levelCounts[StressLevel.alto], 2);
    expect(stats.dominantLevel, StressLevel.alto);
    expect(stats.pausesAccepted, 1);
    expect(stats.pausesProposed, 1);
  });

  test('sessioni non concluse escluse dal log', () async {
    await sessions.startSession(startedAt: DateTime(2026, 7, 1, 10));
    final List<SessionWithStats> recent =
        await sessions.watchRecentSessions().first;
    expect(recent, isEmpty);
  });

  test('watchWeek aggrega i campioni per giorno', () async {
    // Mercoledì 1 luglio 2026 → settimana lun 29/6 – dom 5/7.
    final DateTime wednesday = DateTime(2026, 7, 1, 15);
    final int id = await sessions.startSession(startedAt: wednesday);
    await sessions.addSample(id, StressLevel.basso, wednesday);
    await sessions.addSample(
        id, StressLevel.medio, wednesday.add(const Duration(minutes: 1)));
    await sessions.addSample(id, StressLevel.alto,
        wednesday.add(const Duration(days: 1))); // giovedì

    final List<DayStress> week = await diary.watchWeek(wednesday).first;
    expect(week, hasLength(7));
    expect(week.first.day, DateTime(2026, 6, 29)); // lunedì
    final DayStress wed = week[2];
    expect(wed.lowCount, 1);
    expect(wed.mediumCount, 1);
    expect(wed.highCount, 0);
    expect(week[3].highCount, 1);
    expect(week[6].total, 0);
  });

  test('statistiche pause settimanali per gli insight', () async {
    final DateTime day = DateTime(2026, 7, 1, 10);
    final int id = await sessions.startSession(startedAt: day);
    await sessions.addPause(id, PauseOutcome.accepted,
        kind: PauseKind.music, at: day);
    await sessions.addPause(id, PauseOutcome.ignored, at: day);
    await sessions.addPause(id, PauseOutcome.snoozed, at: day);

    final WeekPauseStats stats = await diary.watchWeekPauseStats(day).first;
    expect(stats.accepted, 1);
    expect(stats.proposed, 3);
  });

  test('deleteAllData svuota tutte le tabelle', () async {
    final int id = await sessions.startSession(startedAt: DateTime(2026, 7, 1));
    await sessions.addSample(id, StressLevel.basso, DateTime(2026, 7, 1));
    await sessions.endSession(id);
    await db.deleteAllData();
    expect(await sessions.watchRecentSessions().first, isEmpty);
  });
}

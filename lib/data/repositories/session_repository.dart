import 'package:drift/drift.dart';

import '../../classifier/stress_level.dart';
import '../db/database.dart';
import '../pause_types.dart';

/// Sessione con statistiche aggregate per il diario.
class SessionWithStats {
  const SessionWithStats({
    required this.session,
    required this.levelCounts,
    required this.pausesAccepted,
    required this.pausesProposed,
  });

  final Session session;

  /// Numero di campioni per livello (chiave: StressLevel).
  final Map<StressLevel, int> levelCounts;
  final int pausesAccepted;
  final int pausesProposed;

  Duration get duration => (session.endedAt ?? session.startedAt)
      .difference(session.startedAt);

  /// Livello prevalente della sessione (badge nel diario).
  StressLevel get dominantLevel {
    StressLevel best = StressLevel.basso;
    int bestCount = -1;
    for (final StressLevel level in StressLevel.values) {
      final int count = levelCounts[level] ?? 0;
      if (count > bestCount) {
        best = level;
        bestCount = count;
      }
    }
    return best;
  }
}

class SessionRepository {
  SessionRepository(this._db);

  final AppDatabase _db;

  Future<int> startSession({DateTime? startedAt, int? plannedMinutes}) {
    return _db.into(_db.sessions).insert(
          SessionsCompanion.insert(
            startedAt: startedAt ?? DateTime.now(),
            plannedMinutes: Value<int?>(plannedMinutes),
          ),
        );
  }

  Future<void> endSession(int id, {DateTime? endedAt}) async {
    await (_db.update(_db.sessions)..where(($SessionsTable s) => s.id.equals(id)))
        .write(SessionsCompanion(
      endedAt: Value<DateTime?>(endedAt ?? DateTime.now()),
    ));
  }

  Future<void> addSample(int sessionId, StressLevel level, DateTime at) async {
    await _db.into(_db.stressSamples).insert(
          StressSamplesCompanion.insert(
            sessionId: sessionId,
            at: at,
            level: level.storageIndex,
          ),
        );
  }

  Future<void> addPause(
    int sessionId,
    PauseOutcome outcome, {
    PauseKind? kind,
    bool completed = false,
    DateTime? at,
  }) async {
    await _db.into(_db.pauses).insert(
          PausesCompanion.insert(
            sessionId: sessionId,
            at: at ?? DateTime.now(),
            kind: Value<int?>(kind?.storageIndex),
            outcome: outcome.storageIndex,
            completed: Value<bool>(completed),
          ),
        );
  }

  /// Sessioni concluse più recenti, con statistiche, per il log del diario.
  Stream<List<SessionWithStats>> watchRecentSessions({int limit = 20}) {
    final Stream<List<Session>> sessions = (_db.select(_db.sessions)
          ..where(($SessionsTable s) => s.endedAt.isNotNull())
          ..orderBy(<OrderClauseGenerator<$SessionsTable>>[
            ($SessionsTable s) =>
                OrderingTerm(expression: s.startedAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .watch();
    return sessions.asyncMap(_withStats);
  }

  Future<List<SessionWithStats>> _withStats(List<Session> sessions) async {
    final List<SessionWithStats> result = <SessionWithStats>[];
    for (final Session session in sessions) {
      final List<StressSample> samples = await (_db.select(_db.stressSamples)
            ..where(($StressSamplesTable s) => s.sessionId.equals(session.id)))
          .get();
      final List<Pause> pauses = await (_db.select(_db.pauses)
            ..where(($PausesTable p) => p.sessionId.equals(session.id)))
          .get();
      final Map<StressLevel, int> counts = <StressLevel, int>{};
      for (final StressSample sample in samples) {
        final StressLevel level = StressLevel.fromStorageIndex(sample.level);
        counts[level] = (counts[level] ?? 0) + 1;
      }
      result.add(
        SessionWithStats(
          session: session,
          levelCounts: counts,
          pausesAccepted: pauses
              .where((Pause p) =>
                  p.outcome == PauseOutcome.accepted.storageIndex)
              .length,
          pausesProposed: pauses.length,
        ),
      );
    }
    return result;
  }
}

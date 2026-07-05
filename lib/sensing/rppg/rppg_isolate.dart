import 'dart:async';
import 'dart:isolate';

import 'rppg_window.dart';

export 'rppg_window.dart' show RppgEstimate;

const String _closeSignal = '__rppg_close__';

void _entryPoint(SendPort mainSendPort) {
  final ReceivePort isolateReceive = ReceivePort();
  mainSendPort.send(isolateReceive.sendPort);
  final RppgWindow window = RppgWindow();

  isolateReceive.listen((dynamic message) {
    if (message is (double, double, double, int)) {
      final (double r, double g, double b, int timestampMs) = message;
      window.add(r, g, b, timestampMs);
      final RppgEstimate? estimate = window.maybeEstimate(timestampMs);
      if (estimate != null) {
        mainSendPort.send(estimate);
      }
    } else if (message == _closeSignal) {
      isolateReceive.close();
      Isolate.exit();
    }
  });
}

/// Wrapper isolate persistente attorno a [RppgWindow]: riceve triplette RGB
/// dal main isolate, mantiene la finestra scorrevole ed emette stime HR.
/// Isolate persistente (non `compute()` per hop) per evitare lo spawn ogni
/// secondo — CLAUDE.md: elaborazione rPPG in isolate dedicato.
class RppgProcessor {
  RppgProcessor._(
    this._isolate,
    this._toIsolate,
    this._fromIsolate,
    this._subscription,
    this._estimates,
  );

  final Isolate _isolate;
  final SendPort _toIsolate;
  final ReceivePort _fromIsolate;
  final StreamSubscription<dynamic> _subscription;
  final StreamController<RppgEstimate> _estimates;

  Stream<RppgEstimate> get estimates => _estimates.stream;

  static Future<RppgProcessor> spawn() async {
    final ReceivePort fromIsolate = ReceivePort();
    final Completer<SendPort> toIsolateCompleter = Completer<SendPort>();
    final StreamController<RppgEstimate> estimates =
        StreamController<RppgEstimate>.broadcast();

    late final StreamSubscription<dynamic> subscription;
    subscription = fromIsolate.listen((dynamic message) {
      if (message is SendPort && !toIsolateCompleter.isCompleted) {
        toIsolateCompleter.complete(message);
      } else if (message is RppgEstimate && !estimates.isClosed) {
        estimates.add(message);
      }
    });

    try {
      final Isolate isolate =
          await Isolate.spawn(_entryPoint, fromIsolate.sendPort);
      final SendPort toIsolate = await toIsolateCompleter.future;

      return RppgProcessor._(isolate, toIsolate, fromIsolate, subscription, estimates);
    } catch (e) {
      await subscription.cancel();
      fromIsolate.close();
      await estimates.close();
      rethrow;
    }
  }

  void addFrame({
    required double r,
    required double g,
    required double b,
    required int timestampMs,
  }) {
    _toIsolate.send((r, g, b, timestampMs));
  }

  Future<void> dispose() async {
    _toIsolate.send(_closeSignal);
    await _subscription.cancel();
    _fromIsolate.close();
    _isolate.kill(priority: Isolate.immediate);
    await _estimates.close();
  }
}

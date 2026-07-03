import 'package:flutter_test/flutter_test.dart';
import 'package:mindbridge/classifier/baseline.dart';
import 'package:mindbridge/classifier/stress_classifier.dart';
import 'package:mindbridge/classifier/stress_level.dart';
import 'package:mindbridge/sensing/sensing_sample.dart';

const Baseline baseline = Baseline(
  hrMean: 65,
  hrStd: 3,
  tensionMean: 0.15,
  tensionStd: 0.05,
  postureMean: 0.9,
  postureStd: 0.05,
);

final DateTime t0 = DateTime(2026, 7, 3, 10);

SensingSample sample(
  int seconds, {
  double? hr = 65,
  double quality = 0.9,
  double tension = 0.15,
  double posture = 0.9,
}) {
  return SensingSample(
    hr: hr,
    hrQuality: quality,
    facialTension: tension,
    postureScore: posture,
    timestamp: t0.add(Duration(seconds: seconds)),
  );
}

SensingSample rest(int seconds) => sample(seconds);

SensingSample stressed(int seconds, {double? hr = 100, double quality = 0.9}) =>
    sample(seconds, hr: hr, quality: quality, tension: 0.7, posture: 0.5);

void main() {
  test('a baseline resta basso e non notifica mai', () {
    final StressClassifier classifier = StressClassifier(baseline: baseline);
    for (int s = 0; s < 300; s++) {
      final ClassifierOutput out = classifier.process(rest(s));
      expect(out.level, StressLevel.basso);
      expect(out.shouldNotify, isFalse);
    }
  });

  test('alto solo dopo 60 s sostenuti, con una sola notifica', () {
    final StressClassifier classifier = StressClassifier(baseline: baseline);
    int notifications = 0;
    for (int s = 0; s < 59; s++) {
      final ClassifierOutput out = classifier.process(stressed(s));
      expect(out.level, isNot(StressLevel.alto),
          reason: 'a $s s non è ancora sostenuto');
      if (out.shouldNotify) {
        notifications++;
      }
    }
    for (int s = 59; s < 120; s++) {
      final ClassifierOutput out = classifier.process(stressed(s));
      if (s >= 60) {
        expect(out.level, StressLevel.alto);
      }
      if (out.shouldNotify) {
        notifications++;
      }
    }
    expect(notifications, 1);
  });

  test('cooldown 15 min: secondo episodio ravvicinato non notifica', () {
    final StressClassifier classifier = StressClassifier(baseline: baseline);
    int notifications = 0;
    void run(int from, int to, SensingSample Function(int) make) {
      for (int s = from; s < to; s++) {
        if (classifier.process(make(s)).shouldNotify) {
          notifications++;
        }
      }
    }

    run(0, 90, stressed); // primo episodio → 1 notifica
    run(90, 210, rest); // rientro
    run(210, 400, stressed); // secondo episodio, entro 15 min → 0
    expect(notifications, 1);

    run(400, 700, rest);
    run(700, 1000, stressed); // oltre 15 min dalla prima → 1
    expect(notifications, 2);
  });

  test('snooze posticipa la notifica', () {
    final StressClassifier classifier = StressClassifier(baseline: baseline);
    int notifications = 0;
    for (int s = 0; s < 90; s++) {
      if (classifier.process(stressed(s)).shouldNotify) {
        notifications++;
      }
    }
    expect(notifications, 1);

    classifier.notifySnoozed(const Duration(minutes: 20));
    // Resta alto ben oltre il cooldown: lo snooze deve comunque tacere.
    for (int s = 90; s < 1100; s++) {
      if (classifier.process(stressed(s)).shouldNotify) {
        notifications++;
      }
    }
    expect(notifications, 1);
    // Dopo lo snooze (20 min dal momento dello snooze) può rinotificare.
    for (int s = 1100; s < 1400; s++) {
      if (classifier.process(stressed(s)).shouldNotify) {
        notifications++;
      }
    }
    expect(notifications, 2);
  });

  test('burst sotto i 60 s non producono mai alto (persistenza)', () {
    final StressClassifier classifier = StressClassifier(baseline: baseline);
    // Raffiche di 30 s di stress alternate a 30 s di riposo: lo score
    // supera la soglia ma mai per 60 s continuativi.
    for (int s = 0; s < 600; s++) {
      final bool inBurst = (s ~/ 30).isEven;
      final ClassifierOutput out =
          classifier.process(inBurst ? stressed(s) : rest(s));
      expect(out.level, isNot(StressLevel.alto), reason: 'a $s s');
      expect(out.shouldNotify, isFalse);
    }
  });

  test('qualità hr bassa: classifica comunque con tensione e postura', () {
    final StressClassifier classifier = StressClassifier(baseline: baseline);
    ClassifierOutput? last;
    for (int s = 0; s < 120; s++) {
      last = classifier.process(stressed(s, hr: null, quality: 0.2));
    }
    expect(last!.level, StressLevel.alto);
  });

  test('baseline da campioni: media e std plausibili', () {
    final List<SensingSample> samples =
        List<SensingSample>.generate(60, rest);
    final Baseline b = Baseline.fromSamples(samples);
    expect(b.hrMean, closeTo(65, 0.01));
    expect(b.tensionMean, closeTo(0.15, 0.01));
    expect(b.postureMean, closeTo(0.9, 0.01));
    expect(b.hasHr, isTrue);
    // Round-trip json (per shared_preferences).
    final Baseline restored = Baseline.fromJson(b.toJson());
    expect(restored.hrMean, b.hrMean);
    expect(restored.postureStd, b.postureStd);
  });
}

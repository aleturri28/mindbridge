import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindbridge/sensing/sensing_sample.dart';
import 'package:mindbridge/sensing/simulated_sensing_source.dart';

Future<List<SensingSample>> collect(
  SimulatedSensingSource source,
  int count,
) async {
  final Future<List<SensingSample>> samples =
      source.signals.take(count).toList();
  await source.start();
  final List<SensingSample> result = await samples;
  await source.stop();
  return result;
}

void main() {
  test('a riposo emette campioni vicini al profilo baseline', () async {
    final SimulatedSensingSource source = SimulatedSensingSource(
      samplePeriod: const Duration(milliseconds: 5),
      random: Random(42),
    );
    final List<SensingSample> samples = await collect(source, 20);
    source.dispose();

    for (final SensingSample s in samples) {
      expect(s.hr, isNotNull);
      expect(s.hr, closeTo(65, 5));
      expect(s.facialTension, closeTo(0.15, 0.1));
      expect(s.postureScore, closeTo(0.9, 0.1));
      expect(s.hrQuality, greaterThan(0.5));
    }
  });

  test('a stress massimo emette campioni del profilo stress', () async {
    final SimulatedSensingSource source = SimulatedSensingSource(
      samplePeriod: const Duration(milliseconds: 5),
      random: Random(42),
    )..targetStress = 1;
    final List<SensingSample> samples = await collect(source, 20);
    source.dispose();

    for (final SensingSample s in samples) {
      expect(s.hr, closeTo(100, 5));
      expect(s.facialTension, closeTo(0.8, 0.1));
      expect(s.postureScore, closeTo(0.45, 0.1));
    }
  });

  test('con qualità simulata bassa hr è null (mai valori inventati)',
      () async {
    final SimulatedSensingSource source = SimulatedSensingSource(
      samplePeriod: const Duration(milliseconds: 5),
      random: Random(42),
    )..simulatedHrQuality = 0.2;
    final List<SensingSample> samples = await collect(source, 10);
    source.dispose();

    for (final SensingSample s in samples) {
      expect(s.hr, isNull);
      expect(s.hrQuality, lessThan(0.5));
    }
  });

  test('stop interrompe le emissioni', () async {
    final SimulatedSensingSource source = SimulatedSensingSource(
      samplePeriod: const Duration(milliseconds: 5),
    );
    int count = 0;
    source.signals.listen((_) => count++);
    await source.start();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await source.stop();
    final int atStop = count;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(count, atStop);
    source.dispose();
  });
}

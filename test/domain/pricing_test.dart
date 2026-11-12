import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kona_share/domain/pricing.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  tz.initializeTimeZones();
  final cases =
      jsonDecode(File('test/pricing_cases.json').readAsStringSync()) as List;
  for (final c in cases) {
    test(c['name'], () {
      final fare = KonaPricing.calculate(
        start: DateTime.parse(c['start']),
        end: DateTime.parse(c['end']),
        km: c['km'],
      );
      expect(fare.totalCents, c['cents']);
      expect(fare.dailyDays, c['days']);
    });
  }
  test('rejects reversed time and negative distance', () {
    final start = DateTime.utc(2026, 11, 12);
    expect(
      () => KonaPricing.calculate(start: start, end: start, km: -1),
      throwsArgumentError,
    );
    expect(
      () => KonaPricing.calculate(
        start: start,
        end: start.subtract(const Duration(minutes: 1)),
        km: 5,
      ),
      throwsArgumentError,
    );
  });
}

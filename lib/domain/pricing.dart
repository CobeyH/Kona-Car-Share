import 'dart:math';

import 'package:timezone/timezone.dart' as tz;

class Fare {
  const Fare({
    required this.totalCents,
    required this.timeCents,
    required this.distanceCents,
    required this.dailyDays,
    required this.includedKm,
    required this.minimumCents,
    required this.elapsed,
    required this.calendarDays,
  });
  final int totalCents, timeCents, distanceCents, dailyDays;
  final int includedKm, minimumCents, calendarDays;
  final Duration elapsed;
  int get dailyCents => dailyDays * 8000;
  Map<String, dynamic> toJson() => {
    'totalCents': totalCents,
    'timeCents': timeCents,
    'distanceCents': distanceCents,
    'dailyCents': dailyCents,
    'dailyDays': dailyDays,
    'includedKm': includedKm,
    'minimumCents': minimumCents,
    'minutes': elapsed.inMilliseconds / 60000,
    'calendarDays': calendarDays,
  };
}

class KonaPricing {
  static Fare calculate({
    required DateTime start,
    required DateTime end,
    required int km,
    String zone = 'America/Vancouver',
  }) {
    if (end.isBefore(start) ||
        end.difference(start) > const Duration(days: 31) ||
        km < 0 ||
        km > 100000) {
      throw ArgumentError('Use valid times (up to 31 days) and kilometres.');
    }
    final location = tz.getLocation(zone);
    final stop = tz.TZDateTime.from(end, location);
    var cursor = tz.TZDateTime.from(start, location);
    final dayMicros = <int>[];
    // End is exclusive. Midnight belongs to the day that follows it.
    while (cursor.isBefore(stop)) {
      final midnight = tz.TZDateTime(
        location,
        cursor.year,
        cursor.month,
        cursor.day + 1,
      );
      final boundary = midnight.isBefore(stop) ? midnight : stop;
      dayMicros.add(boundary.difference(cursor).inMicroseconds);
      cursor = boundary;
    }
    if (dayMicros.isEmpty) dayMicros.add(0);
    dayMicros.sort((a, b) => b.compareTo(a));
    var remainingMicros = end.difference(start).inMicroseconds;
    Fare? best;
    // Pool 250 km for every daily-rate day. For k daily-rate days, assigning
    // the k longest days to that rate minimizes the remaining hourly cost.
    for (var days = 0; days <= dayMicros.length; days++) {
      if (days > 0) remainingMicros -= dayMicros[days - 1];
      final time = (remainingMicros * 500 / Duration.microsecondsPerHour)
          .round();
      final distance = max(0, km - days * 250) * 28;
      final subtotal = 100 + days * 8000 + time + distance;
      final minimum = max(0, 600 - subtotal);
      final candidate = Fare(
        totalCents: subtotal + minimum,
        timeCents: time,
        distanceCents: distance,
        dailyDays: days,
        includedKm: days * 250,
        minimumCents: minimum,
        elapsed: end.difference(start),
        calendarDays: dayMicros.length,
      );
      if (best == null || candidate.totalCents < best.totalCents) {
        best = candidate;
      }
    }
    return best!;
  }
}

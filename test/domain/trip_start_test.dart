import 'package:flutter_test/flutter_test.dart';
import 'package:kona_share/data/demo_repository.dart';
import 'package:kona_share/domain/trip_start.dart';
import 'package:kona_share/ui/app.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  setUpAll(tz.initializeTimeZones);
  final start = DateTime.utc(2026, 11, 16, 12),
      end = DateTime.utc(2026, 11, 16, 14);
  test(
    'start window includes exactly one hour early and excludes the booked end',
    () {
      bool allowed(DateTime at) =>
          canStartTrip(bookedStart: start, bookedEnd: end, now: at);
      expect(allowed(start.subtract(const Duration(hours: 1))), isTrue);
      expect(
        allowed(start.subtract(const Duration(hours: 1, microseconds: 1))),
        isFalse,
      );
      expect(allowed(start.subtract(const Duration(minutes: 30))), isTrue);
      expect(allowed(start), isTrue);
      expect(allowed(end.subtract(const Duration(microseconds: 1))), isTrue);
      expect(allowed(end), isFalse);
      expect(allowed(end.add(const Duration(minutes: 1))), isFalse);
    },
  );
  test(
    'an early start records the real time and prices the entire drive',
    () async {
      final repo = DemoRepository();
      final booked = DateTime.now().add(const Duration(minutes: 30));
      repo.bookings.first.addAll({
        'startAt': booked.toIso8601String(),
        'endAt': booked.add(const Duration(hours: 2)).toIso8601String(),
      });
      repo.group!['lastOdometer'] = 900000;
      final before = DateTime.now();
      await repo.command('start', {'id': 'sample-approved', 'km': 42000});
      final trip = repo.trips.single,
          actual = DateTime.parse(repo.trips.single['startAt']);
      expect(actual.isBefore(before), isFalse);
      expect(actual.isAfter(DateTime.now()), isFalse);
      expect(actual.isBefore(booked), isTrue);
      expect(trip['startKm'], 42000);
      await repo.command('finish', {
        'id': trip['id'],
        'km': 42010,
        'endAt': actual.add(const Duration(hours: 1)).toIso8601String(),
      });
      expect(tripFare(trip).timeCents, 500);
      expect(tripFare(trip).totalCents, 880);
    },
  );
  test('a booking more than one hour away cannot be started', () async {
    final repo = DemoRepository();
    repo.bookings.first['startAt'] = DateTime.now()
        .add(const Duration(minutes: 61))
        .toIso8601String();
    await expectLater(
      repo.command('start', {'id': 'sample-approved', 'km': 42000}),
      throwsStateError,
    );
    expect(repo.trips, isEmpty);
  });
}

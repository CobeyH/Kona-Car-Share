import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kona_share/data/demo_repository.dart';
import 'package:kona_share/data/phone_service.dart';
import 'package:kona_share/ui/app_model.dart';
import 'package:kona_share/ui/app.dart';
import 'package:timezone/data/latest.dart' as tz;

class TestPhone extends PhoneService {
  TestPhone({bool enabled = true})
    : state = {
        'android': true,
        'homeSet': enabled,
        'notifications': enabled,
        'homeLat': enabled ? 49.2827 : null,
        'homeLng': enabled ? -123.1207 : null,
        'homeAddress': enabled ? 'Test home, Vancouver' : null,
        'homeRadius': 200,
        'background': true,
        'precise': true,
      };
  final Map<String, dynamic> state;
  int notificationSettingsOpened = 0,
      notificationRequests = 0,
      homeChanges = 0,
      mapOpened = 0;
  bool pendingOpen = false;
  Future<void> Function()? onOpen;
  @override
  bool get android => false;
  @override
  Future<Map<String, dynamic>> status() async => Map.of(state);
  @override
  void onNotificationOpened(Future<void> Function()? handler) {
    onOpen = handler;
  }

  @override
  Future<bool> consumeTripOpen() async {
    final v = pendingOpen;
    pendingOpen = false;
    return v;
  }

  Future<void> tapNotification() async {
    pendingOpen = true;
    await onOpen?.call();
  }

  @override
  Future<void> notificationSettings() async {
    notificationSettingsOpened++;
  }

  @override
  Future<void> notifications({bool openSettingsIfNeeded = false}) async {
    notificationRequests++;
    state['notifications'] = true;
  }

  @override
  Future<Map<String, dynamic>> setHome() async {
    homeChanges++;
    state.addAll({'homeSet': true, 'homeLat': 49.2827, 'homeLng': -123.1207});
    return {'saved': true};
  }

  @override
  Future<String?> homeAddress() async => 'Test home, Vancouver';
  @override
  Future<void> viewHome() async {
    mapOpened++;
  }
}

Future<void> reveal(WidgetTester tester, String text) async {
  for (
    var i = 0;
    i < 20 && find.text(text).hitTestable().evaluate().isEmpty;
    i++
  ) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
    await tester.pumpAndSettle();
  }
  expect(find.text(text).hitTestable(), findsOneWidget);
}

Future<void> reachHouse(WidgetTester tester, AppModel model) async {
  await tester.pumpWidget(KonaApp(model: model));
  await tester.pumpAndSettle();
  await tester.tap(find.text('House'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(tz.initializeTimeZones);
  testWidgets(
    'enabled setup buttons show checked state and notification settings work',
    (tester) async {
      final phone = TestPhone();
      final app = AppModel(DemoRepository(), phone);
      await reachHouse(tester, app);
      await reveal(tester, 'Notifications enabled');
      expect(
        find.widgetWithText(FilledButton, 'Notifications enabled'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Home location set'),
        findsOneWidget,
      );
      expect(find.text('Enable notifications'), findsNothing);
      expect(find.text('Test home, Vancouver'), findsOneWidget);
      expect(find.textContaining('200 m'), findsNothing);
      expect(find.text('49.28270, -123.12070'), findsNothing);
      expect(find.text('View in Maps'), findsNothing);
      await tester.tap(find.text('Notifications enabled'));
      await tester.pumpAndSettle();
      expect(phone.notificationSettingsOpened, 1);
      expect(phone.notificationRequests, 0);
      await tester.tap(find.text('Home location set'));
      await tester.pumpAndSettle();
      expect(find.text('Your home reminder area'), findsOneWidget);
      expect(find.text('Test home, Vancouver'), findsWidgets);
      expect(find.text('49.28270, -123.12070'), findsNothing);
      expect(find.textContaining('200 m reminder radius'), findsNothing);
      expect(phone.homeChanges, 0);
      await tester.tap(find.text('View in Maps').last);
      await tester.pumpAndSettle();
      expect(phone.mapOpened, 1);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
  testWidgets(
    'setup actions become enabled buttons after granting and setting home',
    (tester) async {
      final phone = TestPhone(enabled: false);
      final model = AppModel(DemoRepository(), phone);
      await reachHouse(tester, model);
      await reveal(tester, 'Enable notifications');
      await tester.tap(find.text('Enable notifications'));
      await tester.pumpAndSettle();
      expect(find.text('Notifications enabled'), findsOneWidget);
      await tester.tap(find.text('Set home location'));
      await tester.pumpAndSettle();
      expect(phone.homeChanges, 0);
      await tester.tap(find.text('Set home here'));
      await tester.pumpAndSettle();
      expect(phone.homeChanges, 1);
      expect(find.text('Home location set'), findsOneWidget);
      expect(find.text('Test home, Vancouver'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
  testWidgets(
    'notification opens the active trip from bookings and from a nested form',
    (tester) async {
      final repo = DemoRepository(), phone = TestPhone();
      await repo.command('start', {'id': 'sample-approved', 'km': 42816});
      final model = AppModel(repo, phone);
      await tester.pumpWidget(KonaApp(model: model));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bookings'));
      await tester.pumpAndSettle();
      expect(find.text('The house calendar'), findsOneWidget);
      await phone.tapNotification();
      await tester.pumpAndSettle();
      expect(find.text('Enjoy the drive.'), findsOneWidget);
      expect(find.text('The house calendar'), findsNothing);
      await tester.tap(find.text('Bookings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request a trip'));
      await tester.pumpAndSettle();
      expect(find.text('Request the Kona'), findsOneWidget);
      await phone.tapNotification();
      await tester.pumpAndSettle();
      expect(find.text('Enjoy the drive.'), findsOneWidget);
      expect(find.text('Request the Kona'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
  testWidgets(
    'cold notification waits for trip data before selecting the trip screen',
    (tester) async {
      final repo = DemoRepository(), phone = TestPhone()..pendingOpen = true;
      repo.tripsReady = false;
      await repo.command('start', {'id': 'sample-approved', 'km': 42816});
      final model = AppModel(repo, phone);
      await tester.pumpWidget(KonaApp(model: model));
      await tester.pumpAndSettle();
      expect(model.openTripRequested, isTrue);
      repo.tripsReady = true;
      await repo.command('demoRole', {'owner': false});
      await tester.pumpAndSettle();
      expect(model.openTripRequested, isFalse);
      expect(find.text('Enjoy the drive.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
  testWidgets('owner can finish a forgotten trip and delete then restore it', (
    tester,
  ) async {
    final repo = DemoRepository();
    await repo.command('start', {'id': 'sample-approved', 'km': 42816});
    await repo.command('demoRole', {'owner': true});
    final model = AppModel(repo, TestPhone());
    await tester.pumpWidget(KonaApp(model: model));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit trip'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('owner-end-km')), '42846');
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Finish with corrected details'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Finish with corrected details'));
    await tester.pumpAndSettle();
    expect(repo.trips.single['status'], 'completed');
    expect(repo.group!['activeTripId'], isNull);
    await tester.scrollUntilVisible(
      find.text('Delete trip'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Delete trip'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete trip'));
    await tester.pumpAndSettle();
    expect(repo.trips.single['status'], 'deleted');
    expect(model.completed, isEmpty);
    await tester.scrollUntilVisible(
      find.text('Restore trip'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Restore trip'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Restore trip'));
    await tester.pumpAndSettle();
    expect(repo.trips.single['status'], 'completed');
    expect(repo.trips.single['endKm'], 42846);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
    await tester.pump(const Duration(seconds: 2));
  });
  testWidgets('requesting a shared ride previews and saves an equal split', (
    tester,
  ) async {
    final repo = DemoRepository();
    final app = AppModel(repo, TestPhone());
    await tester.pumpWidget(KonaApp(model: app));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bookings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request a trip'));
    await tester.pumpAndSettle();
    await reveal(tester, 'Sam');
    await tester.tap(find.byKey(const ValueKey('invite-sam')));
    await tester.pumpAndSettle();
    await reveal(tester, 'ESTIMATED SPLIT');
    expect(find.text('Alex (you)'), findsOneWidget);
    expect(find.text(r'$9.70'), findsNWidgets(2));
    await reveal(tester, 'Send request');
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();
    expect(repo.bookings.first['riderIds'], ['alex', 'sam']);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
  testWidgets(
    'Fine by me records one owner without approving and a second owner completes approval',
    (tester) async {
      final repo = DemoRepository();
      await repo.command('demoRole', {'owner': true});
      final model = AppModel(repo, TestPhone());
      await tester.pumpWidget(KonaApp(model: model));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bookings'));
      await tester.pumpAndSettle();
      await reveal(tester, 'Fine by me');
      await tester.tap(find.text('Fine by me'));
      await tester.pumpAndSettle();
      final booking = repo.bookings.firstWhere(
        (b) => b['id'] == 'sample-request',
      );
      expect(booking['status'], 'requested');
      expect(booking['ownerClearances'].keys, ['cobey']);
      expect(find.text('Fine by: Cobey'), findsOneWidget);
      expect(find.text('Waiting for: Natalie'), findsOneWidget);
      repo.user = {'id': 'natalie', 'name': 'Natalie'};
      await repo.command('fineByMe', {'id': 'sample-request'});
      await tester.pumpAndSettle();
      expect(booking['status'], 'approved');
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
  test(
    'a single owner can approve after another owner says Fine by me',
    () async {
      final repo = DemoRepository();
      await repo.command('demoRole', {'owner': true});
      await repo.command('fineByMe', {'id': 'sample-request'});
      await repo.command('decision', {
        'id': 'sample-request',
        'status': 'approved',
      });
      expect(
        repo.bookings.firstWhere((b) => b['id'] == 'sample-request')['status'],
        'approved',
      );
    },
  );
  testWidgets('a passenger sees their own share in their monthly total', (
    tester,
  ) async {
    final repo = DemoRepository();
    await repo.command('start', {'id': 'sample-approved', 'km': 42816});
    repo.trips.first['riderIds'] = ['alex', 'sam'];
    await repo.command('finish', {
      'id': repo.trips.first['id'],
      'km': 42846,
      'endAt': DateTime.now().toIso8601String(),
    });
    repo.user = {'id': 'sam', 'name': 'Sam'};
    final model = AppModel(repo, TestPhone());
    await tester.pumpWidget(KonaApp(model: model));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Sam (you)'), findsOneWidget);
    final fare = tripFare(repo.trips.first);
    final share = (fare.totalCents ~/ 2);
    expect(find.text(money(share)), findsWidgets);
    expect(find.textContaining('YOUR TOTAL'), findsOneWidget);
    expect(find.text('Send to Spliit'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
  test('borrower cannot invoke owner commands', () async {
    final repo = DemoRepository();
    await repo.command('start', {'id': 'sample-approved', 'km': 42816});
    await expectLater(
      repo.command('deleteTrip', {'id': repo.trips.single['id']}),
      throwsStateError,
    );
    await expectLater(
      repo.command('editTrip', {'id': repo.trips.single['id']}),
      throwsStateError,
    );
  });
}

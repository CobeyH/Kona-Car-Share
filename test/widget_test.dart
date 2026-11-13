import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kona_share/data/demo_repository.dart';
import 'package:kona_share/data/phone_service.dart';
import 'package:kona_share/ui/app_model.dart';
import 'package:kona_share/ui/app.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  setUpAll(tz.initializeTimeZones);
  testWidgets('request estimate changes with the distance', (tester) async {
    final model = AppModel(DemoRepository(), PhoneService());
    await tester.pumpWidget(MaterialApp(home: BookingForm(model: model)));
    await tester.scrollUntilVisible(
      find.text('Estimated trip cost'.toUpperCase()),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(r'$19.40'), findsNWidgets(2));
    await tester.scrollUntilVisible(
      find.byKey(const Key('estimated-km')),
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const Key('estimated-km')), '100');
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Estimated trip cost'.toUpperCase()),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(r'$39.00'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
  testWidgets('only owners see approval actions', (tester) async {
    final repo = DemoRepository();
    final model = AppModel(repo, PhoneService());
    await tester.pumpWidget(KonaApp(model: model));
    await tester.tap(find.text('Bookings'));
    await tester.pumpAndSettle();
    expect(find.text('Approve'), findsNothing);
    await repo.command('demoRole', {'owner': true});
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Approve'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Approve'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(
      repo.bookings.firstWhere((b) => b['id'] == 'sample-request')['status'],
      'approved',
    );
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
  testWidgets('ending odometer cannot go backwards', (tester) async {
    final model = AppModel(DemoRepository(), PhoneService());
    final trip = {
      'id': 'test',
      'userId': 'alex',
      'startAt': DateTime.now()
          .subtract(const Duration(hours: 2))
          .toIso8601String(),
      'startKm': 42000,
    };
    await tester.pumpWidget(
      MaterialApp(
        home: OdometerForm(model: model, trip: trip),
      ),
    );
    await tester.enterText(find.byKey(const Key('odometer')), '41999');
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('The odometer cannot be lower than the previous reading.'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('The odometer cannot be lower than the previous reading.'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Finish & save trip'),
    );
    expect(button.onPressed, isNull);
    await tester.ensureVisible(find.byKey(const Key('odometer')));
    await tester.enterText(find.byKey(const Key('odometer')), '42030');
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Finish & save trip'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Finish & save trip'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
  for (final size in [const Size(360, 800), const Size(1200, 800)]) {
    testWidgets('home fits ${size.width.toInt()}px width', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final model = AppModel(DemoRepository(), PhoneService());
      await tester.pumpWidget(KonaApp(model: model));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Request the car'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });
  }
}

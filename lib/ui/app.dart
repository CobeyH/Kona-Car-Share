import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/repository.dart';
import '../domain/pricing.dart';
import 'app_model.dart';

part 'trip_forms.dart';
part 'account_pages.dart';
part 'house_page.dart';

const ink = Color(0xff173d34);
const muted = Color(0xff68766e);
const paper = Color(0xfff7f7f0);
const mint = Color(0xffdcebcf);
String money(int cents) => NumberFormat.currency(
  locale: 'en_CA',
  symbol: r'$',
  decimalDigits: 2,
).format(cents / 100);
DateTime homeTime(DateTime time) =>
    tz.TZDateTime.from(time, tz.getLocation('America/Vancouver'));
DateTime get homeNow => homeTime(DateTime.now());
String when(String value) =>
    DateFormat('EEE, MMM d · h:mm a').format(homeTime(DateTime.parse(value)));
Fare bookingFare(Json b) => KonaPricing.calculate(
  start: DateTime.parse(b['startAt']),
  end: DateTime.parse(b['endAt']),
  km: b['estimatedKm'],
);
Fare tripFare(Json t) => KonaPricing.calculate(
  start: DateTime.parse(t['startAt']),
  end: DateTime.parse(t['endAt']),
  km: t['endKm'] - t['startKm'],
);

class KonaApp extends StatelessWidget {
  const KonaApp({super.key, required this.model});
  final AppModel model;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Kona Share',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: ink,
        primary: ink,
        surface: paper,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        centerTitle: false,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.3,
          color: ink,
        ),
        headlineMedium: TextStyle(
          fontSize: 27,
          fontWeight: FontWeight.w700,
          letterSpacing: -.8,
          color: ink,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: ink, height: 1.5),
        bodyMedium: TextStyle(fontSize: 14, color: ink, height: 1.45),
      ),
      inputDecorationTheme: InputDecorationTheme(
        helperMaxLines: 3,
        errorMaxLines: 3,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.all(18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xffd9ded4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xffd9ded4)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: mint,
        height: 76,
      ),
    ),
    home: MainShell(model: model),
  );
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.color = Colors.white});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: Color(0xffe2e6dc)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: const EdgeInsets.all(22), child: child),
  );
}

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: children.expand((w) => [w, const SizedBox(height: 18)]).toList(),
  );
}

Widget title(BuildContext context, String text) =>
    Text(text, style: Theme.of(context).textTheme.headlineMedium);
Widget small(String text) =>
    Text(text, style: const TextStyle(color: muted, fontSize: 13, height: 1.5));
Widget label(String text) => Text(
  text.toUpperCase(),
  style: const TextStyle(
    color: muted,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
  ),
);
Widget line(String text, String value, {bool bold = false}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 5),
  child: Row(
    children: [
      Expanded(child: Text(text)),
      const SizedBox(width: 10),
      Text(
        value,
        style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
      ),
    ],
  ),
);

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.model});
  final AppModel model;
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int tab = 0;
  Timer? timer;
  AppModel get m => widget.model;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    m.addListener(_notice);
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(m.refreshPhone());
  }

  @override
  void dispose() {
    timer?.cancel();
    m.removeListener(_notice);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(m.refreshPhone());
  }

  void _notice() {
    if (m.message != null) {
      final message = m.message!;
      m.clearMessage();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: m,
    builder: (context, _) {
      final r = m.repository;
      if (!r.ready) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (r.user == null) return AuthPage(model: m);
      if (r.group == null) {
        if (r.user?['groupId'] != null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return JoinPage(model: m);
      }
      final pages = [
        home(context),
        bookings(context),
        activity(context),
        HousePage(model: m),
      ];
      final icons = [
        Icons.electric_car_outlined,
        Icons.calendar_month_outlined,
        Icons.receipt_long_outlined,
        Icons.home_outlined,
      ];
      const names = ['Trip', 'Bookings', 'Activity', 'House'];
      return LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 800;
          final content = Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: pages[tab],
            ),
          );
          return Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: ink,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.electric_car,
                      color: paper,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'kona share',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 23,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: Chip(
                    label: Text(m.owner ? 'Owner' : 'Borrower'),
                    backgroundColor: mint,
                    side: BorderSide.none,
                  ),
                ),
              ],
            ),
            body: SafeArea(
              child: Column(
                children: [
                  if (r.demo)
                    Container(
                      width: double.infinity,
                      color: const Color(0xffffe9bb),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: const Text(
                        'PREVIEW · Sample data on this device. Connect Firebase to share.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  if (m.busy) const LinearProgressIndicator(minHeight: 2),
                  if (r.problem != null)
                    MaterialBanner(
                      content: Text(r.problem!),
                      actions: [
                        TextButton(
                          onPressed: () => m.refreshPhone(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: wide
                        ? Row(
                            children: [
                              NavigationRail(
                                selectedIndex: tab,
                                onDestinationSelected: (v) =>
                                    setState(() => tab = v),
                                labelType: NavigationRailLabelType.all,
                                backgroundColor: paper,
                                destinations: List.generate(
                                  4,
                                  (i) => NavigationRailDestination(
                                    icon: Icon(icons[i]),
                                    label: Text(names[i]),
                                  ),
                                ),
                              ),
                              const VerticalDivider(width: 1),
                              Expanded(child: content),
                            ],
                          )
                        : content,
                  ),
                ],
              ),
            ),
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: tab,
                    onDestinationSelected: (v) => setState(() => tab = v),
                    destinations: List.generate(
                      4,
                      (i) => NavigationDestination(
                        icon: Icon(icons[i]),
                        label: names[i],
                      ),
                    ),
                  ),
          );
        },
      );
    },
  );
  void request() =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => BookingForm(model: m)));
  Widget home(BuildContext context) {
    final r = m.repository;
    final active = m.active;
    final approved =
        r.bookings
            .where((b) => b['userId'] == r.uid && b['status'] == 'approved')
            .toList()
          ..sort((a, b) => a['startAt'].compareTo(b['startAt']));
    final requests = r.bookings.where((b) => b['status'] == 'requested').length;
    return PageBody(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label(r.group!['name']),
            const SizedBox(height: 8),
            Text(
              active == null
                  ? 'A little freedom.\nA fair share.'
                  : 'Enjoy the drive.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 8),
            small('Hi ${r.user!['name']}. Your next trip, without the maths.'),
          ],
        ),
        if (m.pendingFinish?.isNotEmpty == true)
          Panel(
            color: const Color(0xffffe9bb),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your ending reading is saved.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                small(
                  'Send it when you have a connection. The saved return time will be used.',
                ),
                TextButton(
                  onPressed: m.busy
                      ? null
                      : () => m.action('finish', m.pendingFinish!),
                  child: const Text('Retry saved finish'),
                ),
              ],
            ),
          ),
        if (active != null)
          Panel(
            color: mint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.route),
                    const SizedBox(width: 8),
                    label('Trip in progress'),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  _elapsed(active['startAt']),
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                small(
                  'Started at ${active['startKm']} km · ${when(active['startAt'])}',
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: m.busy
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  OdometerForm(model: m, trip: active),
                            ),
                          ),
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Finish trip'),
                  ),
                ),
                const SizedBox(height: 10),
                small(
                  'Confirm the ending odometer when you park. Plug in below 30% charge.',
                ),
              ],
            ),
          )
        else
          Panel(
            color: mint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.electric_car, size: 62, color: ink),
                    Spacer(),
                    Icon(Icons.bolt, size: 32, color: ink),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  r.group!['activeTripId'] == null
                      ? 'Ready for the next adventure.'
                      : 'The Kona is out on a trip.',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                small(
                  'Request a time, get the okay, and enter the odometer. Charging is included.',
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: request,
                    icon: const Icon(Icons.add),
                    label: const Text('Request the car'),
                  ),
                ),
              ],
            ),
          ),
        if (m.owner && requests > 0)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.inbox_outlined),
            title: Text(
              '$requests request${requests == 1 ? '' : 's'} to review',
            ),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () => setState(() => tab = 1),
          ),
        if (active == null && approved.isNotEmpty) ...[
          title(context, 'Your approved trips'),
          for (final b in approved) bookingCard(context, b, start: true),
        ],
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label('Your house rate'),
              const SizedBox(height: 12),
              const Text(
                '\$1 to start · \$5/hour · \$0.28/km',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 6),
              small(
                '\$6 minimum. The cheaper daily rate is applied automatically: \$80 per calendar day with 250 km included, plus the trip’s \$1 base fee. Monthly payment is due on the 1st.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _elapsed(String value) {
    final d = DateTime.now().difference(DateTime.parse(value));
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }

  Widget bookingCard(BuildContext context, Json b, {bool start = false}) {
    final r = m.repository;
    final status = b['status'] as String;
    final fare = bookingFare(b);
    final approved = ['approved', 'active'].contains(status);
    final inWindow =
        !DateTime.now().isBefore(DateTime.parse(b['startAt'])) &&
        DateTime.now().isBefore(DateTime.parse(b['endAt']));
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  b['driver'],
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              _badge(status),
            ],
          ),
          const SizedBox(height: 12),
          Text(when(b['startAt'])),
          small('Until ${when(b['endAt'])}'),
          if ((b['note'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(b['note']),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: small('${b['estimatedKm']} km estimated')),
              Text(
                '${money(fare.totalCents)} est.',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if ((b['decisionNote'] as String? ?? '').isNotEmpty)
            small('Owner’s note: ${b['decisionNote']}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (m.owner && status == 'requested') ...[
                FilledButton.icon(
                  onPressed: m.busy
                      ? null
                      : () => m.action('decision', {
                          'id': b['id'],
                          'status': 'approved',
                        }),
                  icon: const Icon(Icons.check),
                  label: const Text('Approve'),
                ),
                OutlinedButton(
                  onPressed: m.busy ? null : () => _decline(b),
                  child: const Text('Decline'),
                ),
              ],
              if (approved)
                OutlinedButton.icon(
                  onPressed: () =>
                      m.run(() => m.phone.calendar(b, b['driver'])),
                  icon: const Icon(Icons.event_available, size: 18),
                  label: const Text('Add to calendar'),
                ),
              if (start &&
                  status == 'approved' &&
                  r.group!['activeTripId'] == null)
                FilledButton(
                  onPressed: m.busy || !inWindow
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OdometerForm(model: m, booking: b),
                          ),
                        ),
                  child: Text(
                    inWindow ? 'Start trip' : 'Start during booked time',
                  ),
                ),
              if (['requested', 'approved'].contains(status) &&
                  (b['userId'] == r.uid || m.owner))
                TextButton(
                  onPressed: m.busy ? null : () => _cancel(b),
                  child: const Text('Cancel'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(String status) {
    final color = switch (status) {
      'approved' || 'active' => mint,
      'requested' => const Color(0xffffe9bb),
      _ => const Color(0xffedf0ea),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status == 'requested'
            ? 'Awaiting approval'
            : '${status[0].toUpperCase()}${status.substring(1)}',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _decline(Json b) async {
    final note = await _askText(
      context,
      'Decline request',
      'Optional reason',
      optional: true,
    );
    if (note != null) {
      await m.action('decision', {
        'id': b['id'],
        'status': 'denied',
        'note': note,
      });
    }
  }

  Future<void> _cancel(Json b) async {
    final okay = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: const Text(
          'It will remain visible as cancelled in the house history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep booking'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    if (okay == true) {
      await m.action('decision', {'id': b['id'], 'status': 'cancelled'});
    }
  }

  Widget bookings(BuildContext context) {
    final all = m.repository.bookings;
    final upcoming =
        all
            .where(
              (b) => ['requested', 'approved', 'active'].contains(b['status']),
            )
            .toList()
          ..sort((a, b) => a['startAt'].compareTo(b['startAt']));
    final past = all
        .where(
          (b) => !['requested', 'approved', 'active'].contains(b['status']),
        )
        .take(20)
        .toList();
    return PageBody(
      children: [
        title(context, 'The house calendar'),
        small(
          'All times use Vancouver time. Everyone in the group can add approved bookings to their own calendar.',
        ),
        FilledButton.icon(
          onPressed: request,
          icon: const Icon(Icons.add),
          label: const Text('Request a trip'),
        ),
        if (upcoming.isEmpty)
          const Panel(
            child: Text(
              'No upcoming bookings. There’s room for a little adventure.',
            ),
          ),
        for (final b in upcoming)
          bookingCard(context, b, start: b['userId'] == m.repository.uid),
        if (past.isNotEmpty) label('Earlier requests'),
        for (final b in past) bookingCard(context, b),
      ],
    );
  }

  Widget activity(BuildContext context) {
    final trips = m.completed
        .where((t) => m.owner || t['userId'] == m.repository.uid)
        .toList();
    final now = homeNow;
    final month = trips.where((t) {
      final end = homeTime(DateTime.parse(t['endAt']));
      return end.year == now.year && end.month == now.month;
    });
    final total = month.fold<int>(0, (sum, t) => sum + tripFare(t).totalCents);
    final due = tz.TZDateTime(
      tz.getLocation('America/Vancouver'),
      now.year,
      now.month + 1,
      1,
    );
    return PageBody(
      children: [
        title(context, 'Every trip, accounted for.'),
        Panel(
          color: ink,
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: paper),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.owner
                      ? 'HOUSE TOTAL · ${DateFormat.MMMM().format(now).toUpperCase()}'
                      : 'YOUR TOTAL · ${DateFormat.MMMM().format(now).toUpperCase()}',
                  style: const TextStyle(fontSize: 11, letterSpacing: 1.5),
                ),
                const SizedBox(height: 14),
                Text(
                  money(total),
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1.5,
                  ),
                ),
                Text(
                  'Payable ${DateFormat('MMMM d').format(due)} · See balances in Spliit',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        if (trips.isEmpty)
          const Panel(
            child: Text(
              'Finished trips will appear here with their distance, time and price breakdown.',
            ),
          ),
        for (final t in trips)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t['driver'],
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Text(
                      money(tripFare(t).totalCents),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                small('${t['endKm'] - t['startKm']} km · ${when(t['endAt'])}'),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Price breakdown'),
                  children: [
                    FareBreakdown(
                      fare: tripFare(t),
                      estimate: false,
                      heading: false,
                    ),
                  ],
                ),
                small(_syncLabel(t['sync'])),
                if (t['userId'] == m.repository.uid && t['sync'] != 'sent')
                  TextButton.icon(
                    onPressed: m.busy
                        ? null
                        : () => m.action('sync', {'id': t['id']}),
                    icon: const Icon(Icons.sync, size: 18),
                    label: Text(
                      ['sending', 'uncertain'].contains(t['sync'])
                          ? 'Check Spliit'
                          : 'Send to Spliit',
                    ),
                  ),
              ],
            ),
          ),
        small(
          'These are recorded car-use costs, not a payment status. Spliit tracks who owes whom; this app does not charge a card or move money.',
        ),
      ],
    );
  }

  String _syncLabel(String? status) => switch (status) {
    'sent' => 'Added to Spliit',
    'pending' => 'Waiting to send to Spliit',
    'sending' || 'uncertain' => 'Spliit needs a check · no automatic resend',
    _ => 'Saved in Kona · not yet added to Spliit',
  };
}

part of 'app.dart';

class FareBreakdown extends StatelessWidget {
  const FareBreakdown({
    super.key,
    required this.fare,
    required this.estimate,
    this.heading = true,
  });
  final Fare fare;
  final bool estimate, heading;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (heading) ...[
        label(estimate ? 'Estimated trip cost' : 'Trip cost'),
        const SizedBox(height: 8),
        Text(
          money(fare.totalCents),
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 16),
      ],
      line('Base trip fee', r'$1.00'),
      if (fare.dailyDays > 0)
        line(
          '${fare.dailyDays} calendar day${fare.dailyDays == 1 ? '' : 's'} at daily rate',
          money(fare.dailyCents),
        ),
      line(
        'Time${fare.dailyDays > 0 ? ' outside daily rate' : ''}',
        money(fare.timeCents),
      ),
      line(
        'Distance${fare.includedKm > 0 ? ' beyond ${fare.includedKm} included km' : ''}',
        money(fare.distanceCents),
      ),
      if (fare.minimumCents > 0)
        line('Adjustment to the \$6 minimum', money(fare.minimumCents)),
      const Divider(height: 24),
      line(
        estimate ? 'Estimated total' : 'Total',
        money(fare.totalCents),
        bold: true,
      ),
      if (estimate)
        small(
          'Based on your planned time and kilometres. Final cost uses the actual trip. Charging included; parking and ferries are extra.',
        ),
    ],
  );
}

class FormFrame extends StatelessWidget {
  const FormFrame({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: PageBody(children: children),
        ),
      ),
    ),
  );
}

Future<DateTime?> pickMoment(
  BuildContext context,
  DateTime initial, {
  DateTime? first,
}) async {
  final local = homeTime(initial);
  final date = await showDatePicker(
    context: context,
    initialDate: DateTime(local.year, local.month, local.day),
    firstDate: first ?? DateTime(homeNow.year, homeNow.month, homeNow.day),
    lastDate: DateTime(homeNow.year + 2),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: local.hour, minute: local.minute),
  );
  if (time == null) return null;
  return tz.TZDateTime(
    tz.getLocation('America/Vancouver'),
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
}

class BookingForm extends StatefulWidget {
  const BookingForm({super.key, required this.model});
  final AppModel model;
  @override
  State<BookingForm> createState() => _BookingFormState();
}

class _BookingFormState extends State<BookingForm> {
  late DateTime start = homeNow.add(const Duration(hours: 1)),
      end = start.add(const Duration(hours: 2));
  final km = TextEditingController(text: '30'), note = TextEditingController();
  @override
  void dispose() {
    km.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final distance = int.tryParse(km.text);
    final valid =
        distance != null &&
        distance >= 0 &&
        distance <= 100000 &&
        end.isAfter(start) &&
        end.difference(start) <= const Duration(days: 31) &&
        !start.isBefore(DateTime.now().subtract(const Duration(minutes: 4)));
    final fare = valid
        ? KonaPricing.calculate(start: start, end: end, km: distance)
        : null;
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) => FormFrame(
        title: 'Request the Kona',
        children: [
          title(context, 'Where to next?'),
          small(
            'Choose your time and estimated distance. An owner will approve or decline the request.',
          ),
          Panel(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.north_east),
                  title: const Text('Start'),
                  subtitle: Text(when(start.toIso8601String())),
                  trailing: const Icon(Icons.edit_outlined, size: 19),
                  onTap: () async {
                    final value = await pickMoment(context, start);
                    if (value != null) {
                      setState(() {
                        final length = end.difference(start);
                        start = value;
                        end = start.add(length);
                      });
                    }
                  },
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.south_west),
                  title: const Text('Return'),
                  subtitle: Text(when(end.toIso8601String())),
                  trailing: const Icon(Icons.edit_outlined, size: 19),
                  onTap: () async {
                    final value = await pickMoment(context, end);
                    if (value != null) setState(() => end = value);
                  },
                ),
              ],
            ),
          ),
          TextField(
            key: const Key('estimated-km'),
            controller: km,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Estimated distance',
              suffixText: 'km',
              helperText: 'A rough estimate is fine. The odometer gives the final distance.',
            ),
          ),
          TextField(
            controller: note,
            maxLength: 500,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'A note for the owners',
              hintText: 'Groceries, an afternoon out…',
            ),
          ),
          if (fare != null)
            Panel(
              color: mint,
              child: FareBreakdown(fare: fare, estimate: true),
            )
          else
            const Text(
              'Choose a future start, a later return (up to 31 days), and valid kilometres.',
              style: TextStyle(color: Colors.red),
            ),
          FilledButton(
            onPressed: valid && !widget.model.busy
                ? () async {
                    final okay = await widget.model.action('request', {
                      'startAt': start.toUtc().toIso8601String(),
                      'endAt': end.toUtc().toIso8601String(),
                      'estimatedKm': distance,
                      'note': note.text.trim(),
                    });
                    if (okay && context.mounted) Navigator.pop(context);
                  }
                : null,
            child: const Text('Send request'),
          ),
          small(
            'Submitting a request does not reserve the car until an owner approves it.',
          ),
        ],
      ),
    );
  }
}

class OdometerForm extends StatefulWidget {
  const OdometerForm({super.key, required this.model, this.booking, this.trip});
  final AppModel model;
  final Json? booking, trip;
  @override
  State<OdometerForm> createState() => _OdometerFormState();
}

class _OdometerFormState extends State<OdometerForm> {
  final km = TextEditingController();
  late DateTime end = DateTime.now();
  bool scanning = false;
  bool get finishing => widget.trip != null;
  @override
  void initState() {
    super.initState();
    if (!finishing) {
      km.text = '${widget.model.repository.group?['lastOdometer'] ?? ''}';
    }
    final arrival = widget.model.phoneStatus['arrival'];
    if (finishing && arrival is int) {
      final at = DateTime.fromMillisecondsSinceEpoch(arrival);
      if (at.isAfter(DateTime.parse(widget.trip!['startAt'])) &&
          at.isBefore(DateTime.now())) {
        end = at;
      }
    }
  }

  @override
  void dispose() {
    km.dispose();
    super.dispose();
  }

  Future<void> photo() async {
    if (!widget.model.phone.android) {
      await widget.model.run(
        () async =>
            throw StateError('Photo reading is available in the Android app.'),
      );
      return;
    }
    setState(() => scanning = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        imageQuality: 90,
      );
      if (file == null) return;
      final values = await widget.model.phone.scan(file.path);
      if (!mounted) return;
      if (values.isEmpty) {
        throw StateError(
          'No clear odometer number found. Try typing it or take a closer photo.',
        );
      }
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Which is the odometer?'),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                'Check the number against the dashboard. Other dashboard numbers may appear too.',
              ),
            ),
            for (final v in values)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, v),
                child: Text(
                  '$v km',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context),
              child: const Text('Type it myself'),
            ),
          ],
        ),
      );
      if (selected != null) setState(() => km.text = selected);
    } catch (e) {
      await widget.model.run(() async => throw e);
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = int.tryParse(km.text);
    final startKm = finishing
        ? widget.trip!['startKm'] as int
        : widget.model.repository.group?['lastOdometer'] as int? ?? 0;
    final valid =
        value != null &&
        value >= startKm &&
        value < 10000000 &&
        (!finishing ||
            (value - startKm <= 100000 &&
                end.difference(DateTime.parse(widget.trip!['startAt'])) <=
                    const Duration(days: 31) &&
                !end.isBefore(DateTime.parse(widget.trip!['startAt'])) &&
                !end.isAfter(DateTime.now().add(const Duration(minutes: 5)))));
    final fare = finishing && valid
        ? KonaPricing.calculate(
            start: DateTime.parse(widget.trip!['startAt']),
            end: end,
            km: value - startKm,
          )
        : null;
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) => FormFrame(
        title: finishing ? 'Welcome home' : 'Start your trip',
        children: [
          label(finishing ? 'One last reading' : 'Before you drive'),
          title(
            context,
            finishing ? 'Park. Read. Done.' : 'What’s on the odometer?',
          ),
          small(
            finishing
                ? 'Enter the total odometer reading, not the distance for this trip.'
                : 'Check the car’s current odometer. We’ll remember the start time for you.',
          ),
          TextField(
            key: const Key('odometer'),
            controller: km,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w600,
              letterSpacing: -1,
            ),
            decoration: InputDecoration(
              labelText: finishing ? 'Ending odometer' : 'Starting odometer',
              suffixText: 'km',
              helperText: finishing
                  ? 'Started at $startKm km'
                  : 'Last recorded: ${startKm == 0 ? 'no reading yet' : '$startKm km'}. Check against the car.',
            ),
          ),
          OutlinedButton.icon(
            onPressed: scanning ? null : photo,
            icon: scanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_camera_outlined),
            label: const Text('Read from a photo'),
          ),
          if (finishing)
            Panel(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Return time'),
                subtitle: Text(when(end.toIso8601String())),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final start = homeTime(
                    DateTime.parse(widget.trip!['startAt']),
                  );
                  final at = await pickMoment(
                    context,
                    end,
                    first: DateTime(start.year, start.month, start.day),
                  );
                  if (at != null) setState(() => end = at);
                },
              ),
            ),
          if (finishing)
            small(
              'Adjust the return time if the reminder arrived late. The trip is timed up to the time shown above.',
            ),
          if (fare != null)
            Panel(
              color: mint,
              child: FareBreakdown(fare: fare, estimate: false),
            ),
          if (value != null && value < startKm)
            const Text(
              'The odometer cannot be lower than the previous reading.',
              style: TextStyle(color: Colors.red),
            ),
          FilledButton(
            onPressed: valid && !widget.model.busy && !scanning
                ? () async {
                    final okay = await widget.model.action(
                      finishing ? 'finish' : 'start',
                      finishing
                          ? {
                              'id': widget.trip!['id'],
                              'km': value,
                              'endAt': end.toUtc().toIso8601String(),
                            }
                          : {'id': widget.booking!['id'], 'km': value},
                    );
                    if (okay && context.mounted) Navigator.pop(context);
                    if (!okay) await widget.model.refreshPhone();
                  }
                : null,
            child: Text(finishing ? 'Finish & save trip' : 'Start trip'),
          ),
          if (finishing)
            small(
              'Plug the Kona in if the battery is below 30%. Please leave it as you found it.',
            ),
        ],
      ),
    );
  }
}

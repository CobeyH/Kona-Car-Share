part of 'app.dart';

class TripOwnerActions extends StatelessWidget {
  const TripOwnerActions({super.key, required this.model, required this.trip});
  final AppModel model;
  final Json trip;
  @override
  Widget build(BuildContext context) {
    if (!model.owner) return const SizedBox.shrink();
    final deleted = trip['status'] == 'deleted';
    final ledgerPending = [
      'pending',
      'sending',
      'uncertain',
    ].contains(trip['ledgerState']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (trip['editedByName'] != null)
          small(
            'Updated by ${trip['editedByName']}${trip['editedAt'] == null ? '' : ' · ${when(trip['editedAt'])}'}',
          ),
        if ((trip['editReason'] as String? ?? '').isNotEmpty)
          small(trip['editReason']),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!deleted)
              TextButton.icon(
                onPressed: model.busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              OwnerTripForm(model: model, trip: trip),
                        ),
                      ),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit trip'),
              ),
            TextButton.icon(
              onPressed: model.busy ? null : () => confirm(context, deleted),
              icon: Icon(
                deleted ? Icons.restore : Icons.delete_outline,
                size: 18,
              ),
              label: Text(deleted ? 'Restore trip' : 'Delete trip'),
            ),
          ],
        ),
        if (ledgerPending) ...[
          small(
            trip['ledgerAction'] == 'delete'
                ? 'Removal from Spliit still needs confirmation.'
                : 'The linked Spliit expense still needs updating.',
          ),
          TextButton.icon(
            onPressed: model.busy
                ? null
                : () => model.action('syncCorrection', {'id': trip['id']}),
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('Check Spliit correction'),
          ),
        ] else if (deleted && trip['ledgerState'] == 'done')
          small('Removed from Spliit.'),
      ],
    );
  }

  Future<void> confirm(BuildContext context, bool restore) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(restore ? 'Restore this trip?' : 'Delete this trip?'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                restore
                    ? 'Restore the saved trip and its linked Spliit expense. An active trip can only be restored when the car has no other active trip.'
                    : 'Remove this trip from totals and remove its linked Spliit expense. If it is active, the car becomes available again. The saved record can be restored from Activity.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reason,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(restore ? 'Restore trip' : 'Delete trip'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await model.action(restore ? 'restoreTrip' : 'deleteTrip', {
        'id': trip['id'],
        'expectedChangeId': trip['changeId'],
        'reason': reason.text.trim(),
      });
    }
    Future<void>.delayed(const Duration(seconds: 1), reason.dispose);
  }
}

class OwnerTripForm extends StatefulWidget {
  const OwnerTripForm({super.key, required this.model, required this.trip});
  final AppModel model;
  final Json trip;
  @override
  State<OwnerTripForm> createState() => _OwnerTripFormState();
}

class _OwnerTripFormState extends State<OwnerTripForm> {
  late DateTime start = DateTime.parse(widget.trip['startAt']);
  late DateTime end = widget.trip['endAt'] == null
      ? DateTime.now()
      : DateTime.parse(widget.trip['endAt']);
  late final startKm = TextEditingController(text: '${widget.trip['startKm']}');
  late final endKm = TextEditingController(
    text: widget.trip['endKm'] == null ? '' : '${widget.trip['endKm']}',
  );
  final reason = TextEditingController();
  @override
  void dispose() {
    startKm.dispose();
    endKm.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final first = int.tryParse(startKm.text), last = int.tryParse(endKm.text);
    final valid =
        first != null &&
        last != null &&
        first >= 0 &&
        last >= first &&
        last < 10000000 &&
        last - first <= 100000 &&
        !end.isBefore(start) &&
        end.difference(start) <= const Duration(days: 31) &&
        !end.isAfter(DateTime.now().add(const Duration(minutes: 5)));
    final fare = valid
        ? KonaPricing.calculate(start: start, end: end, km: last - first)
        : null;
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) => FormFrame(
        title: 'Correct trip',
        children: [
          title(context, '${widget.trip['driver']}’s trip'),
          small(
            'Use the actual driving times and odometer readings. If the trip was left running, enter when the car really returned. Corrections are recorded and the linked Spliit expense is updated.',
          ),
          Panel(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Actual start'),
                  subtitle: Text(when(start.toIso8601String())),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () async {
                    final at = await pickMoment(
                      context,
                      start,
                      first: DateTime(2000),
                    );
                    if (at != null) setState(() => start = at);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Actual return'),
                  subtitle: Text(when(end.toIso8601String())),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () async {
                    final at = await pickMoment(
                      context,
                      end,
                      first: DateTime(2000),
                    );
                    if (at != null) setState(() => end = at);
                  },
                ),
              ],
            ),
          ),
          TextField(
            key: const Key('owner-start-km'),
            controller: startKm,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Starting odometer',
              suffixText: 'km',
            ),
          ),
          TextField(
            key: const Key('owner-end-km'),
            controller: endKm,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Ending odometer',
              suffixText: 'km',
            ),
          ),
          TextField(
            controller: reason,
            maxLength: 500,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              hintText: 'Forgot to end the trip…',
            ),
          ),
          if (fare != null)
            Panel(
              color: mint,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FareBreakdown(fare: fare, estimate: false),
                  RideSplit(
                    model: widget.model,
                    ride: widget.trip,
                    totalCents: fare.totalCents,
                  ),
                ],
              ),
            )
          else
            small(
              'Enter valid odometer readings and return after the start, up to 31 days later.',
            ),
          FilledButton(
            onPressed: valid && !widget.model.busy
                ? () async {
                    final saved = await widget.model.action('editTrip', {
                      'id': widget.trip['id'],
                      'expectedChangeId': widget.trip['changeId'],
                      'startAt': start.toUtc().toIso8601String(),
                      'endAt': end.toUtc().toIso8601String(),
                      'startKm': first,
                      'endKm': last,
                      'reason': reason.text.trim(),
                    });
                    if (saved && context.mounted) Navigator.pop(context);
                  }
                : null,
            child: Text(
              widget.trip['status'] == 'active'
                  ? 'Finish with corrected details'
                  : 'Save correction',
            ),
          ),
        ],
      ),
    );
  }
}

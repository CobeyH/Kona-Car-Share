part of 'app.dart';

class HousePage extends StatelessWidget {
  const HousePage({super.key, required this.model});
  final AppModel model;
  @override
  Widget build(BuildContext context) {
    final r = model.repository, status = model.phoneStatus;
    final remoteMembers = (r.group!['spliitMembers'] as List? ?? [])
        .where((v) => v['id'] != r.group!['ownerMemberId'])
        .toList();
    final linked = r.me?['spliitMemberId'];
    final selectedMember = remoteMembers.any((v) => v['id'] == linked)
        ? linked as String?
        : null;
    return PageBody(
      children: [
        title(context, 'Your house, in sync.'),
        if (r.demo)
          Panel(
            color: const Color(0xffffe9bb),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Preview the two roles',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                small(
                  'Sample data resets when the preview restarts. No real account or expense is created.',
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Borrower')),
                    ButtonSegment(value: true, label: Text('Owner')),
                  ],
                  selected: {model.owner},
                  onSelectionChanged: (v) =>
                      model.action('demoRole', {'owner': v.first}),
                ),
              ],
            ),
          ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label('The group'),
              const SizedBox(height: 10),
              Text(
                r.group!['name'],
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final member in r.members)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: mint,
                    child: Text(
                      ((member['name'] as String).characters.firstOrNull ??
                          '?'),
                    ),
                  ),
                  title: Text(member['name']),
                  subtitle: Text(
                    member['role'] == 'owner' ? 'Vehicle owner' : 'Borrower',
                  ),
                ),
              if (model.owner)
                OutlinedButton.icon(
                  onPressed: model.busy ? null : () => invite(context),
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Invite an owner or borrower'),
                ),
            ],
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label('Arrive home, remember to finish'),
              const SizedBox(height: 12),
              const Text(
                'A helpful tap on the shoulder.',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 10,
                children: [
                  if (status['homeSet'] == true)
                    FilledButton.icon(
                      key: const Key('home-ready'),
                      onPressed: () => showHome(context),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Home location set'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: model.busy ? null : () => setHome(context),
                      icon: const Icon(Icons.home_outlined),
                      label: const Text('Set home location'),
                    ),
                  if (status['notifications'] == true)
                    FilledButton.icon(
                      key: const Key('notifications-ready'),
                      onPressed: () =>
                          model.run(model.phone.notificationSettings),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Notifications enabled'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: model.busy
                          ? null
                          : () => model.run(() async {
                              await model.phone.notifications(
                                openSettingsIfNeeded: true,
                              );
                              await model.refreshPhone();
                            }),
                      icon: const Icon(Icons.notifications_outlined),
                      label: const Text('Enable notifications'),
                    ),
                ],
              ),
              if (status['homeSet'] == true) ...[
                const SizedBox(height: 14),
                HomeLocationDetails(model: model),
              ],
              const SizedBox(height: 12),
              Text(
                'Arrival access: ${status['background'] == true && status['precise'] == true ? 'enabled' : 'needs precise location, all the time'}',
              ),
              TextButton(
                onPressed: () => model.run(model.phone.backgroundSettings),
                child: const Text('Open location settings'),
              ),
              small(
                'In Android settings choose Permissions → Location → Allow all the time, with precise location. Arrival alerts can be delayed by Android; check the return time when finishing. No route history is collected.',
              ),
            ],
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label('Settle up with Spliit'),
              const SizedBox(height: 12),
              Text(
                (r.group!['spliitGroupId'] as String? ?? '').isNotEmpty
                    ? 'Connected to ${r.group!['spliitName']}'
                    : 'Connect your existing group',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              small(
                'Finished trips become expenses credited to the car owner and owed by the borrower. No payment is collected in this app.',
              ),
              if (model.owner)
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SpliitSetup(model: model),
                    ),
                  ),
                  child: const Text('Configure Spliit'),
                ),
              if ((r.group!['spliitMembers'] as List? ?? []).isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('${r.group!['spliitGroupId']}:$selectedMember'),
                  initialValue: selectedMember,
                  decoration: const InputDecoration(
                    labelText: 'Your Spliit participant',
                  ),
                  items: (r.group!['spliitMembers'] as List)
                      .where((v) => v['id'] != r.group!['ownerMemberId'])
                      .map(
                        (v) => DropdownMenuItem<String>(
                          value: v['id'],
                          child: Text(v['name']),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) model.action('spliitMap', {'memberId': v});
                  },
                ),
              ],
              const SizedBox(height: 10),
              small(
                'The Spliit group link grants access to its expenses. It is shared only within this household group. If a send is uncertain, the app checks for the existing expense before doing anything else.',
              ),
            ],
          ),
        ),
        ExpansionTile(
          title: const Text('Agreement & rates'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '\$1/trip + \$5/hour + \$0.28/km. \$6 minimum.\n\nWhen cheaper: \$80 per calendar day, midnight to midnight, with 250 km included for each daily-rate day. Included km are pooled over the trip. Additional km cost \$0.28. The \$1 fee is always added once per trip.',
                  ),
                  const SizedBox(height: 12),
                  small(
                    'Charging is included. Pay on the 1st of the following month. Parking, ferries, tickets and damage are separate. A late return may incur a discretionary \$20 fee. Lost keys cost \$20 plus replacement and reprogramming; these fees are not applied automatically. Regular daily trips with the owners are free; longer shared trips are agreed separately. Shared borrowed rides split one trip total equally.',
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!r.demo)
          TextButton(
            onPressed: model.busy ? null : () => model.run(() => r.signOut()),
            child: const Text('Sign out'),
          ),
      ],
    );
  }

  Future<void> setHome(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Use your current location as home?'),
        content: const Text(
          'Do this while you’re at home. Arrival reminders use a 200 m area around the saved point.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Set home here'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await model.run(() async {
        await model.phone.setHome();
        await model.refreshPhone();
      });
    }
  }

  Future<void> showHome(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your home reminder area'),
        content: SizedBox(
          width: 420,
          child: ListenableBuilder(
            listenable: model,
            builder: (context, _) =>
                HomeLocationDetails(model: model, showMap: true),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              setHome(context);
            },
            child: const Text('Change home location'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> invite(BuildContext context) async {
    Json? codes;
    await model.run(() async {
      codes = await model.repository.command('invites');
    });
    if (codes == null || !context.mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite to the house'),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Borrower invitation',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SelectableText(codes!['borrowerCode']),
              TextButton.icon(
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: codes!['borrowerCode']),
                ),
                icon: const Icon(Icons.copy),
                label: const Text('Copy borrower code'),
              ),
              const Divider(height: 24),
              const Text(
                'Owner invitation',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              small(
                'Owner access includes approving requests and changing the Spliit connection. Share only with a vehicle owner.',
              ),
              SelectableText(codes!['ownerCode']),
              TextButton.icon(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: codes!['ownerCode'])),
                icon: const Icon(Icons.copy),
                label: const Text('Copy owner code'),
              ),
            ],
          ),
        ),
        actions: [
          if (!model.repository.demo)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await model.action('rotateInvites');
              },
              child: const Text('Replace both codes'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class SpliitSetup extends StatefulWidget {
  const SpliitSetup({super.key, required this.model});
  final AppModel model;
  @override
  State<SpliitSetup> createState() => _SpliitSetupState();
}

class _SpliitSetupState extends State<SpliitSetup> {
  final link = TextEditingController();
  Json? remote;
  String? ownerId;
  bool cad = false;
  @override
  void dispose() {
    link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model,
    builder: (context, _) => FormFrame(
      title: 'Connect Spliit',
      children: [
        title(context, 'Keep the balances together.'),
        small(
          'Use your existing Spliit group, with a participant for the car owners and each borrower.',
        ),
        TextField(
          controller: link,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Spliit group link',
            hintText: 'https://spliit.app/groups/…',
          ),
          onChanged: (_) => setState(() {
            remote = null;
            ownerId = null;
            cad = false;
          }),
        ),
        OutlinedButton(
          onPressed: widget.model.busy
              ? null
              : () => widget.model.run(() async {
                  final value = await widget.model.repository.command(
                    'spliitPreview',
                    {'url': link.text},
                  );
                  if (mounted) setState(() => remote = value);
                }),
          child: const Text('Load group'),
        ),
        if (remote != null) ...[
          Text(remote!['name'], style: Theme.of(context).textTheme.titleLarge),
          DropdownButtonFormField<String>(
            initialValue: ownerId,
            decoration: const InputDecoration(
              labelText: 'Credit car-use costs to',
            ),
            items: (remote!['participants'] as List)
                .map(
                  (v) => DropdownMenuItem<String>(
                    value: v['id'],
                    child: Text(v['name']),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => ownerId = v),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: cad,
            onChanged: (v) => setState(() => cad = v ?? false),
            title: const Text('This group uses Canadian dollars.'),
          ),
          FilledButton(
            onPressed: ownerId != null && cad && !widget.model.busy
                ? () async {
                    final okay = await widget.model.action('spliitConnect', {
                      'url': link.text,
                      'ownerId': ownerId,
                      'confirmedCad': cad,
                    });
                    if (okay && context.mounted) Navigator.pop(context);
                  }
                : null,
            child: const Text('Connect group'),
          ),
        ],
        small(
          'Each borrower chooses their own Spliit participant in House settings. The requester records the trip once. All borrowers on a shared ride must be linked before its expense is sent.',
        ),
      ],
    ),
  );
}

class HomeLocationDetails extends StatelessWidget {
  const HomeLocationDetails({
    super.key,
    required this.model,
    this.showMap = false,
  });
  final AppModel model;
  final bool showMap;
  @override
  Widget build(BuildContext context) {
    final status = model.phoneStatus;
    final lat = status['homeLat'] as num?, lng = status['homeLng'] as num?;
    final address = status['homeAddress'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_on_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                address?.isNotEmpty == true
                    ? address!
                    : model.homeAddressLoading
                    ? 'Looking up the address…'
                    : 'Saved home point',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        if (showMap && lat != null && lng != null)
          TextButton.icon(
            onPressed: () => model.run(model.phone.viewHome),
            icon: const Icon(Icons.map_outlined),
            label: const Text('View in Maps'),
          ),
      ],
    );
  }
}

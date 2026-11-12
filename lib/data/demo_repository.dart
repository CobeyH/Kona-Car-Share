import 'repository.dart';

class DemoRepository extends Repository {
  DemoRepository() {
    ready = true;
    tripsReady = true;
    user = {'id': 'alex', 'name': 'Alex'};
    group = {
      'id': 'demo',
      'name': 'The Kona house',
      'lastOdometer': 42816,
      'activeTripId': null,
      'spliitGroupId': '',
      'spliitMembers': [],
      'ownerMemberId': '',
    };
    members = [
      {'id': 'cobey', 'name': 'Cobey', 'role': 'owner', 'spliitMemberId': ''},
      {
        'id': 'natalie',
        'name': 'Natalie',
        'role': 'owner',
        'spliitMemberId': '',
      },
      {'id': 'alex', 'name': 'Alex', 'role': 'borrower', 'spliitMemberId': ''},
    ];
    final start = DateTime.now().subtract(const Duration(minutes: 30));
    bookings = [
      {
        'id': 'sample-approved',
        'userId': 'alex',
        'driver': 'Alex',
        'startAt': start.toIso8601String(),
        'endAt': start.add(const Duration(hours: 2)).toIso8601String(),
        'estimatedKm': 30,
        'note': 'Groceries and a few errands',
        'status': 'approved',
        'decisionNote': '',
      },
      {
        'id': 'sample-request',
        'userId': 'alex',
        'driver': 'Alex',
        'startAt': start.add(const Duration(days: 1)).toIso8601String(),
        'endAt': start.add(const Duration(days: 1, hours: 4)).toIso8601String(),
        'estimatedKm': 65,
        'note': 'An afternoon out',
        'status': 'requested',
        'decisionNote': '',
      },
    ];
  }
  @override
  bool get demo => true;
  @override
  Future<void> auth(String email, String password, String? name) async {}
  @override
  Future<void> googleAuth() async =>
      throw StateError('Connect Firebase to sign in with Google.');
  @override
  Future<void> signOut() async {
    user = null;
    group = null;
    notifyListeners();
  }

  @override
  Future<Json> command(String action, [Json data = const {}]) async {
    switch (action) {
      case 'demoRole':
        user = data['owner'] == true
            ? {'id': 'cobey', 'name': 'Cobey'}
            : {'id': 'alex', 'name': 'Alex'};
      case 'request':
        bookings = [
          {
            'id': randomCode(21),
            'userId': uid,
            'driver': user!['name'],
            ...data,
            'status': 'requested',
            'decisionNote': '',
          },
          ...bookings,
        ];
      case 'decision':
        final b = bookings.firstWhere((b) => b['id'] == data['id']);
        if (data['status'] == 'approved') {
          if (!owner) throw StateError('Only owners can approve.');
          final s = DateTime.parse(b['startAt']),
              e = DateTime.parse(b['endAt']);
          if (bookings.any(
            (other) =>
                other['id'] != b['id'] &&
                ['approved', 'active'].contains(other['status']) &&
                s.isBefore(DateTime.parse(other['endAt'])) &&
                e.isAfter(DateTime.parse(other['startAt'])),
          )) {
            throw StateError('That overlaps an approved booking.');
          }
        }
        b['status'] = data['status'];
        b['decisionNote'] = data['note'] ?? '';
      case 'start':
        if (group!['activeTripId'] != null) {
          throw StateError('There is already an active trip.');
        }
        final b = bookings.firstWhere((b) => b['id'] == data['id']);
        final id = randomCode(21);
        trips = [
          {
            'id': id,
            'bookingId': b['id'],
            'userId': uid,
            'driver': user!['name'],
            'startAt': DateTime.now().toIso8601String(),
            'startKm': data['km'],
            'status': 'active',
            'sync': 'local',
            'expenseId': '',
          },
          ...trips,
        ];
        group!['activeTripId'] = id;
        b['status'] = 'active';
      case 'finish':
        final t = trips.firstWhere((t) => t['id'] == data['id']);
        t.addAll({
          'endAt': data['endAt'],
          'endKm': data['km'],
          'status': 'completed',
        });
        bookings.firstWhere((b) => b['id'] == t['bookingId'])['status'] =
            'completed';
        group!['activeTripId'] = null;
        group!['lastOdometer'] = data['km'];
      case 'pendingFinish':
        return {};
      case 'invites':
        return {
          'ownerCode': 'Demo owner invite — connect Firebase to share',
          'borrowerCode': 'Demo borrower invite — connect Firebase to share',
        };
      case 'sync':
        throw StateError(
          'Preview trips stay on this device. Connect Firebase and Spliit for real expenses.',
        );
      default:
        throw StateError('Connect a Firebase project to use this feature.');
    }
    notifyListeners();
    return {};
  }
}

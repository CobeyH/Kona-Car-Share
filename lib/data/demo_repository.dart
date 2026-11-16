import 'repository.dart';
import '../domain/pricing.dart';
import '../domain/shared_ride.dart';
import '../domain/trip_start.dart';

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
      {'id': 'sam', 'name': 'Sam', 'role': 'borrower', 'spliitMemberId': ''},
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
            'riderIds': data['riderIds'] ?? [uid],
            'ownerClearances': <String, dynamic>{},
          },
          ...bookings,
        ];
      case 'decision':
      case 'fineByMe':
        final b = bookings.firstWhere((b) => b['id'] == data['id']);
        final fine = action == 'fineByMe';
        var status = data['status'] ?? 'requested';
        if (fine || status == 'approved' || status == 'denied') {
          if (!owner) throw StateError('Only owners can review a request.');
          if (b['status'] != 'requested') {
            throw StateError('This request has already changed.');
          }
        }
        final votes = Map<String, dynamic>.from(b['ownerClearances'] ?? {});
        if (fine) {
          votes[uid!] = DateTime.now().toIso8601String();
          status =
              members
                  .where((m) => m['role'] == 'owner')
                  .every((m) => votes.containsKey(m['id']))
              ? 'approved'
              : 'requested';
        }
        if (status == 'approved') {
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
        b['status'] = status;
        if (fine) b['ownerClearances'] = votes;
        b['decisionNote'] = data['note'] ?? '';
      case 'start':
        if (group!['activeTripId'] != null) {
          throw StateError('There is already an active trip.');
        }
        final b = bookings.firstWhere((b) => b['id'] == data['id']);
        if (b['userId'] != uid || b['status'] != 'approved') {
          throw StateError('An approved request is needed first.');
        }
        final now = DateTime.now();
        if (!canStartTrip(
          bookedStart: DateTime.parse(b['startAt']),
          bookedEnd: DateTime.parse(b['endAt']),
          now: now,
        )) {
          throw StateError(
            'You can start up to 1 hour before the booked start, and before the booked return time.',
          );
        }
        final id = randomCode(21);
        trips = [
          {
            'id': id,
            'bookingId': b['id'],
            'riderIds': rideUserIds(b),
            'userId': uid,
            'driver': user!['name'],
            'startAt': now.toIso8601String(),
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
      case 'editTrip':
      case 'deleteTrip':
      case 'restoreTrip':
        if (!owner) throw StateError('Only an owner can change a trip.');
        final t = trips.firstWhere((t) => t['id'] == data['id']);
        if (t['changeId'] != data['expectedChangeId']) {
          throw StateError('This trip has changed. Reopen it.');
        }
        final oldStatus = t['status'];
        if (action == 'editTrip') {
          KonaPricing.calculate(
            start: DateTime.parse(data['startAt']),
            end: DateTime.parse(data['endAt']),
            km: data['endKm'] - data['startKm'],
          );
          t.addAll({
            'startAt': data['startAt'],
            'endAt': data['endAt'],
            'startKm': data['startKm'],
            'endKm': data['endKm'],
            'status': 'completed',
          });
          if (oldStatus == 'active') group!['lastOdometer'] = data['endKm'];
        } else if (action == 'deleteTrip') {
          t.addAll({'status': 'deleted', 'deletedFrom': oldStatus});
        } else {
          if (t['deletedFrom'] == 'active' && group!['activeTripId'] != null) {
            throw StateError('Another trip is active.');
          }
          t['status'] = t['deletedFrom'];
        }
        if (group!['activeTripId'] == t['id'] && t['status'] != 'active') {
          group!['activeTripId'] = null;
        }
        if (t['status'] == 'active') group!['activeTripId'] = t['id'];
        bookings.firstWhere((b) => b['id'] == t['bookingId'])['status'] =
            t['status'] == 'deleted' ? 'cancelled' : t['status'];
        t.addAll({
          'editedBy': uid,
          'editedByName': user!['name'],
          'editedAt': DateTime.now().toIso8601String(),
          'editReason': data['reason'] ?? '',
          'changeId': randomCode(21),
        });
        notifyListeners();
        return {};
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

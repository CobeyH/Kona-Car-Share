import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'spliit_service.dart';
import '../domain/pricing.dart';
import '../domain/shared_ride.dart';

typedef Json = Map<String, dynamic>;
String randomCode([int length = 32]) {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
  final r = Random.secure();
  return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
}

dynamic clean(dynamic value) {
  if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), clean(v)));
  }
  if (value is List) return value.map(clean).toList();
  return value;
}

abstract class Repository extends ChangeNotifier {
  bool get demo;
  bool ready = false;
  bool tripsReady = false;
  String? problem;
  Json? user, group;
  List<Json> members = [], bookings = [], trips = [];
  String? get uid => user?['id'];
  Json? get me => members.where((m) => m['id'] == uid).firstOrNull;
  bool get owner => me?['role'] == 'owner';
  Future<void> auth(String email, String password, String? name);
  Future<void> googleAuth();
  Future<void> signOut();
  Future<Json> command(String name, [Json data = const {}]);
}

class FirebaseRepository extends Repository {
  FirebaseRepository(this.preferences) {
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_account);
  }
  final SharedPreferences preferences;
  final db = FirebaseFirestore.instance;
  final spliit = SpliitService();
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Json>>? _profileSub;
  final List<StreamSubscription> _groupSubs = [];
  String? _groupId;
  bool _syncing = false;
  static Future<void>? _googleInitialization;
  @override
  bool get demo => false;
  DocumentReference<Json> get groupRef =>
      db.collection('groups').doc(_groupId!);
  Json doc(QueryDocumentSnapshot<Json> d) => {
    'id': d.id,
    ...clean(d.data()) as Json,
  };
  void fail(Object e) {
    problem =
        'Could not load shared data. Check your connection and Firebase setup.';
    notifyListeners();
  }

  Future<void> _account(User? account) async {
    await _profileSub?.cancel();
    for (final s in _groupSubs) {
      await s.cancel();
    }
    _groupSubs.clear();
    _groupId = null;
    tripsReady = false;
    group = null;
    members = [];
    bookings = [];
    trips = [];
    user = account == null
        ? null
        : {
            'id': account.uid,
            'name': account.displayName ?? account.email ?? 'Roommate',
          };
    ready = account == null;
    notifyListeners();
    if (account == null) return;
    _profileSub = db.collection('users').doc(account.uid).snapshots().listen((
      snapshot,
    ) {
      if (!snapshot.exists) return;
      ready = true;
      user = {'id': account.uid, ...snapshot.data()!};
      final id = snapshot.data()!['groupId'] as String?;
      if (id != _groupId) _listenGroup(id);
      notifyListeners();
    }, onError: fail);
    final ref = db.collection('users').doc(account.uid);
    try {
      final profile = await ref.get();
      if (!profile.exists) {
        await ref.set({
          'name': account.displayName ?? account.email ?? 'Roommate',
          'groupId': null,
        });
      }
    } catch (e) {
      fail(e);
    }
  }

  void _listenGroup(String? id) {
    for (final s in _groupSubs) {
      unawaited(s.cancel());
    }
    _groupSubs.clear();
    _groupId = id;
    tripsReady = false;
    group = null;
    members = [];
    bookings = [];
    trips = [];
    if (id == null) return;
    _groupSubs.add(
      groupRef.snapshots().listen((s) {
        if (s.exists) group = {'id': s.id, ...clean(s.data()) as Json};
        problem = null;
        notifyListeners();
      }, onError: fail),
    );
    _groupSubs.add(
      groupRef.collection('members').snapshots().listen((s) {
        members = s.docs.map(doc).toList();
        notifyListeners();
      }, onError: fail),
    );
    _groupSubs.add(
      groupRef
          .collection('bookings')
          .orderBy('startAt', descending: true)
          .limit(200)
          .snapshots()
          .listen((s) {
            bookings = s.docs.map(doc).toList();
            notifyListeners();
          }, onError: fail),
    );
    _groupSubs.add(
      groupRef
          .collection('trips')
          .orderBy('startAt', descending: true)
          .limit(200)
          .snapshots()
          .listen((s) {
            trips = s.docs
                .where((d) => d.data()['startAt'] is Timestamp)
                .map(doc)
                .toList();
            tripsReady = true;
            notifyListeners();
          }, onError: fail),
    );
  }

  @override
  Future<void> auth(String email, String password, String? name) async {
    final a = FirebaseAuth.instance;
    if (name == null) {
      await a.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } else {
      final result = await a.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await result.user!.updateDisplayName(name.trim());
      final ref = db.collection('users').doc(result.user!.uid);
      await ref.set({'name': name.trim(), 'groupId': null});
    }
  }

  @override
  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!kIsWeb && _googleInitialization != null) {
      try {
        await _googleInitialization;
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
  }

  @override
  Future<void> googleAuth() async {
    if (kIsWeb) {
      await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      return;
    }
    const clientId = String.fromEnvironment('FIREBASE_GOOGLE_CLIENT_ID');
    if (clientId.isEmpty) {
      throw StateError(
        'Google sign-in needs the web OAuth client ID in this build’s Firebase configuration.',
      );
    }
    final google = GoogleSignIn.instance;
    await (_googleInitialization ??= google.initialize(
      serverClientId: clientId,
    ));
    try {
      final account = await google.authenticate();
      final token = account.authentication.idToken;
      if (token == null) {
        throw StateError(
          'Google did not return a sign-in token. Please try again.',
        );
      }
      await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(idToken: token),
      );
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) rethrow;
    }
  }

  @override
  Future<Json> command(String action, [Json data = const {}]) async {
    final u = uid;
    if (u == null) throw StateError('Sign in first.');
    final profile = db.collection('users').doc(u);
    switch (action) {
      case 'createGroup':
        final ref = db.collection('groups').doc();
        final ownerCode = randomCode(), borrowerCode = randomCode();
        await db.runTransaction((tx) async {
          final p = await tx.get(profile);
          if (p.data()?['groupId'] != null) {
            throw StateError('You already belong to a group.');
          }
          tx.set(ref, {
            'name': data['name'],
            'createdBy': u,
            'ownerRosterVersion': 0,
            'createdAt': FieldValue.serverTimestamp(),
            'timeZone': 'America/Vancouver',
            'activeTripId': null,
            'lastOdometer': null,
            'schedule': {},
            'spliitGroupId': '',
            'spliitName': '',
            'spliitMembers': [],
            'spliitMemberIds': [],
            'ownerMemberId': '',
          });
          tx.set(ref.collection('members').doc(u), {
            'uid': u,
            'name': user!['name'],
            'role': 'owner',
            'spliitMemberId': '',
          });
          tx.update(profile, {'groupId': ref.id});
          tx.set(db.collection('invites').doc(ownerCode), {
            'groupId': ref.id,
            'role': 'owner',
          });
          tx.set(db.collection('invites').doc(borrowerCode), {
            'groupId': ref.id,
            'role': 'borrower',
          });
          tx.set(ref.collection('private').doc('invites'), {
            'ownerCode': ownerCode,
            'borrowerCode': borrowerCode,
          });
        });
        return {};
      case 'joinGroup':
        final code = (data['code'] as String).trim();
        if (!RegExp(r'^[A-Za-z0-9_-]{32}$').hasMatch(code)) {
          throw StateError('Paste the full invitation code.');
        }
        await db.runTransaction((tx) async {
          final p = await tx.get(profile);
          final invitation = await tx.get(db.collection('invites').doc(code));
          if (p.data()?['groupId'] != null) {
            throw StateError('You already belong to a group.');
          }
          if (!invitation.exists) {
            throw StateError(
              'Invitation not found. Ask an owner for a current code.',
            );
          }
          final g = db.collection('groups').doc(invitation.data()!['groupId']);
          tx.set(db.collection('joinProofs').doc(u), {
            'code': code,
            'groupId': g.id,
          });
          if (invitation.data()!['role'] == 'owner') {
            // Invalidate concurrent consensus reviews when the owner roster changes.
            tx.update(g, {'ownerRosterVersion': FieldValue.increment(1)});
          }
          tx.set(g.collection('members').doc(u), {
            'uid': u,
            'name': user!['name'],
            'role': invitation.data()!['role'],
            'spliitMemberId': '',
          });
          tx.update(profile, {'groupId': g.id});
        });
        return {};
      case 'invites':
        return (await groupRef.collection('private').doc('invites').get())
            .data()!;
      case 'rotateInvites':
        await db.runTransaction((tx) async {
          final ref = groupRef.collection('private').doc('invites');
          final old = (await tx.get(ref)).data()!;
          final ownerCode = randomCode(), borrowerCode = randomCode();
          tx.delete(db.collection('invites').doc(old['ownerCode']));
          tx.delete(db.collection('invites').doc(old['borrowerCode']));
          tx.set(db.collection('invites').doc(ownerCode), {
            'groupId': _groupId,
            'role': 'owner',
          });
          tx.set(db.collection('invites').doc(borrowerCode), {
            'groupId': _groupId,
            'role': 'borrower',
          });
          tx.set(ref, {'ownerCode': ownerCode, 'borrowerCode': borrowerCode});
        });
        return await command('invites');
      case 'request':
        final riders = List<String>.from(data['riderIds'] ?? [u]);
        if (riders.isEmpty ||
            riders.first != u ||
            riders.length > 5 ||
            riders.toSet().length != riders.length) {
          throw StateError(
            'Choose up to five distinct borrowers, including yourself.',
          );
        }
        await groupRef.collection('bookings').add({
          'userId': u,
          'driver': user!['name'],
          'riderIds': riders,
          'ownerClearances': <String, dynamic>{},
          'startAt': Timestamp.fromDate(DateTime.parse(data['startAt'])),
          'endAt': Timestamp.fromDate(DateTime.parse(data['endAt'])),
          'estimatedKm': data['estimatedKm'],
          'note': data['note'] ?? '',
          'status': 'requested',
          'decisionNote': '',
          'createdAt': FieldValue.serverTimestamp(),
        });
        return {};
      case 'decision':
      case 'fineByMe':
        final ref = groupRef.collection('bookings').doc(data['id']);
        await db.runTransaction((tx) async {
          final g = (await tx.get(groupRef)).data()!;
          final booking = (await tx.get(ref)).data()!;
          final schedule = Map<String, dynamic>.from(g['schedule'] ?? {});
          final fine = action == 'fineByMe';
          var status = data['status'] as String? ?? 'requested';
          final clearances = Map<String, dynamic>.from(
            booking['ownerClearances'] ?? {},
          );
          List<String>? currentOwners;
          if (fine || status == 'approved' || status == 'denied') {
            if (!owner) throw StateError('Only owners can review a request.');
            if (booking['status'] != 'requested') {
              throw StateError('This request has already changed.');
            }
          }
          if (fine) {
            // This query is repeated on every transaction retry. Owner joins
            // also write the group, so a concurrent join invalidates this read.
            final roster = await groupRef
                .collection('members')
                .where('role', isEqualTo: 'owner')
                .get(const GetOptions(source: Source.server));
            currentOwners = roster.docs.map((d) => d.id).toList();
            if (!currentOwners.contains(u)) {
              throw StateError('Only owners can review a request.');
            }
            clearances[u] = FieldValue.serverTimestamp();
            status = currentOwners.every(clearances.containsKey)
                ? 'approved'
                : 'requested';
          }
          if (status == 'approved') {
            final start =
                (booking['startAt'] as Timestamp).millisecondsSinceEpoch;
            final end = (booking['endAt'] as Timestamp).millisecondsSinceEpoch;
            final stale = <String>[];
            for (final entry in schedule.entries) {
              if (entry.key == ref.id) continue;
              final other = (await tx.get(
                groupRef.collection('bookings').doc(entry.key),
              )).data();
              if (other == null ||
                  !['approved', 'active'].contains(other['status'])) {
                stale.add(entry.key);
                continue;
              }
              if (start < entry.value['end'] && end > entry.value['start']) {
                throw StateError('That overlaps an approved booking.');
              }
            }
            for (final key in stale) {
              schedule.remove(key);
            }
            schedule[ref.id] = {'start': start, 'end': end};
          } else if (owner && !fine) {
            schedule.remove(ref.id);
          }
          tx.update(ref, {
            'status': status,
            'decisionNote': data['note'] ?? '',
            if (fine) 'ownerClearances.$u': FieldValue.serverTimestamp(),
          });
          if (owner) tx.update(groupRef, {'schedule': schedule});
        });
        return {};
      case 'start':
        final id = randomCode(21);
        final bookingRef = groupRef.collection('bookings').doc(data['id']);
        await db.runTransaction((tx) async {
          final g = (await tx.get(groupRef)).data()!;
          final b = (await tx.get(bookingRef)).data()!;
          if (g['activeTripId'] != null) {
            throw StateError('The car already has an active trip.');
          }
          if (b['userId'] != u || b['status'] != 'approved') {
            throw StateError('An approved request is needed first.');
          }
          final now = DateTime.now();
          if (now.isBefore((b['startAt'] as Timestamp).toDate()) ||
              !now.isBefore((b['endAt'] as Timestamp).toDate())) {
            throw StateError(
              'Start the trip within its approved booking time. Ask an owner if your plans have changed.',
            );
          }
          tx.set(groupRef.collection('trips').doc(id), {
            'userId': u,
            'driver': user!['name'],
            'riderIds': rideUserIds(b),
            'borrowerIds': <String>[],
            'bookingId': bookingRef.id,
            'startAt': FieldValue.serverTimestamp(),
            'startKm': data['km'],
            'endAt': null,
            'endKm': null,
            'status': 'active',
            'sync': 'local',
            'expenseId': '',
            'remoteGroupId': '',
            'payerId': '',
            'borrowerId': '',
          });
          tx.update(bookingRef, {'status': 'active'});
          tx.update(groupRef, {'activeTripId': id});
        });
        return {'id': id};
      case 'finish':
        // Save the actual reading and time first. A failed/offline finish is
        // recoverable after restarting and never silently moves the end time.
        await preferences.setString('finish_${_groupId}_$u', jsonEncode(data));
        final ref = groupRef.collection('trips').doc(data['id']);
        await db
            .runTransaction((tx) async {
              final t = (await tx.get(ref)).data()!;
              final g = (await tx.get(groupRef)).data()!;
              if (t['status'] == 'completed') return;
              final schedule = Map<String, dynamic>.from(g['schedule'] ?? {})
                ..remove(t['bookingId']);
              tx.update(ref, {
                'status': 'completed',
                'endAt': Timestamp.fromDate(DateTime.parse(data['endAt'])),
                'endKm': data['km'],
              });
              tx.update(groupRef.collection('bookings').doc(t['bookingId']), {
                'status': 'completed',
              });
              tx.update(groupRef, {
                'activeTripId': null,
                'lastOdometer': data['km'],
                'schedule': schedule,
              });
            })
            .timeout(const Duration(seconds: 20));
        await preferences.remove('finish_${_groupId}_$u');
        return {};
      case 'pendingFinish':
        final saved = preferences.getString('finish_${_groupId}_$u');
        if (saved == null) return {};
        final draft = jsonDecode(saved) as Json;
        if (trips.any(
          (t) => t['id'] == draft['id'] && t['status'] != 'active',
        )) {
          await preferences.remove('finish_${_groupId}_$u');
          return {};
        }
        return draft;
      case 'spliitPreview':
        return await spliit.group(data['url']);
      case 'spliitConnect':
        if (data['confirmedCad'] != true) {
          throw StateError('Confirm this group uses Canadian dollars.');
        }
        final remote = await spliit.group(data['url']);
        if (!(remote['participants'] as List).any(
          (m) => m['id'] == data['ownerId'],
        )) {
          throw StateError('Choose the owner in Spliit.');
        }
        await groupRef.update({
          'spliitGroupId': SpliitService.groupId(data['url']),
          'spliitName': remote['name'],
          'spliitMemberIds': (remote['participants'] as List)
              .map((m) => m['id'])
              .toList(),
          'ownerMemberId': data['ownerId'],
          'spliitMembers': (remote['participants'] as List)
              .map((m) => {'id': m['id'], 'name': m['name']})
              .toList(),
        });
        return {};
      case 'spliitMap':
        final memberRef = groupRef.collection('members').doc(u);
        final claimRef = groupRef
            .collection('spliitClaims')
            .doc(data['memberId']);
        await db.runTransaction((tx) async {
          final member = (await tx.get(memberRef)).data()!;
          final claim = await tx.get(claimRef);
          if (claim.exists && claim.data()!['uid'] != u) {
            throw StateError(
              'That Spliit participant is already linked to another roommate.',
            );
          }
          final old = member['spliitMemberId'] as String;
          if (old == data['memberId']) return;
          if (old.isNotEmpty) {
            tx.delete(groupRef.collection('spliitClaims').doc(old));
          }
          tx.set(claimRef, {'uid': u});
          tx.update(memberRef, {'spliitMemberId': data['memberId']});
        });
        return {};
      case 'editTrip':
      case 'deleteTrip':
      case 'restoreTrip':
        return {'needsLedger': await _ownerChange(action, data)};
      case 'syncCorrection':
        await _syncCorrection(data['id']);
        return {};
      case 'sync':
        await _sync(data['id']);
        return {};
      default:
        throw StateError('Unknown action.');
    }
  }

  Future<bool> _ownerChange(String action, Json data) async {
    if (!owner) throw StateError('Only an owner can change a trip.');
    final ref = groupRef.collection('trips').doc(data['id']);
    final revision = randomCode(21);
    var needsLedger = false;
    await db.runTransaction((tx) async {
      final trip = (await tx.get(ref)).data()!;
      final g = (await tx.get(groupRef)).data()!;
      final bookingRef = groupRef.collection('bookings').doc(trip['bookingId']);
      final booking = (await tx.get(bookingRef)).data()!;
      if (trip['changeId'] != data['expectedChangeId']) {
        throw StateError('This trip has changed. Reopen it before editing.');
      }
      if (trip['ledgerState'] == 'sending') {
        throw StateError(
          'A Spliit correction is in progress. Check Spliit first, then try again.',
        );
      }
      final patch = <String, dynamic>{
        'changeId': revision,
        'editedBy': uid,
        'editedByName': user!['name'],
        'editedAt': FieldValue.serverTimestamp(),
        'editReason': data['reason'] ?? '',
      };
      final groupPatch = <String, dynamic>{};
      final schedule = Map<String, dynamic>.from(g['schedule'] ?? {});
      String state;
      if (action == 'editTrip') {
        if (!['active', 'completed'].contains(trip['status'])) {
          throw StateError('Restore this trip before editing it.');
        }
        final start = DateTime.parse(data['startAt']),
            end = DateTime.parse(data['endAt']);
        final startKm = data['startKm'] as int, endKm = data['endKm'] as int;
        if (startKm < 0 ||
            endKm < startKm ||
            end.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
          throw StateError('Check the times and odometer readings.');
        }
        KonaPricing.calculate(start: start, end: end, km: endKm - startKm);
        patch.addAll({
          'startAt': Timestamp.fromDate(start),
          'endAt': Timestamp.fromDate(end),
          'startKm': startKm,
          'endKm': endKm,
          'status': 'completed',
        });
        state = 'completed';
        if (trip['status'] == 'active' ||
            (g['activeTripId'] == null && g['lastOdometer'] == trip['endKm'])) {
          groupPatch['lastOdometer'] = endKm;
        }
      } else if (action == 'deleteTrip') {
        if (trip['status'] == 'deleted') {
          throw StateError('This trip is already deleted.');
        }
        state = 'deleted';
        patch.addAll({'status': state, 'deletedFrom': trip['status']});
      } else {
        if (trip['status'] != 'deleted') {
          throw StateError('This trip is not deleted.');
        }
        state = trip['deletedFrom'] as String;
        if (state == 'active' && g['activeTripId'] != null) {
          throw StateError(
            'Another trip is active. Finish it before restoring this one.',
          );
        }
        patch['status'] = state;
      }
      if (state == 'active') {
        groupPatch['activeTripId'] = ref.id;
        schedule[trip['bookingId']] = {
          'start': (booking['startAt'] as Timestamp).millisecondsSinceEpoch,
          'end': (booking['endAt'] as Timestamp).millisecondsSinceEpoch,
        };
      } else {
        schedule.remove(trip['bookingId']);
        if (g['activeTripId'] == ref.id) groupPatch['activeTripId'] = null;
      }
      groupPatch['schedule'] = schedule;
      final remote = trip['remoteGroupId'] as String? ?? '';
      needsLedger = remote.isNotEmpty;
      if (remote.isNotEmpty) {
        patch.addAll({
          'ledgerAction': state == 'deleted'
              ? 'delete'
              : action == 'restoreTrip'
              ? 'restore'
              : 'update',
          'ledgerState': 'pending',
          'ledgerCreateStarted': false,
        });
      }
      tx.set(ref.collection('changes').doc(revision), {
        'actorId': uid,
        'actorName': user!['name'],
        'action': action,
        'at': FieldValue.serverTimestamp(),
        'reason': data['reason'] ?? '',
        'before': trip,
      });
      tx.update(ref, patch);
      tx.update(bookingRef, {
        'status': state == 'deleted' ? 'cancelled' : state,
      });
      tx.update(groupRef, groupPatch);
    });
    return needsLedger;
  }

  Future<void> _syncCorrection(String id) async {
    if (!owner) throw StateError('Only an owner can synchronize a correction.');
    if (_syncing) return;
    _syncing = true;
    final ref = groupRef.collection('trips').doc(id);
    String? revision;
    try {
      late Json trip;
      await db.runTransaction((tx) async {
        final raw = (await tx.get(ref)).data()!;
        trip = {'id': id, ...clean(raw) as Json};
        if (trip['ledgerState'] == 'done') return;
        final claimedAt = raw['ledgerClaimedAt'] as Timestamp?;
        if (trip['ledgerState'] == 'sending' &&
            claimedAt != null &&
            DateTime.now().difference(claimedAt.toDate()) <
                const Duration(seconds: 90)) {
          throw StateError(
            'This correction is already being sent. Try checking again shortly.',
          );
        }
        revision = trip['changeId'];
        tx.update(ref, {
          'ledgerState': 'sending',
          'ledgerClaimedAt': FieldValue.serverTimestamp(),
        });
      });
      if (revision == null) return;
      final remote = trip['remoteGroupId'] as String;
      final existing = await spliit.findLinked(remote, trip);
      String expenseId = existing ?? trip['expenseId'] ?? '';
      if (trip['ledgerAction'] == 'delete') {
        if (existing != null) {
          await spliit.delete(remote, existing, trip['payerId']);
        } else if (['sending', 'uncertain'].contains(trip['sync'])) {
          throw StateError(
            'The earlier Spliit send needs a check before its removal can be confirmed.',
          );
        }
      } else if (existing != null) {
        await spliit.update(
          trip,
          remote,
          existing,
          trip['payerId'],
          trip['borrowerId'],
        );
      } else if (trip['ledgerAction'] == 'restore' &&
          trip['ledgerCreateStarted'] != true &&
          !['sending', 'uncertain'].contains(trip['sync'])) {
        // Persist this BEFORE creating. If interrupted, only reconcile the
        // matching expense; never blindly create a second copy.
        await ref.update({'ledgerCreateStarted': true});
        expenseId = await spliit.create(
          trip,
          remote,
          trip['payerId'],
          trip['borrowerId'],
        );
      } else {
        throw StateError(
          'No matching Spliit expense found yet. Check Spliit before continuing.',
        );
      }
      await db.runTransaction((tx) async {
        final current = (await tx.get(ref)).data()!;
        if (current['changeId'] != revision) return;
        tx.update(ref, {
          'ledgerState': 'done',
          'expenseId': expenseId,
          if (trip['ledgerAction'] != 'delete') 'sync': 'sent',
        });
      });
    } catch (_) {
      if (revision != null) {
        await db.runTransaction((tx) async {
          if ((await tx.get(ref)).data()?['changeId'] == revision) {
            tx.update(ref, {'ledgerState': 'uncertain'});
          }
        });
      }
      rethrow;
    } finally {
      _syncing = false;
    }
  }

  Future<void> _sync(String id) async {
    if (_syncing) return;
    _syncing = true;
    final ref = groupRef.collection('trips').doc(id);
    var canCreate = false;
    var attempted = false;
    try {
      late Json trip;
      late String remoteGroup, payer, borrower;
      await db.runTransaction((tx) async {
        final snapshot = await tx.get(ref);
        final settings = (await tx.get(groupRef)).data()!;
        trip = {'id': id, ...clean(snapshot.data()) as Json};
        final memberships = <Json>[];
        for (final rider in rideUserIds(trip)) {
          memberships.add(
            (await tx.get(groupRef.collection('members').doc(rider))).data()!,
          );
        }
        if ((trip['userId'] != uid && !owner) ||
            trip['status'] != 'completed') {
          throw StateError('Only your completed trips can be sent.');
        }
        if (['pending', 'sending', 'uncertain'].contains(trip['ledgerState'])) {
          throw StateError('Synchronize the owner’s correction first.');
        }
        remoteGroup = trip['remoteGroupId'] as String? ?? '';
        payer = trip['payerId'] as String? ?? '';
        borrower = trip['borrowerId'] as String? ?? '';
        final firstSend = remoteGroup.isEmpty;
        if (firstSend) {
          remoteGroup = settings['spliitGroupId'];
          payer = settings['ownerMemberId'];
          final mapped = memberships
              .map((m) => m['spliitMemberId'] as String? ?? '')
              .toList();
          if (mapped.any((id) => id.isEmpty || id == payer) ||
              mapped.toSet().length != mapped.length) {
            throw StateError(
              'Every borrower on the ride must link a different Spliit participant in House before this expense can be sent.',
            );
          }
          trip['borrowerIds'] = mapped;
          borrower = mapped.first;
        }
        if (remoteGroup.isEmpty ||
            payer.isEmpty ||
            borrower.isEmpty ||
            payer == borrower) {
          throw StateError(
            'Connect Spliit and choose your participant in House settings first.',
          );
        }
        canCreate = ['local', 'pending'].contains(trip['sync']);
        if (canCreate) {
          tx.update(ref, {
            'sync': 'sending',
            if (firstSend) ...{
              'remoteGroupId': remoteGroup,
              'payerId': payer,
              'borrowerId': borrower,
              'borrowerIds': trip['borrowerIds'],
            },
          });
        }
      });
      if (trip['sync'] == 'sent') return;
      final existing = await spliit.find(remoteGroup, id);
      if (existing != null) {
        await ref.update({'sync': 'sent', 'expenseId': existing});
        return;
      }
      if (!canCreate) {
        throw StateError(
          'No matching expense found yet. Check Spliit before creating anything manually; this app will not risk a duplicate.',
        );
      }
      attempted = true;
      final expense = await spliit.create(trip, remoteGroup, payer, borrower);
      await ref.update({'sync': 'sent', 'expenseId': expense});
    } catch (_) {
      if (canCreate) {
        await ref.update({'sync': attempted ? 'uncertain' : 'pending'});
      }
      rethrow;
    } finally {
      _syncing = false;
    }
  }

  @override
  void dispose() {
    unawaited(_authSub?.cancel());
    unawaited(_profileSub?.cancel());
    for (final s in _groupSubs) {
      unawaited(s.cancel());
    }
    super.dispose();
  }
}

Future<bool> initializeFirebase() async {
  const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
  const emulator = bool.fromEnvironment('USE_EMULATORS');
  if (project.isEmpty && !emulator) return false;
  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: const String.fromEnvironment(
        'FIREBASE_API_KEY',
        defaultValue: 'demo-api-key',
      ),
      appId: const String.fromEnvironment(
        'FIREBASE_APP_ID',
        defaultValue: '1:1234567890:android:demo',
      ),
      messagingSenderId: const String.fromEnvironment(
        'FIREBASE_SENDER_ID',
        defaultValue: '1234567890',
      ),
      authDomain:
          '${project.isEmpty ? 'demo-kona-share' : project}.firebaseapp.com',
      projectId: const String.fromEnvironment(
        'FIREBASE_PROJECT_ID',
        defaultValue: 'demo-kona-share',
      ),
    ),
  );
  if (emulator) {
    const host = String.fromEnvironment(
      'EMULATOR_HOST',
      defaultValue: '10.0.2.2',
    );
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  }
  return true;
}

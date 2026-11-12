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
        await groupRef.collection('bookings').add({
          'userId': u,
          'driver': user!['name'],
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
        final ref = groupRef.collection('bookings').doc(data['id']);
        await db.runTransaction((tx) async {
          final g = (await tx.get(groupRef)).data()!;
          final booking = (await tx.get(ref)).data()!;
          final schedule = Map<String, dynamic>.from(g['schedule'] ?? {});
          if (data['status'] == 'approved') {
            if (booking['status'] != 'requested') {
              throw StateError('This request has already changed.');
            }
            final start =
                (booking['startAt'] as Timestamp).millisecondsSinceEpoch;
            final end = (booking['endAt'] as Timestamp).millisecondsSinceEpoch;
            // Read each scheduled booking inside the transaction, so cancelled
            // requests are pruned and concurrent owner approvals retry safely.
            final stale = <String>[];
            for (final entry in schedule.entries) {
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
          } else if (owner) {
            schedule.remove(ref.id);
          }
          tx.update(ref, {
            'status': data['status'],
            'decisionNote': data['note'] ?? '',
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
        return saved == null ? {} : jsonDecode(saved) as Json;
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
      case 'sync':
        await _sync(data['id']);
        return {};
      default:
        throw StateError('Unknown action.');
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
        final membership = (await tx.get(
          groupRef.collection('members').doc(uid),
        )).data()!;
        trip = {'id': id, ...clean(snapshot.data()) as Json};
        if (trip['userId'] != uid || trip['status'] != 'completed') {
          throw StateError('Only your completed trips can be sent.');
        }
        remoteGroup = trip['remoteGroupId'] as String? ?? '';
        payer = trip['payerId'] as String? ?? '';
        borrower = trip['borrowerId'] as String? ?? '';
        final firstSend = remoteGroup.isEmpty;
        if (firstSend) {
          remoteGroup = settings['spliitGroupId'];
          payer = settings['ownerMemberId'];
          borrower = membership['spliitMemberId'];
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

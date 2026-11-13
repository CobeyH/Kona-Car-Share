import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../data/repository.dart';
import '../data/phone_service.dart';

class AppModel extends ChangeNotifier {
  AppModel(this.repository, this.phone) {
    repository.addListener(_changed);
    phone.onNotificationOpened(refreshPhone);
  }
  final Repository repository;
  final PhoneService phone;
  bool busy = false;
  String? message;
  Map<String, dynamic> phoneStatus = {};
  bool homeAddressLoading = false;
  String? _addressRequest;
  bool openTripRequested = false;
  Json? pendingFinish;
  final Set<String> _attempted = {};
  bool _autoWorking = false;
  String _syncConfiguration = '';
  String? _restoredGroup;
  String _phoneTrip = 'loading';
  bool _disposed = false;
  bool get owner => repository.owner;
  Json? get active => repository.trips
      .where((t) => t['status'] == 'active' && t['userId'] == repository.uid)
      .firstOrNull;
  List<Json> get completed =>
      repository.trips.where((t) => t['status'] == 'completed').toList();
  void _changed() {
    final config =
        '${repository.group?['spliitGroupId']}/${repository.group?['ownerMemberId']}/${repository.members.map((m) => '${m['id']}:${m['spliitMemberId']}').join(',')}';
    if (config != _syncConfiguration) {
      _syncConfiguration = config;
      _attempted.clear();
    }
    if (pendingFinish?.isNotEmpty == true &&
        repository.tripsReady &&
        repository.trips.any(
          (t) => t['id'] == pendingFinish!['id'] && t['status'] != 'active',
        )) {
      pendingFinish = null;
    }
    if (repository.tripsReady && repository.group != null) {
      final tripId = active?['id'] as String? ?? '';
      if (_phoneTrip != tripId) {
        _phoneTrip = tripId;
        unawaited(phone.reconcile(tripId.isNotEmpty).catchError((_) {}));
      }
      if (_restoredGroup != '${repository.group!['id']}/${repository.uid}') {
        _restoredGroup = '${repository.group!['id']}/${repository.uid}';
        pendingFinish = null;
        unawaited(
          repository
              .command('pendingFinish')
              .then((draft) {
                if (!_disposed) {
                  pendingFinish = draft;
                  notifyListeners();
                }
              })
              .catchError((_) {}),
        );
      }
      unawaited(_automaticSync());
    }
    notifyListeners();
  }

  Future<void> _automaticSync() async {
    if (_autoWorking ||
        busy ||
        repository.demo ||
        repository.group == null ||
        (repository.group!['spliitGroupId'] as String? ?? '').isEmpty ||
        (!owner &&
            (repository.me?['spliitMemberId'] as String? ?? '').isEmpty)) {
      return;
    }
    _autoWorking = true;
    try {
      if (owner) {
        for (final trip in repository.trips.where(
          (t) => t['ledgerState'] == 'pending',
        )) {
          final key = 'correction:${trip['id']}:${trip['changeId']}';
          if (_attempted.add(key)) {
            try {
              await repository.command('syncCorrection', {'id': trip['id']});
            } catch (_) {}
          }
        }
      }
      final pending = completed
          .where(
            (t) =>
                (owner || t['userId'] == repository.uid) &&
                ![
                  'pending',
                  'sending',
                  'uncertain',
                ].contains(t['ledgerState']) &&
                ['local', 'pending'].contains(t['sync']) &&
                !_attempted.contains(t['id']),
          )
          .toList();
      for (final t in pending) {
        _attempted.add(t['id']);
        try {
          await repository.command('sync', {'id': t['id']});
        } catch (_) {}
      }
    } finally {
      _autoWorking = false;
    }
  }

  Future<void> refreshPhone() async {
    _attempted.clear();
    try {
      phoneStatus = await phone.status();
      if (await phone.consumeTripOpen()) openTripRequested = true;
      final homeKey = '${phoneStatus['homeLat']}/${phoneStatus['homeLng']}';
      if (phoneStatus['homeSet'] == true &&
          (phoneStatus['homeAddress'] as String? ?? '').isEmpty &&
          _addressRequest != homeKey) {
        _addressRequest = homeKey;
        homeAddressLoading = true;
        unawaited(_loadHomeAddress(homeKey));
      }
    } catch (_) {
      phoneStatus = {};
    }
    if (repository.group != null) {
      try {
        pendingFinish = await repository.command('pendingFinish');
      } catch (_) {}
      try {
        if (repository.tripsReady) await phone.reconcile(active != null);
      } catch (_) {}
    }
    if (!_disposed) {
      notifyListeners();
      unawaited(_automaticSync());
    }
  }

  Future<void> _loadHomeAddress(String homeKey) async {
    String? address;
    try {
      address = await phone.homeAddress();
    } catch (_) {}
    if (_disposed ||
        '${phoneStatus['homeLat']}/${phoneStatus['homeLng']}' != homeKey) {
      return;
    }
    homeAddressLoading = false;
    if (address != null) phoneStatus = {...phoneStatus, 'homeAddress': address};
    notifyListeners();
  }

  void consumeTripScreenRequest() {
    openTripRequested = false;
  }

  String friendly(Object e) {
    if (e is FirebaseException) {
      return switch (e.code) {
        'permission-denied' => 'That action is not allowed for your account. Check your role or ask an owner.',
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' => 'Check your email and password.',
        'email-already-in-use' =>
          'That email already has an account. Try signing in.',
        'unavailable' || 'network-request-failed' => 'No connection. Your ending reading is saved on this phone if you were finishing a trip.',
        _ => e.message ?? 'Could not complete the action. Please try again.',
      };
    }
    if (e is TimeoutException) {
      return 'Connection timed out. Your ending reading is saved; use Retry saved finish when online.';
    }
    return e.toString().replaceFirst(
      RegExp(r'^(Bad state: |Invalid argument\(s\): |Exception: )'),
      '',
    );
  }

  Future<bool> run(Future<void> Function() work) async {
    if (busy) return false;
    busy = true;
    message = null;
    notifyListeners();
    try {
      await work();
      return true;
    } catch (e) {
      message = friendly(e);
      return false;
    } finally {
      busy = false;
      notifyListeners();
      unawaited(_automaticSync());
    }
  }

  Future<bool> action(String action, [Json data = const {}]) => run(() async {
    final result = await repository.command(action, data);
    if (result['needsLedger'] == true) {
      try {
        await repository.command('syncCorrection', {'id': data['id']});
      } catch (_) {
        message = 'Trip saved. Its Spliit correction still needs a check in Activity.';
      }
    }
    if (action == 'start') {
      try {
        await phone.notifications();
        message = await phone.startTrip();
      } catch (_) {
        message = 'Trip started. Home reminders need to be enabled in House settings.';
      }
    }
    if (action == 'finish') {
      try {
        await phone.endTrip();
      } catch (_) {}
      pendingFinish = null;
      if (!repository.demo &&
          repository.group?['spliitGroupId'] != '' &&
          repository.me?['spliitMemberId'] != '') {
        try {
          await repository.command('sync', {'id': data['id']});
        } catch (_) {
          message = 'Trip saved. Spliit still needs attention; check the trip in Activity.';
        }
      }
    }
  });
  void clearMessage() {
    message = null;
  }

  @override
  void dispose() {
    _disposed = true;
    phone.onNotificationOpened(null);
    repository.removeListener(_changed);
    super.dispose();
  }
}

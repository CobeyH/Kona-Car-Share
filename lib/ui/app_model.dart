import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../data/repository.dart';
import '../data/phone_service.dart';

class AppModel extends ChangeNotifier {
  AppModel(this.repository, this.phone) {
    repository.addListener(_changed);
  }
  final Repository repository;
  final PhoneService phone;
  bool busy = false;
  String? message;
  Map<String, dynamic> phoneStatus = {};
  Json? pendingFinish;
  final Set<String> _attempted = {};
  bool _autoWorking = false;
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
        (repository.me?['spliitMemberId'] as String? ?? '').isEmpty) {
      return;
    }
    _autoWorking = true;
    try {
      final pending = completed
          .where(
            (t) =>
                t['userId'] == repository.uid &&
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
    await repository.command(action, data);
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
    repository.removeListener(_changed);
    super.dispose();
  }
}

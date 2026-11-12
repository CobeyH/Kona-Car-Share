import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/pricing.dart';

class SpliitService {
  SpliitService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static String groupId(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'spliit.app' ||
        uri.pathSegments.length < 2 ||
        uri.pathSegments.first != 'groups' ||
        !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(uri.pathSegments[1])) {
      throw ArgumentError(
        'Paste a group link beginning https://spliit.app/groups/',
      );
    }
    return uri.pathSegments[1];
  }

  Future<Map<String, dynamic>> call(
    String procedure,
    Map<String, dynamic> input, {
    bool mutation = false,
  }) async {
    final envelope = jsonEncode({'json': input});
    final uri = Uri.https(
      'spliit.app',
      '/api/trpc/$procedure',
      mutation ? null : {'input': envelope},
    );
    final response =
        await (mutation
                ? _client.post(
                    uri,
                    headers: {'Content-Type': 'application/json'},
                    body: envelope,
                  )
                : _client.get(uri))
            .timeout(const Duration(seconds: 15));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['error'] != null) {
      throw StateError(
        'Spliit could not complete the request. Check the group link and connection.',
      );
    }
    return Map<String, dynamic>.from(body['result']['data']['json']);
  }

  Future<Map<String, dynamic>> group(String link) async {
    final data = await call('groups.get', {'groupId': groupId(link)});
    if (data['group'] == null) {
      throw StateError('That Spliit group was not found.');
    }
    final group = Map<String, dynamic>.from(data['group']);
    if (group['currencyCode'] != null && group['currencyCode'] != 'CAD') {
      throw StateError(
        'Use a Spliit group with Canadian dollars for the Kona rates.',
      );
    }
    return group;
  }

  Future<String?> find(String groupId, String tripId) async {
    var cursor = 0;
    for (var page = 0; page < 1000; page++) {
      final data = await call('groups.expenses.list', {
        'groupId': groupId,
        'cursor': cursor,
        'limit': 100,
      });
      for (final e in data['expenses'] as List) {
        if ((e['title'] as String).contains('[Kona:$tripId]')) return e['id'];
      }
      if (data['hasMore'] != true) return null;
      final next = data['nextCursor'];
      if (next is! int || next <= cursor) {
        throw StateError('Cannot safely check existing Spliit expenses.');
      }
      cursor = next;
    }
    throw StateError('Cannot safely check this very large Spliit group.');
  }

  Future<String> create(
    Map<String, dynamic> trip,
    String groupId,
    String ownerId,
    String borrowerId,
  ) async {
    final fare = KonaPricing.calculate(
      start: DateTime.parse(trip['startAt']),
      end: DateTime.parse(trip['endAt']),
      km: trip['endKm'] - trip['startKm'],
    );
    final result = await call('groups.expenses.create', {
      'groupId': groupId,
      'expenseId': trip['id'],
      'participantId': borrowerId,
      'expenseFormValues': {
        'title':
            'Kona · ${trip['endKm'] - trip['startKm']} km [Kona:${trip['id']}]',
        'expenseDate': DateTime.parse(trip['endAt']).toUtc().toIso8601String(),
        'amount': fare.totalCents,
        'category': 0,
        'paidBy': ownerId,
        'paidFor': [
          {'participant': borrowerId, 'shares': 100},
        ],
        'splitMode': 'EVENLY',
        'saveDefaultSplittingOptions': false,
        'isReimbursement': false,
        'originalCurrency': null,
        'documents': [],
        'recurrenceRule': 'NONE',
        'notes':
            '${trip['driver']} · Kona car use.\n'
            'Odometer ${trip['startKm']} → ${trip['endKm']} km.\n'
            '${trip['startAt']} to ${trip['endAt']}.\n'
            'Base: \$1; daily: \$${(fare.dailyCents / 100).toStringAsFixed(2)} '
            '(${fare.includedKm} km included); '
            'time: \$${(fare.timeCents / 100).toStringAsFixed(2)}; '
            'distance: \$${(fare.distanceCents / 100).toStringAsFixed(2)}; '
            'minimum adjustment: \$${(fare.minimumCents / 100).toStringAsFixed(2)}.\n'
            'Payable on the first of the following month. [Kona:${trip['id']}]',
      },
    }, mutation: true);
    if (result['expenseId'] is! String) {
      throw StateError('Spliit did not return an expense ID.');
    }
    return result['expenseId'];
  }
}

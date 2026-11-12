import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kona_share/data/spliit_service.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  setUpAll(tz.initializeTimeZones);
  test('expense payload credits the owner, charges only the borrower, and uses cents', () async {
    late Map<String, dynamic> input;
    final service = SpliitService(
      client: MockClient((request) async {
        expect(request.url.path, '/api/trpc/groups.expenses.create');
        expect(request.method, 'POST');
        input = jsonDecode(request.body)['json'];
        return http.Response(
          jsonEncode({
            'result': {
              'data': {
                'json': {'expenseId': 'remote-id'},
              },
            },
          }),
          200,
        );
      }),
    );
    final result = await service.create(
      {
        'id': 'trip-marker',
        'driver': 'Alex',
        'startKm': 42000,
        'endKm': 42030,
        'startAt': '2026-11-12T10:00:00-07:00',
        'endAt': '2026-11-12T12:00:00-07:00',
      },
      'group-id',
      'owner-id',
      'borrower-id',
    );
    expect(result, 'remote-id');
    final expense = input['expenseFormValues'];
    expect(expense['amount'], 1940);
    expect(expense['paidBy'], 'owner-id');
    expect(expense['paidFor'], [
      {'participant': 'borrower-id', 'shares': 100},
    ]);
    expect(expense['title'], contains('[Kona:trip-marker]'));
  });
  test(
    'reconciliation searches following pages before returning not found',
    () async {
      var count = 0;
      final service = SpliitService(
        client: MockClient((request) async {
          count++;
          final input = jsonDecode(
            request.url.queryParameters['input']!,
          )['json'];
          expect(input['cursor'], count == 1 ? 0 : 100);
          return http.Response(
            jsonEncode({
              'result': {
                'data': {
                  'json': {
                    'expenses': count == 1
                        ? []
                        : [
                            {'id': 'existing-id', 'title': 'Kona [Kona:trip]'},
                          ],
                    'hasMore': count == 1,
                    'nextCursor': count * 100,
                  },
                },
              },
            }),
            200,
          );
        }),
      );
      expect(await service.find('group', 'trip'), 'existing-id');
      expect(count, 2);
    },
  );
  test('rejects lookalike domains and non-HTTPS group links', () {
    expect(
      () => SpliitService.groupId('https://spliit.app.evil.test/groups/x'),
      throwsArgumentError,
    );
    expect(
      () => SpliitService.groupId('http://spliit.app/groups/x'),
      throwsArgumentError,
    );
    expect(
      SpliitService.groupId('https://spliit.app/groups/abc/expenses'),
      'abc',
    );
  });
}

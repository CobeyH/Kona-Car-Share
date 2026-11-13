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
  test('correction updates the linked expense and preserves receipts and notes', () async {
    final trip = <String, dynamic>{
      'id': 'trip',
      'driver': 'Alex',
      'startKm': 42000,
      'endKm': 42030,
      'startAt': '2026-11-12T10:00:00-07:00',
      'endAt': '2026-11-12T11:00:00-07:00',
    };
    final documents = [
      {
        'id': 'receipt',
        'url': 'https://example.com/receipt',
        'width': 400,
        'height': 600,
      },
    ];
    var mutations = 0;
    final service = SpliitService(
      client: MockClient((request) async {
        Map<String, dynamic> response;
        if (request.method == 'GET') {
          expect(request.url.path, '/api/trpc/groups.expenses.get');
          response = {
            'expense': {
              'title': 'Kona [Kona:trip]',
              'notes':
                  'Old generated details [Kona:trip]\nParking paid separately.',
              'categoryId': 3,
              'documents': documents,
            },
          };
        } else {
          mutations++;
          expect(request.url.path, '/api/trpc/groups.expenses.update');
          final input = jsonDecode(request.body)['json'];
          expect(input['expenseId'], 'linked');
          expect(input['participantId'], 'payer');
          final form = input['expenseFormValues'];
          expect(form['amount'], 1440);
          expect(form['category'], 3);
          expect(form['documents'], documents);
          expect(form['notes'], endsWith('Parking paid separately.'));
          expect(form['notes'], isNot(contains('Old generated details')));
          response = {'expenseId': 'linked'};
        }
        return http.Response(
          jsonEncode({
            'result': {
              'data': {'json': response},
            },
          }),
          200,
        );
      }),
    );
    await service.update(trip, 'group', 'linked', 'payer', 'borrower');
    expect(mutations, 1);
  });
  test('correction refuses an expense belonging to another trip', () async {
    var mutations = 0;
    final service = SpliitService(
      client: MockClient((request) async {
        if (request.method == 'POST') mutations++;
        return http.Response(
          jsonEncode({
            'result': {
              'data': {
                'json': {
                  'expense': {'title': 'Groceries', 'notes': 'Other expense'},
                },
              },
            },
          }),
          200,
        );
      }),
    );
    await expectLater(
      service.update(
        {
          'id': 'trip',
          'driver': 'Alex',
          'startKm': 1,
          'endKm': 2,
          'startAt': '2026-11-12T10:00:00Z',
          'endAt': '2026-11-12T11:00:00Z',
        },
        'group',
        'unrelated',
        'payer',
        'borrower',
      ),
      throwsStateError,
    );
    expect(mutations, 0);
  });
  test(
    'deleting a linked expense tolerates an already removed expense',
    () async {
      final service = SpliitService(
        client: MockClient((request) async {
          expect(request.url.path, '/api/trpc/groups.expenses.delete');
          expect(jsonDecode(request.body)['json'], {
            'groupId': 'group',
            'expenseId': 'expense',
            'participantId': 'payer',
          });
          return http.Response(
            jsonEncode({
              'error': {
                'json': {'message': 'Expense not found'},
              },
            }),
            404,
          );
        }),
      );
      await service.delete('group', 'expense', 'payer');
    },
  );
  test(
    'shared ride creates one expense with exact equal borrower amounts',
    () async {
      var creates = 0;
      final service = SpliitService(
        client: MockClient((request) async {
          creates++;
          expect(request.url.path, '/api/trpc/groups.expenses.create');
          final form = jsonDecode(request.body)['json']['expenseFormValues'];
          expect(form['amount'], 1940);
          expect(form['splitMode'], 'BY_AMOUNT');
          expect(form['paidBy'], 'payer');
          expect(form['paidFor'], [
            {'participant': 'alex', 'shares': 647},
            {'participant': 'sam', 'shares': 647},
            {'participant': 'jo', 'shares': 646},
          ]);
          return http.Response(
            jsonEncode({
              'result': {
                'data': {
                  'json': {'expenseId': 'one-shared-expense'},
                },
              },
            }),
            200,
          );
        }),
      );
      await service.create(
        {
          'id': 'shared',
          'driver': 'Alex',
          'startKm': 42000,
          'endKm': 42030,
          'startAt': '2026-11-12T10:00:00Z',
          'endAt': '2026-11-12T12:00:00Z',
          'borrowerIds': ['alex', 'sam', 'jo'],
        },
        'group',
        'payer',
        'alex',
      );
      expect(creates, 1);
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

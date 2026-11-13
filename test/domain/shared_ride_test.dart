import 'package:flutter_test/flutter_test.dart';
import 'package:kona_share/domain/shared_ride.dart';

void main() {
  test('legacy solo trips retain their only borrower', () {
    expect(rideUserIds({'userId': 'alex'}), ['alex']);
    expect(equalRideShares(600, ['alex']), {'alex': 600});
  });
  test('split sums to the fare and differs by no more than one cent', () {
    for (var count = 1; count <= 5; count++) {
      final ids = List.generate(count, (i) => 'borrower-$i');
      for (final total in [600, 601, 1940, 8100, 9500, 123456]) {
        final shares = equalRideShares(total, ids).values.toList();
        expect(shares.reduce((a, b) => a + b), total);
        expect(shares.first - shares.last, lessThanOrEqualTo(1));
      }
    }
    expect(equalRideShares(1940, ['alex', 'sam', 'jo']), {
      'alex': 647,
      'sam': 647,
      'jo': 646,
    });
  });
  test('duplicate borrowers and empty splits are rejected', () {
    expect(() => equalRideShares(600, []), throwsArgumentError);
    expect(() => equalRideShares(600, ['alex', 'alex']), throwsArgumentError);
  });
}

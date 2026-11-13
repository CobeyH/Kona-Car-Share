List<String> rideUserIds(Map<String, dynamic> ride) =>
    List<String>.from(ride['riderIds'] ?? [ride['userId']]);

Map<String, int> equalRideShares(int totalCents, List<String> ids) {
  if (totalCents < 0 || ids.isEmpty || ids.toSet().length != ids.length) {
    throw ArgumentError(
      'A nonnegative cost and distinct borrowers are required.',
    );
  }
  final each = totalCents ~/ ids.length, extra = totalCents % ids.length;
  return {
    for (var i = 0; i < ids.length; i++) ids[i]: each + (i < extra ? 1 : 0),
  };
}

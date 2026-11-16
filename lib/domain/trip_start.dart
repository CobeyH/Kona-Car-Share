const earlyStartAllowance = Duration(hours: 1);

bool canStartTrip({
  required DateTime bookedStart,
  required DateTime bookedEnd,
  required DateTime now,
}) =>
    !now.isBefore(bookedStart.subtract(earlyStartAllowance)) &&
    now.isBefore(bookedEnd);

import 'package:cloud_firestore/cloud_firestore.dart';

import 'employee_utils.dart';

/// Leave accrues at 1 day per eligible calendar month (max 12 per Apr–Mar cycle).
const double leaveAccrualPerMonth = 1.0;
/// Join on or before this day of the month → that month accrues 1 leave.
const int leaveJoinAccrualCutoffDay = 5;

int countLeaveDays(DateTime start, DateTime end) {
  final s = normalizeDate(start);
  final e = normalizeDate(end);
  return e.difference(s).inDays + 1;
}

/// Leave year starting April [startYear] → March [startYear + 1].
class LeaveCycle {
  final int startYear;

  const LeaveCycle(this.startYear);

  DateTime get start => DateTime(startYear, 4, 1);

  DateTime get end => DateTime(startYear + 1, 3, 31);

  String get label => '$startYear-${(startYear + 1) % 100}';

  bool contains(DateTime date) {
    final d = normalizeDate(date);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  static LeaveCycle containing(DateTime date) {
    if (date.month >= 4) return LeaveCycle(date.year);
    return LeaveCycle(date.year - 1);
  }

  static List<LeaveCycle> recentCycles({int count = 5}) {
    final current = LeaveCycle.containing(DateTime.now());
    return List.generate(
      count,
      (index) => LeaveCycle(current.startYear - index),
    );
  }
}

DateTime _monthEnd(int year, int month) =>
    DateTime(year, month + 1, 0);

DateTime _nextMonthStart(DateTime monthStart) =>
    DateTime(monthStart.year, monthStart.month + 1, 1);

/// Months counted for accrual within [cycle], up to [asOf].
/// Join on or before the 5th of a month → that month counts.
int countAccruedLeaveMonths({
  required LeaveCycle cycle,
  required DateTime? joinDate,
  required DateTime? resignedDate,
  required DateTime asOf,
}) {
  final effectiveAsOf = normalizeDate(
    asOf.isAfter(cycle.end) ? cycle.end : asOf,
  );
  if (effectiveAsOf.isBefore(cycle.start)) return 0;

  var monthCursor = cycle.start;
  var count = 0;

  while (!monthCursor.isAfter(
    DateTime(effectiveAsOf.year, effectiveAsOf.month, 1),
  )) {
    if (_isMonthEligibleForAccrual(
      monthCursor,
      joinDate: joinDate,
      resignedDate: resignedDate,
    )) {
      count++;
    }
    if (monthCursor.month == 3 && monthCursor.year == cycle.end.year) {
      break;
    }
    monthCursor = _nextMonthStart(monthCursor);
  }

  return count;
}

bool _isMonthEligibleForAccrual(
  DateTime monthStart, {
  required DateTime? joinDate,
  required DateTime? resignedDate,
}) {
  final monthEnd = _monthEnd(monthStart.year, monthStart.month);

  if (joinDate != null) {
    final join = normalizeDate(joinDate);
    if (join.isAfter(monthEnd)) return false;
    if (join.year == monthStart.year && join.month == monthStart.month) {
      return join.day <= leaveJoinAccrualCutoffDay;
    }
  }

  if (resignedDate != null) {
    final resigned = normalizeDate(resignedDate);
    if (!resigned.isBefore(monthStart)) {
      // Still employed at some point this month — count it.
    } else {
      return false;
    }
  }

  return true;
}

double accruedLeaveDays({
  required LeaveCycle cycle,
  required DateTime? joinDate,
  required DateTime? resignedDate,
  required DateTime asOf,
}) {
  final months = countAccruedLeaveMonths(
    cycle: cycle,
    joinDate: joinDate,
    resignedDate: resignedDate,
    asOf: asOf,
  );
  return double.parse(
    (months * leaveAccrualPerMonth).toStringAsFixed(1),
  );
}

double openingBalanceForCycle(
  Map<String, dynamic> employee,
  LeaveCycle cycle,
) {
  final balances = employee['leaveOpeningBalances'];
  if (balances is Map) {
    final raw = balances[cycle.startYear.toString()] ??
        balances[cycle.startYear];
    if (raw is num) return raw.toDouble();
  }
  final legacy = employee['leaveOpeningBalance'];
  if (legacy is num) return legacy.toDouble();
  return 0;
}

class EmployeeLeaveStats {
  final String userId;
  final String name;
  final LeaveCycle cycle;
  final double openingBalance;
  final double accrued;
  final double taken;
  final double total;
  final double balance;

  const EmployeeLeaveStats({
    required this.userId,
    required this.name,
    required this.cycle,
    required this.openingBalance,
    required this.accrued,
    required this.taken,
    required this.total,
    required this.balance,
  });

  @Deprecated('Use total')
  double get totalEntitlement => total;

  @Deprecated('Use balance')
  double get available => balance;
}

Future<Map<String, double>> fetchApprovedLeaveDaysByUserForCycle(
  LeaveCycle cycle,
) async {
  final snapshot = await FirebaseFirestore.instance
      .collection('leaves')
      .where('status', isEqualTo: 'Approved')
      .get();

  final takenByUser = <String, double>{};

  for (final doc in snapshot.docs) {
    final data = doc.data();
    final userId = data['userId']?.toString();
    if (userId == null || userId.isEmpty) continue;

    final start = (data['startDate'] as Timestamp?)?.toDate();
    final end = (data['endDate'] as Timestamp?)?.toDate();
    if (start == null || end == null) continue;

    if (end.isBefore(cycle.start) || start.isAfter(cycle.end)) continue;

    final clampedStart = start.isBefore(cycle.start) ? cycle.start : start;
    final clampedEnd = end.isAfter(cycle.end) ? cycle.end : end;
    final days = countLeaveDays(clampedStart, clampedEnd).toDouble();

    takenByUser[userId] = (takenByUser[userId] ?? 0) + days;
  }

  return takenByUser;
}

bool leaveMatchesDateFilter(
  Map<String, dynamic> data, {
  DateTime? filterStart,
  DateTime? filterEnd,
}) {
  final startTs = data['startDate'];
  final endTs = data['endDate'];
  if (startTs is! Timestamp || endTs is! Timestamp) return false;

  final leaveStart = startTs.toDate();
  final leaveEnd = endTs.toDate();

  if (filterStart != null && filterEnd != null) {
    return !leaveEnd.isBefore(filterStart) && !leaveStart.isAfter(filterEnd);
  }
  if (filterStart != null) {
    return !leaveEnd.isBefore(filterStart);
  }
  if (filterEnd != null) {
    return !leaveStart.isAfter(filterEnd);
  }
  return true;
}

int compareLeavesByStartDateDesc(
  QueryDocumentSnapshot a,
  QueryDocumentSnapshot b,
) {
  final aStart = (a.data() as Map<String, dynamic>)['startDate'];
  final bStart = (b.data() as Map<String, dynamic>)['startDate'];
  if (aStart is! Timestamp) return 1;
  if (bStart is! Timestamp) return -1;
  return bStart.compareTo(aStart);
}

Future<List<EmployeeLeaveStats>> buildLeaveStatsForEmployees({
  required List<Map<String, dynamic>> employees,
  required LeaveCycle cycle,
}) async {
  final takenByUser = await fetchApprovedLeaveDaysByUserForCycle(cycle);
  final now = DateTime.now();
  final asOf = cycle.contains(now) ? now : cycle.end;

  final stats = employees.map((employee) {
    final userId = employee['uid']?.toString() ?? '';
    final joinDate = employee['createdAt'] as DateTime?;
    final resignedDate = parseResignedDate(employee);
    final opening = openingBalanceForCycle(employee, cycle);
    final accrued = accruedLeaveDays(
      cycle: cycle,
      joinDate: joinDate,
      resignedDate: resignedDate,
      asOf: asOf,
    );
    final taken = takenByUser[userId] ?? 0;
    final total =
        double.parse((opening + accrued).toStringAsFixed(1));
    final balance =
        double.parse((total - taken).toStringAsFixed(1));

    return EmployeeLeaveStats(
      userId: userId,
      name: employee['name']?.toString() ?? 'Unknown',
      cycle: cycle,
      openingBalance: opening,
      accrued: accrued,
      taken: taken,
      total: total,
      balance: balance,
    );
  }).toList();

  stats.sort(
    (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  );

  return stats;
}

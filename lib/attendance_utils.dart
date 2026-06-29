import 'package:cloud_firestore/cloud_firestore.dart';

class AttendanceUtils {
  /// Standard working day (9 hours) — expected hours and half-day labels.
  static const int fullDayMinutes = 540;
  static const int expectedDayMinutes = fullDayMinutes;

  /// Reads `totalHours` from Firestore (stored as total minutes).
  static int? parseStoredMinutes(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static DateTime? parseRecordDate(Map<String, dynamic> data) {
    final punchInDate = data['punchInDate'];
    if (punchInDate is Timestamp) {
      final d = punchInDate.toDate();
      return DateTime(d.year, d.month, d.day);
    }
    if (punchInDate is DateTime) {
      return DateTime(
        punchInDate.year,
        punchInDate.month,
        punchInDate.day,
      );
    }

    final punchInTs = data['punchInTime'];
    if (punchInTs is Timestamp) {
      final punchIn = punchInTs.toDate();
      return DateTime(punchIn.year, punchIn.month, punchIn.day);
    }
    if (punchInTs is DateTime) {
      return DateTime(punchInTs.year, punchInTs.month, punchInTs.day);
    }

    return null;
  }

  static bool isDateInInclusiveRange(
    DateTime date,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final normalized = DateTime(date.year, date.month, date.day);
    final start = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    final end = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
    return !normalized.isBefore(start) && !normalized.isAfter(end);
  }

  static bool isExemptionApproved(Map<String, dynamic> data) {
    return (data['exemptionStatus'] ?? '').toString().toLowerCase() ==
        'approved';
  }

  /// Sum of actual minutes worked (no daily cap).
  static int sumWorkedMinutes(Iterable<Map<String, dynamic>> records) {
    var total = 0;
    for (final data in records) {
      if (data['punchOutTime'] == null) continue;
      total += parseStoredMinutes(data['totalHours']) ?? 0;
    }
    return total;
  }

  static String formatMinutes(int? totalMinutes) {
    if (totalMinutes == null) return '-';

    final mins = totalMinutes < 0 ? 0 : totalMinutes;
    final hrs = mins ~/ 60;
    final remMins = mins % 60;
    return '$hrs h ${remMins.toString().padLeft(2, '0')} m';
  }

  static double toDecimalHours(int minutes) {
    return double.parse((minutes / 60.0).toStringAsFixed(2));
  }
}

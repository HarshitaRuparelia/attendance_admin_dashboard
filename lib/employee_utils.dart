import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'attendance_utils.dart';

DateTime? parseResignedDate(Map<String, dynamic> data) {
  final value = data['resignedDate'] ??
      data['resignationDate'] ??
      data['resignDate'];
  if (value == null) return null;

  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;

  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final iso = DateTime.tryParse(trimmed);
    if (iso != null) return iso;

    const patterns = [
      'yyyy-MM-dd',
      'dd-MM-yyyy',
      'dd/MM/yyyy',
      'MM/dd/yyyy',
      'd MMM yyyy',
      'dd MMM yyyy',
    ];
    for (final pattern in patterns) {
      try {
        return DateFormat(pattern).parseStrict(trimmed);
      } catch (_) {}
    }
    return null;
  }

  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }

  return null;
}

bool hasResigned(Map<String, dynamic> data) {
  if (data['isActive'] == false) return true;

  final status = data['status']?.toString().toLowerCase().trim() ?? '';
  if (status == 'resigned' || status == 'inactive') return true;

  return parseResignedDate(data) != null;
}

DateTime? parseCreatedAt(Map<String, dynamic> data) {
  final value = data['createdAt'];
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

Map<String, dynamic> employeeFromDoc(QueryDocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>;
  final docId = doc.id;
  final uid = data['uid']?.toString().trim();
  return {
    'docId': docId,
    'uid': (uid != null && uid.isNotEmpty) ? uid : docId,
    'name': data['name']?.toString() ?? 'Unknown',
    'email': data['email']?.toString() ?? '',
    'isActive': data['isActive'] ?? true,
    'resignedDate': parseResignedDate(data),
    'createdAt': parseCreatedAt(data),
    'leaveEntitlement': (data['leaveEntitlement'] as num?)?.toDouble() ?? 12.0,
    'leaveOpeningBalance':
        (data['leaveOpeningBalance'] as num?)?.toDouble() ?? 0.0,
    'leaveOpeningBalances': data['leaveOpeningBalances'] is Map
        ? Map<String, dynamic>.from(
            data['leaveOpeningBalances'] as Map,
          )
        : <String, dynamic>{},
    'clientSiteSchedule': followsClientSiteSchedule(data),
  };
}

/// Client-deputed employees follow client routine: off 1st & 3rd Saturday.
/// Everyone else uses company default: off 2nd & 4th Saturday.
bool followsClientSiteSchedule(Map<String, dynamic> data) {
  return data['clientSiteSchedule'] == true ||
      data['offFirstThirdSaturday'] == true;
}

bool isNonTestUser(Map<String, dynamic> data) {
  return data['isTestUser'] != true;
}

Map<String, Map<String, dynamic>> buildEmployeeLookup(
  List<Map<String, dynamic>> employees,
) {
  final lookup = <String, Map<String, dynamic>>{};
  for (final employee in employees) {
    final uid = employee['uid']?.toString().trim();
    final docId = employee['docId']?.toString().trim();
    if (uid != null && uid.isNotEmpty) lookup[uid] = employee;
    if (docId != null && docId.isNotEmpty) lookup[docId] = employee;
  }
  return lookup;
}

Map<String, dynamic> lookupEmployeeRecord(
  String userId,
  Map<String, Map<String, dynamic>> lookup,
) {
  final key = userId.trim();
  if (key.isEmpty) {
    return {'uid': '', 'name': 'Unknown'};
  }
  return lookup[key] ?? {'uid': key, 'name': 'Unknown'};
}

DateTime normalizeDate(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

/// Whether attendance/leave on [date] should be shown for this employee.
/// Resignation is treated as the last working day (date-only, not time-of-day).
bool isEmployeeVisibleOnDate(Map<String, dynamic> emp, DateTime date) {
  final resignedDate = emp['resignedDate'] as DateTime?;

  if (emp['isActive'] == false && resignedDate == null) {
    return false;
  }

  if (resignedDate != null) {
    final recordDay = normalizeDate(date);
    final resignedDay = normalizeDate(resignedDate);
    return !recordDay.isAfter(resignedDay);
  }

  return true;
}

/// For monthly summary: exclude days before join date and after resignation.
bool isEmployeeActiveForSummaryDay(Map<String, dynamic> emp, DateTime day) {
  final dayNorm = normalizeDate(day);

  final createdAt = emp['createdAt'] as DateTime?;
  if (createdAt != null && dayNorm.isBefore(normalizeDate(createdAt))) {
    return false;
  }

  return isEmployeeVisibleOnDate(emp, day);
}

bool isWeekendDay(DateTime day) {
  return isWeekendDayForEmployee(const {}, day);
}

/// Whether [day] is a scheduled Saturday off for [emp] (not Sunday).
/// Company default: 2nd & 4th Saturday off.
/// Client site: 1st & 3rd Saturday off.
bool isScheduledOffSaturday(Map<String, dynamic> emp, DateTime day) {
  if (day.weekday != DateTime.saturday) return false;

  final saturdayCount = ((day.day - 1) ~/ 7) + 1;

  if (emp['clientSiteSchedule'] == true) {
    return saturdayCount == 1 || saturdayCount == 3;
  }

  return saturdayCount == 2 || saturdayCount == 4;
}

/// Whether [day] is a non-working day for [emp].
/// Sunday off for everyone.
/// Scheduled off-Saturdays follow [isScheduledOffSaturday].
bool isWeekendDayForEmployee(Map<String, dynamic> emp, DateTime day) {
  if (day.weekday == DateTime.sunday) return true;
  return isScheduledOffSaturday(emp, day);
}

int? minutesFromAttendanceRecord(Map<String, dynamic>? record) {
  if (record == null || record['punchOutTime'] == null) return null;
  return AttendanceUtils.parseStoredMinutes(record['totalHours']);
}

String attendanceDateKey(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String attendanceDayKey(Map<String, dynamic> record) {
  final userId = record['userId']?.toString();
  if (userId == null || userId.isEmpty) return '';

  final day = AttendanceUtils.parseRecordDate(record);
  if (day == null) return '';

  return '${userId}_${attendanceDateKey(day)}';
}

/// `${userId}_yyyy-mm-dd` keys where more than one attendance row exists.
Set<String> findDuplicateAttendanceDayKeys(
  Iterable<Map<String, dynamic>> attendanceRecords,
) {
  final counts = <String, int>{};
  for (final record in attendanceRecords) {
    final key = attendanceDayKey(record);
    if (key.isEmpty) continue;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts.entries
      .where((entry) => entry.value > 1)
      .map((entry) => entry.key)
      .toSet();
}

bool isDuplicateAttendanceEntry(
  Map<String, dynamic> record,
  Set<String> duplicateDayKeys,
) {
  if (record['type'] != 'attendance') return false;
  final key = attendanceDayKey(record);
  return key.isNotEmpty && duplicateDayKeys.contains(key);
}

/// Human-readable labels, e.g. "Kavita (15 May 2026)".
List<String> formatDuplicateAttendanceLabels({
  required Set<String> duplicateDayKeys,
  required Map<String, Map<String, dynamic>> employeeLookup,
}) {
  final labels = <String>[];

  for (final key in duplicateDayKeys) {
    final sep = key.indexOf('_');
    if (sep <= 0 || sep >= key.length - 1) continue;

    final userId = key.substring(0, sep);
    final dateParts = key.substring(sep + 1).split('-');
    if (dateParts.length != 3) continue;

    final year = int.tryParse(dateParts[0]);
    final month = int.tryParse(dateParts[1]);
    final day = int.tryParse(dateParts[2]);
    if (year == null || month == null || day == null) continue;

    final name =
        lookupEmployeeRecord(userId, employeeLookup)['name']?.toString() ??
            'Unknown';
    final dateLabel =
        DateFormat('dd MMM yyyy').format(DateTime(year, month, day));
    labels.add('$name ($dateLabel)');
  }

  labels.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return labels;
}

String formatHoursMinutes(int minutes) {
  return AttendanceUtils.formatMinutes(minutes);
}

Set<String> buildHolidayDateKeys(List<Map<String, dynamic>> holidays) {
  final keys = <String>{};
  for (final holiday in holidays) {
    final value = holiday['date'];
    if (value is! Timestamp) continue;
    keys.add(attendanceDateKey(value.toDate()));
  }
  return keys;
}

bool isApprovedLeaveOnDay(
  String userId,
  DateTime day,
  List<Map<String, dynamic>> leaves,
) {
  for (final leave in leaves) {
    if (leave['userId']?.toString() != userId) continue;
    if (leave['status']?.toString() == 'Rejected') continue;

    final startTs = leave['startDate'];
    final endTs = leave['endDate'];
    if (startTs is! Timestamp || endTs is! Timestamp) continue;

    final start = normalizeDate(startTs.toDate());
    final end = normalizeDate(endTs.toDate());
    final dayNorm = normalizeDate(day);

    if (!dayNorm.isBefore(start) && !dayNorm.isAfter(end)) {
      return true;
    }
  }
  return false;
}

/// One attendance record per employee per calendar day (latest wins).
Map<String, Map<String, dynamic>> buildAttendanceByDayMap(
  List<Map<String, dynamic>> attendanceRecords,
  String userId,
) {
  final map = <String, Map<String, dynamic>>{};
  for (final record in attendanceRecords) {
    if (record['userId']?.toString() != userId) continue;

    final punchDay = AttendanceUtils.parseRecordDate(record);
    if (punchDay == null) continue;

    map['${userId}_${attendanceDateKey(punchDay)}'] = record;
  }
  return map;
}

/// Worked minutes using the same rules as the monthly summary screen.
int calculateWorkedMinutesInRange({
  required String userId,
  required Map<String, dynamic> employee,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required List<Map<String, dynamic>> attendanceRecords,
  required List<Map<String, dynamic>> leaveRecords,
  required Set<String> holidayDateKeys,
}) {
  final firstDay = normalizeDate(rangeStart);
  final lastDay = normalizeDate(rangeEnd);
  final attendanceByDay = buildAttendanceByDayMap(attendanceRecords, userId);

  var totalMinutes = 0;

  for (var day = firstDay;
      !day.isAfter(lastDay);
      day = day.add(const Duration(days: 1))) {
    final dayKey = attendanceDateKey(day);

    if (holidayDateKeys.contains(dayKey)) continue;
    if (!isEmployeeActiveForSummaryDay(employee, day)) continue;

    final record = attendanceByDay['${userId}_$dayKey'];

    if (isWeekendDayForEmployee(employee, day)) {
      if (isScheduledOffSaturday(employee, day)) {
        final offSatMinutes = minutesFromAttendanceRecord(record);
        if (offSatMinutes != null) {
          totalMinutes += offSatMinutes;
        }
      }
      continue;
    }

    if (isApprovedLeaveOnDay(userId, day, leaveRecords)) continue;

    if (record == null || record['punchOutTime'] == null) continue;

    totalMinutes += AttendanceUtils.parseStoredMinutes(record['totalHours']) ?? 0;
  }

  return totalMinutes;
}

List<Map<String, dynamic>> listWorkedAttendanceRecordsInRange({
  required String userId,
  required Map<String, dynamic> employee,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required List<Map<String, dynamic>> attendanceRecords,
  required List<Map<String, dynamic>> leaveRecords,
  required Set<String> holidayDateKeys,
}) {
  final firstDay = normalizeDate(rangeStart);
  final lastDay = normalizeDate(rangeEnd);
  final attendanceByDay = buildAttendanceByDayMap(attendanceRecords, userId);
  final results = <Map<String, dynamic>>[];

  for (var day = firstDay;
      !day.isAfter(lastDay);
      day = day.add(const Duration(days: 1))) {
    final dayKey = attendanceDateKey(day);

    if (holidayDateKeys.contains(dayKey)) continue;
    if (!isEmployeeActiveForSummaryDay(employee, day)) continue;

    final record = attendanceByDay['${userId}_$dayKey'];

    if (isWeekendDayForEmployee(employee, day)) {
      if (isScheduledOffSaturday(employee, day) && record != null) {
        results.add(record);
      }
      continue;
    }

    if (isApprovedLeaveOnDay(userId, day, leaveRecords)) continue;

    if (record != null) {
      results.add(record);
    }
  }

  return results;
}

String calculateWorkedHoursTextInRange({
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required List<Map<String, dynamic>> attendanceRecords,
  required List<Map<String, dynamic>> leaveRecords,
  required Set<String> holidayDateKeys,
  required Map<String, Map<String, dynamic>> employeeLookup,
  String? userId,
}) {
  if (userId != null && userId.isNotEmpty) {
    final employee = lookupEmployeeRecord(userId, employeeLookup);
    final minutes = calculateWorkedMinutesInRange(
      userId: userId,
      employee: employee,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      attendanceRecords: attendanceRecords,
      leaveRecords: leaveRecords,
      holidayDateKeys: holidayDateKeys,
    );
    return formatHoursMinutes(minutes);
  }

  final userIds = attendanceRecords
      .map((record) => record['userId']?.toString())
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toSet();

  var totalMinutes = 0;
  for (final id in userIds) {
    final employee = lookupEmployeeRecord(id, employeeLookup);
    totalMinutes += calculateWorkedMinutesInRange(
      userId: id,
      employee: employee,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      attendanceRecords: attendanceRecords,
      leaveRecords: leaveRecords,
      holidayDateKeys: holidayDateKeys,
    );
  }

  return formatHoursMinutes(totalMinutes);
}

bool isSelectableEmployee(Map<String, dynamic> data) {
  if (data['isTestUser'] == true) return false;
  return !hasResigned(data);
}

bool isSelectableEmployeeRecord(Map<String, dynamic> employee) {
  if (employee['isActive'] == false) return false;
  if (employee['resignedDate'] != null) return false;
  return true;
}

Future<List<Map<String, dynamic>>> fetchAllEmployees() async {
  final snapshot =
      await FirebaseFirestore.instance.collection('users').get();

  final list = snapshot.docs
      .where((doc) => isNonTestUser(doc.data()))
      .map(employeeFromDoc)
      .toList();

  list.sort(
    (a, b) => a['name']
        .toString()
        .toLowerCase()
        .compareTo(b['name'].toString().toLowerCase()),
  );

  return list;
}

Future<List<Map<String, dynamic>>> fetchActiveEmployees() async {
  final all = await fetchAllEmployees();
  return all.where(isSelectableEmployeeRecord).toList();
}

Future<Map<String, String>> fetchActiveEmployeeNameMap() async {
  final employees = await fetchActiveEmployees();
  return employeeListToNameMap(employees);
}

Future<Map<String, String>> fetchAllEmployeeNameMap() async {
  final employees = await fetchAllEmployees();
  final map = <String, String>{};
  for (final employee in employees) {
    final name = employee['name']?.toString() ?? 'Unknown';
    final uid = employee['uid']?.toString();
    final docId = employee['docId']?.toString();
    if (uid != null && uid.isNotEmpty) map[uid] = name;
    if (docId != null && docId.isNotEmpty) map[docId] = name;
  }
  return map;
}

Map<String, String> employeeListToNameMap(List<Map<String, dynamic>> employees) {
  final map = <String, String>{};
  for (final employee in employees) {
    final name = employee['name']?.toString() ?? 'Unknown';
    final uid = employee['uid']?.toString();
    final docId = employee['docId']?.toString();
    if (uid != null && uid.isNotEmpty) map[uid] = name;
    if (docId != null && docId.isNotEmpty) map[docId] = name;
  }
  return map;
}

String formatStatusLabel(String status) {
  final trimmed = status.trim();
  if (trimmed.isEmpty) return 'Pending';
  return trimmed[0].toUpperCase() + trimmed.substring(1).toLowerCase();
}

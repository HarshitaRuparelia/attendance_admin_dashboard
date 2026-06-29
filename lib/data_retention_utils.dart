import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'employee_utils.dart';

/// Keeps [May of reference year] and [reference month] only.
bool isDateInRetention(DateTime date, {DateTime? reference}) {
  final ref = reference ?? DateTime.now();
  final d = normalizeDate(date);
  if (d.year == ref.year && d.month == ref.month) return true;
  if (d.year == ref.year && d.month == 5) return true;
  return false;
}

String retentionKeepLabel({DateTime? reference}) {
  final ref = reference ?? DateTime.now();
  final monthName = _monthName(ref.month);
  return 'May ${ref.year} and $monthName ${ref.year}';
}

String _monthName(int month) {
  const names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return names[month - 1];
}

class RetentionCleanupResult {
  final int logsDeleted;
  final int selfiesDeleted;
  final int attendanceUpdated;
  final List<String> errors;

  const RetentionCleanupResult({
    required this.logsDeleted,
    required this.selfiesDeleted,
    required this.attendanceUpdated,
    required this.errors,
  });
}

Future<void> _deleteStorageUrl(String? url, void Function() onDeleted) async {
  if (url == null || url.trim().isEmpty) return;
  if (url == 'auto_punchout') return;
  if (!url.startsWith('http')) return;
  try {
    await FirebaseStorage.instance.refFromURL(url).delete();
    onDeleted();
  } catch (e) {
    // File may already be gone — still count as attempted cleanup.
    if (!e.toString().toLowerCase().contains('object-not-found')) {
      rethrow;
    }
  }
}

Future<RetentionCleanupResult> cleanupLogsOutsideRetention({
  DateTime? reference,
  void Function(int deletedSoFar)? onProgress,
}) async {
  final ref = reference ?? DateTime.now();
  var logsDeleted = 0;
  final errors = <String>[];

  DocumentSnapshot? lastDoc;
  while (true) {
    Query query = FirebaseFirestore.instance
        .collection('logs')
        .orderBy('timestamp')
        .limit(400);

    if (lastDoc != null) {
      query = query.startAfterDocument(lastDoc);
    }

    final snapshot = await query.get();
    if (snapshot.docs.isEmpty) break;

    WriteBatch batch = FirebaseFirestore.instance.batch();
    var batchCount = 0;

    for (final doc in snapshot.docs) {
      lastDoc = doc;
      final ts = (doc.data() as Map<String, dynamic>)['timestamp'];
      if (ts is! Timestamp) continue;

      if (isDateInRetention(ts.toDate(), reference: ref)) continue;

      batch.delete(doc.reference);
      batchCount++;
      logsDeleted++;

      if (batchCount >= 400) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        batchCount = 0;
        onProgress?.call(logsDeleted);
      }
    }

    if (batchCount > 0) {
      await batch.commit();
      onProgress?.call(logsDeleted);
    }

    if (snapshot.docs.length < 400) break;
  }

  return RetentionCleanupResult(
    logsDeleted: logsDeleted,
    selfiesDeleted: 0,
    attendanceUpdated: 0,
    errors: errors,
  );
}

Future<RetentionCleanupResult> cleanupSelfiesOutsideRetention({
  DateTime? reference,
  void Function(int selfiesDeleted, int recordsUpdated)? onProgress,
}) async {
  final ref = reference ?? DateTime.now();
  var selfiesDeleted = 0;
  var attendanceUpdated = 0;
  final errors = <String>[];

  DocumentSnapshot? lastDoc;
  while (true) {
    Query query = FirebaseFirestore.instance
        .collection('attendance')
        .orderBy('punchInDate')
        .limit(200);

    if (lastDoc != null) {
      query = query.startAfterDocument(lastDoc);
    }

    final snapshot = await query.get();
    if (snapshot.docs.isEmpty) break;

    for (final doc in snapshot.docs) {
      lastDoc = doc;
      final data = doc.data() as Map<String, dynamic>;
      final recordDate = _attendanceRecordDate(data);
      if (recordDate == null) continue;
      if (isDateInRetention(recordDate, reference: ref)) continue;

      final updates = <String, dynamic>{};
      var recordChanged = false;

      for (final field in ['punchInSelfieUrl', 'punchOutSelfieUrl']) {
        final url = data[field]?.toString();
        if (url == null || url.isEmpty || url == 'auto_punchout') continue;

        try {
          await _deleteStorageUrl(url, () => selfiesDeleted++);
          updates[field] = FieldValue.delete();
          recordChanged = true;
        } catch (e) {
          errors.add('Selfie ${doc.id}/$field: $e');
        }
      }

      if (recordChanged) {
        try {
          await doc.reference.update(updates);
          attendanceUpdated++;
        } catch (e) {
          errors.add('Attendance ${doc.id}: $e');
        }
      }

      onProgress?.call(selfiesDeleted, attendanceUpdated);
    }

    if (snapshot.docs.length < 200) break;
  }

  return RetentionCleanupResult(
    logsDeleted: 0,
    selfiesDeleted: selfiesDeleted,
    attendanceUpdated: attendanceUpdated,
    errors: errors,
  );
}

DateTime? _attendanceRecordDate(Map<String, dynamic> data) {
  final punchInDate = data['punchInDate'];
  if (punchInDate is Timestamp) {
    final d = punchInDate.toDate();
    return DateTime(d.year, d.month, d.day);
  }
  final punchInTime = data['punchInTime'];
  if (punchInTime is Timestamp) {
    final d = punchInTime.toDate();
    return DateTime(d.year, d.month, d.day);
  }
  return null;
}

Future<RetentionCleanupResult> cleanupLogsAndSelfiesOutsideRetention({
  DateTime? reference,
  void Function(String stage, int count)? onProgress,
}) async {
  final logResult = await cleanupLogsOutsideRetention(
    reference: reference,
    onProgress: (count) => onProgress?.call('logs', count),
  );

  final selfieResult = await cleanupSelfiesOutsideRetention(
    reference: reference,
    onProgress: (selfies, records) =>
        onProgress?.call('selfies', selfies),
  );

  return RetentionCleanupResult(
    logsDeleted: logResult.logsDeleted,
    selfiesDeleted: selfieResult.selfiesDeleted,
    attendanceUpdated: selfieResult.attendanceUpdated,
    errors: [...logResult.errors, ...selfieResult.errors],
  );
}

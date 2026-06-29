import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

const String clockClientsCollection = 'clock_clients';
const String clockTasksCollection = 'clock_tasks';
const String clockHoursCollection = 'clock_hours';

String normalizeClockName(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String clockDocIdFromName(String name) {
  final normalized = normalizeClockName(name);
  final slug = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  return slug.isEmpty ? 'item' : slug;
}

String? readExcelCellText(Data? cell) {
  if (cell == null) return null;
  final value = cell.value;
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

enum ClockImportItemResult { added, skipped, reactivated }

class ClockMasterImportResult {
  final int clientsAdded;
  final int clientsSkipped;
  final int clientsReactivated;
  final int tasksAdded;
  final int tasksSkipped;
  final int tasksReactivated;
  final List<String> errors;

  const ClockMasterImportResult({
    this.clientsAdded = 0,
    this.clientsSkipped = 0,
    this.clientsReactivated = 0,
    this.tasksAdded = 0,
    this.tasksSkipped = 0,
    this.tasksReactivated = 0,
    this.errors = const [],
  });

  int get totalChanges =>
      clientsAdded +
      clientsReactivated +
      tasksAdded +
      tasksReactivated;

  String summaryText() {
    return 'Clients: $clientsAdded added, $clientsReactivated reactivated, '
        '$clientsSkipped unchanged. '
        'Tasks: $tasksAdded added, $tasksReactivated reactivated, '
        '$tasksSkipped unchanged.';
  }
}

class ClockMasterItem {
  final String id;
  final String name;
  final bool isActive;
  final String source;
  final String status;
  final String requestedByName;

  const ClockMasterItem({
    required this.id,
    required this.name,
    required this.isActive,
    required this.source,
    required this.status,
    this.requestedByName = '',
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';

  factory ClockMasterItem.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ClockMasterItem(
      id: doc.id,
      name: data['name']?.toString() ?? doc.id,
      isActive: data['isActive'] != false,
      source: data['source']?.toString() ?? 'manual',
      status: masterItemStatus(data),
      requestedByName: data['requestedByName']?.toString() ?? '',
    );
  }
}

String masterItemStatus(Map<String, dynamic> data) {
  final raw = data['status']?.toString().toLowerCase();
  if (raw == 'pending' || raw == 'approved' || raw == 'rejected') {
    return raw!;
  }
  return data['isActive'] != false ? 'approved' : 'rejected';
}

bool isApprovedMasterData(Map<String, dynamic> data) {
  return masterItemStatus(data) == 'approved' && data['isActive'] != false;
}

class ClockHourEntry {
  final String id;
  final String employeeId;
  final String employeeName;
  final String clientName;
  final String taskName;
  final double hours;
  final DateTime? workDate;
  final String notes;

  const ClockHourEntry({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.clientName,
    required this.taskName,
    required this.hours,
    required this.workDate,
    required this.notes,
  });

  factory ClockHourEntry.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    DateTime? workDate;
    final rawDate = data['workDate'];
    if (rawDate is Timestamp) {
      workDate = rawDate.toDate();
    } else if (rawDate is String) {
      workDate = DateTime.tryParse(rawDate);
    }

    return ClockHourEntry(
      id: doc.id,
      employeeId: data['employeeId']?.toString() ?? '',
      employeeName: data['employeeName']?.toString() ?? 'Unknown',
      clientName: data['clientName']?.toString() ?? '-',
      taskName: data['taskName']?.toString() ?? '-',
      hours: (data['hours'] as num?)?.toDouble() ?? 0,
      workDate: workDate,
      notes: data['notes']?.toString() ?? '',
    );
  }
}

String formatClockHours(double hours) {
  if (hours <= 0) return '0 h';
  final whole = hours.truncate();
  final minutes = ((hours - whole) * 60).round();
  if (minutes == 0) return '$whole h';
  return '$whole h ${minutes.toString().padLeft(2, '0')} m';
}

Stream<List<ClockMasterItem>> watchActiveClockClients() {
  return FirebaseFirestore.instance
      .collection(clockClientsCollection)
      .where('isActive', isEqualTo: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(ClockMasterItem.fromDoc)
            .where((item) => item.isApproved)
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      );
}

Stream<List<ClockMasterItem>> watchActiveClockTasks() {
  return FirebaseFirestore.instance
      .collection(clockTasksCollection)
      .where('isActive', isEqualTo: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(ClockMasterItem.fromDoc)
            .where((item) => item.isApproved)
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      );
}

Stream<List<ClockMasterItem>> watchAllClockClients() {
  return FirebaseFirestore.instance
      .collection(clockClientsCollection)
      .orderBy('name')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(ClockMasterItem.fromDoc).toList());
}

Stream<List<ClockMasterItem>> watchAllClockTasks() {
  return FirebaseFirestore.instance
      .collection(clockTasksCollection)
      .orderBy('name')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(ClockMasterItem.fromDoc).toList());
}

Stream<List<ClockHourEntry>> watchClockHours() {
  return FirebaseFirestore.instance
      .collection(clockHoursCollection)
      .orderBy('workDate', descending: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map(ClockHourEntry.fromDoc).toList(),
      );
}

Future<ClockImportItemResult> _upsertMasterItem({
  required String collection,
  required String name,
  required String source,
}) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError('Name cannot be empty');
  }

  final docId = clockDocIdFromName(trimmed);
  final ref = FirebaseFirestore.instance.collection(collection).doc(docId);
  final existing = await ref.get();

  if (existing.exists) {
    final data = existing.data() ?? {};
    if (data['isActive'] == true &&
        data['name']?.toString().trim() == trimmed) {
      return ClockImportItemResult.skipped;
    }

    await ref.set(
      {
        'name': trimmed,
        'normalizedName': normalizeClockName(trimmed),
        'isActive': true,
        'status': 'approved',
        'source': source,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return data['isActive'] == true
        ? ClockImportItemResult.skipped
        : ClockImportItemResult.reactivated;
  }

  await ref.set({
    'name': trimmed,
    'normalizedName': normalizeClockName(trimmed),
    'isActive': true,
    'status': 'approved',
    'source': source,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });
  return ClockImportItemResult.added;
}

Future<ClockImportItemResult> addClockClient(
  String name, {
  String source = 'manual',
}) {
  return _upsertMasterItem(
    collection: clockClientsCollection,
    name: name,
    source: source,
  );
}

Future<ClockImportItemResult> addClockTask(
  String name, {
  String source = 'manual',
}) {
  return _upsertMasterItem(
    collection: clockTasksCollection,
    name: name,
    source: source,
  );
}

Future<void> deactivateClockClient(String docId) async {
  await FirebaseFirestore.instance
      .collection(clockClientsCollection)
      .doc(docId)
      .delete();
}

Future<void> deactivateClockTask(String docId) async {
  await FirebaseFirestore.instance
      .collection(clockTasksCollection)
      .doc(docId)
      .delete();
}

Future<void> approveClockClient(String docId) async {
  await FirebaseFirestore.instance
      .collection(clockClientsCollection)
      .doc(docId)
      .update({
    'isActive': true,
    'status': 'approved',
    'approvedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

Future<void> approveClockTask(String docId) async {
  await FirebaseFirestore.instance
      .collection(clockTasksCollection)
      .doc(docId)
      .update({
    'isActive': true,
    'status': 'approved',
    'approvedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

Future<void> rejectClockClient(String docId) async {
  await deactivateClockClient(docId);
}

Future<void> rejectClockTask(String docId) async {
  await deactivateClockTask(docId);
}

bool _looksLikeMasterHeaderRow(String text, String kind) {
  final lower = text.toLowerCase().trim();
  if (lower.isEmpty) return false;

  if (kind == 'task') {
    return lower == 'task' ||
        lower == 'tasks' ||
        lower == 'task name' ||
        lower == 'task names' ||
        (lower.startsWith('task') && lower.contains('name'));
  }

  return lower == 'client' ||
      lower == 'clients' ||
      lower == 'client name' ||
      lower == 'client names' ||
      (lower.startsWith('client') && lower.contains('name'));
}

Sheet? _findExcelSheet(Excel excel, String preferredName) {
  if (excel.tables.containsKey(preferredName)) {
    return excel.tables[preferredName];
  }

  final target = preferredName.toLowerCase();
  for (final entry in excel.tables.entries) {
    if (entry.key.toLowerCase() == target) {
      return entry.value;
    }
  }
  return null;
}

List<String> _readNameColumnFromSheet(
  Sheet sheet, {
  required String kind,
}) {
  final names = <String>[];
  final seen = <String>{};
  var skippedHeader = false;

  for (final row in sheet.rows) {
    if (row.isEmpty) continue;
    final first = readExcelCellText(row.first);
    if (first == null) continue;

    if (!skippedHeader && _looksLikeMasterHeaderRow(first, kind)) {
      skippedHeader = true;
      continue;
    }

    final normalized = normalizeClockName(first);
    if (seen.add(normalized)) {
      names.add(first.trim());
    }
  }

  return names;
}

Future<ClockMasterImportResult> importClockMasterDataFromExcelBytes(
  List<int> bytes,
) async {
  final excel = Excel.decodeBytes(bytes);

  var clientsAdded = 0;
  var clientsSkipped = 0;
  var clientsReactivated = 0;
  var tasksAdded = 0;
  var tasksSkipped = 0;
  var tasksReactivated = 0;
  final errors = <String>[];

  Sheet? clientsSheet = _findExcelSheet(excel, 'Clients');
  Sheet? tasksSheet = _findExcelSheet(excel, 'Tasks');

  if (clientsSheet == null && tasksSheet == null) {
    final sheets = excel.tables.values.toList();
    if (sheets.length == 1) {
      clientsSheet = sheets.first;
    } else if (sheets.length > 1) {
      clientsSheet = sheets.first;
      tasksSheet = sheets[1];
    }
  } else if (clientsSheet == null && tasksSheet != null) {
    // Only Tasks sheet present — do not treat it as clients.
  } else if (clientsSheet != null && tasksSheet == null) {
    final sheets = excel.tables.values.toList();
    if (sheets.length > 1) {
      final clientsIndex = sheets.indexOf(clientsSheet);
      if (clientsIndex >= 0 && clientsIndex + 1 < sheets.length) {
        tasksSheet = sheets[clientsIndex + 1];
      }
    }
  }

  if (clientsSheet != null) {
    for (final name in _readNameColumnFromSheet(clientsSheet, kind: 'client')) {
      try {
        switch (await addClockClient(name, source: 'excel')) {
          case ClockImportItemResult.added:
            clientsAdded++;
          case ClockImportItemResult.skipped:
            clientsSkipped++;
          case ClockImportItemResult.reactivated:
            clientsReactivated++;
        }
      } catch (e) {
        errors.add('Client "$name": $e');
      }
    }
  }

  if (tasksSheet != null) {
    for (final name in _readNameColumnFromSheet(tasksSheet, kind: 'task')) {
      try {
        switch (await addClockTask(name, source: 'excel')) {
          case ClockImportItemResult.added:
            tasksAdded++;
          case ClockImportItemResult.skipped:
            tasksSkipped++;
          case ClockImportItemResult.reactivated:
            tasksReactivated++;
        }
      } catch (e) {
        errors.add('Task "$name": $e');
      }
    }
  }

  if (clientsSheet == null && tasksSheet == null) {
    errors.add('No readable sheets found in the Excel file.');
  }

  return ClockMasterImportResult(
    clientsAdded: clientsAdded,
    clientsSkipped: clientsSkipped,
    clientsReactivated: clientsReactivated,
    tasksAdded: tasksAdded,
    tasksSkipped: tasksSkipped,
    tasksReactivated: tasksReactivated,
    errors: errors,
  );
}

Future<String> downloadClockMasterTemplate() async {
  final workbook = xlsio.Workbook();

  final clientsSheet = workbook.worksheets[0];
  clientsSheet.name = 'Clients';
  clientsSheet.getRangeByIndex(1, 1).setText('Client Name');
  clientsSheet.getRangeByIndex(1, 1).cellStyle.bold = true;
  clientsSheet.getRangeByIndex(2, 1).setText('Example Client A');
  clientsSheet.getRangeByIndex(3, 1).setText('Example Client B');
  clientsSheet.autoFitColumn(1);

  final tasksSheet = workbook.worksheets.add();
  tasksSheet.name = 'Tasks';
  tasksSheet.getRangeByIndex(1, 1).setText('Task Name');
  tasksSheet.getRangeByIndex(1, 1).cellStyle.bold = true;
  tasksSheet.getRangeByIndex(2, 1).setText('Example Task 1');
  tasksSheet.getRangeByIndex(3, 1).setText('Example Task 2');
  tasksSheet.autoFitColumn(1);

  final bytes = workbook.saveAsStream();
  workbook.dispose();

  final downloadsPath = await _downloadsDirectoryPath();
  final filePath =
      '$downloadsPath\\Clock_Clients_Tasks_Template.xlsx';
  final file = File(filePath);
  await file.writeAsBytes(bytes, flush: true);
  return filePath;
}

Future<String> exportClockHoursToExcel({
  required List<ClockHourEntry> entries,
}) async {
  final workbook = xlsio.Workbook();
  final sheet = workbook.worksheets[0];
  sheet.name = 'Clock Hours';

  const headers = [
    'Employee',
    'Date',
    'Client',
    'Task',
    'Hours',
    'Notes',
  ];

  for (var i = 0; i < headers.length; i++) {
    final cell = sheet.getRangeByIndex(1, i + 1);
    cell.setText(headers[i]);
    cell.cellStyle.bold = true;
    cell.cellStyle.backColor = '#FFF2CC';
  }

  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final row = i + 2;
    sheet.getRangeByIndex(row, 1).setText(entry.employeeName);
    if (entry.workDate != null) {
      sheet.getRangeByIndex(row, 2).setDateTime(entry.workDate!);
    }
    sheet.getRangeByIndex(row, 3).setText(entry.clientName);
    sheet.getRangeByIndex(row, 4).setText(entry.taskName);
    sheet.getRangeByIndex(row, 5).setNumber(entry.hours);
    sheet.getRangeByIndex(row, 6).setText(entry.notes);
  }

  sheet.getRangeByName('B2:B10000').numberFormat = 'dd-mmm-yyyy';
  sheet.getRangeByName('E2:E10000').numberFormat = '0.00';
  for (var col = 1; col <= headers.length; col++) {
    sheet.autoFitColumn(col);
  }

  final bytes = workbook.saveAsStream();
  workbook.dispose();

  final downloadsPath = await _downloadsDirectoryPath();
  final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
  final filePath = '$downloadsPath\\Clock_Hours_$stamp.xlsx';
  await File(filePath).writeAsBytes(bytes, flush: true);
  return filePath;
}

Future<String> _downloadsDirectoryPath() async {
  if (Platform.isWindows) {
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) {
      return userProfile + '\\Downloads';
    }
  }
  final dir = await getApplicationDocumentsDirectory();
  return dir.path;
}

Future<void> openExportedFile(String filePath) async {
  try {
    await OpenFilex.open(filePath);
    if (Platform.isWindows) {
      Process.start('explorer.exe', [filePath]);
    }
  } catch (_) {}
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:io';
import 'package:fluttertoast/fluttertoast.dart';
class LeaveApprovalScreen extends StatefulWidget {
  const LeaveApprovalScreen({super.key});

  @override
  State<LeaveApprovalScreen> createState() => _LeaveApprovalScreenState();
}

class _LeaveApprovalScreenState extends State<LeaveApprovalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, String> employees = {}; // userId → name
  String? selectedEmployee;
  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchEmployees();
  }

  Future<void> _fetchEmployees() async {
    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    setState(() {
      employees = {
        for (var doc in snapshot.docs)
          (doc.id): (doc['name'] ?? 'Unknown').toString()
      };
    });
  }

  Stream<QuerySnapshot> _getLeaveStream(String status) {
    Query query = FirebaseFirestore.instance
        .collection('leaves')
        .where('status', isEqualTo: status)
        .orderBy('startDate', descending: true);

    if (selectedEmployee != null && selectedEmployee!.isNotEmpty) {
      query = query.where('userId', isEqualTo: selectedEmployee);
    }

    if (startDate != null && endDate != null) {
      query = query
          .where('startDate', isGreaterThanOrEqualTo: startDate)
          .where('endDate', isLessThanOrEqualTo: endDate);
    }

    return query.snapshots();
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
      initialDateRange: startDate != null && endDate != null
          ? DateTimeRange(start: startDate!, end: endDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        startDate = picked.start;
        endDate = picked.end;
      });
    }
  }

  void _updateLeaveStatus(String docId, String status) async {
    await FirebaseFirestore.instance
        .collection('leaves')
        .doc(docId)
        .update({'status': status});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Leave marked as $status')),
    );
  }

  Widget _buildLeaveList(String status) {
    return StreamBuilder<QuerySnapshot>(
      stream: _getLeaveStream(status),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text("No $status leaves"));
        }

        final docs = snapshot.data!.docs;

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final userId = data['userId'] ?? '';
            final name = employees[userId] ?? 'Unknown';
            final startDate = (data['startDate'] as Timestamp).toDate();
            final endDate = (data['endDate'] as Timestamp).toDate();

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ListTile(
                title: Text(
                  name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                subtitle: SelectableText(
                  "From: ${DateFormat('dd MMM yyyy').format(startDate)}\n"
                      "To: ${DateFormat('dd MMM yyyy').format(endDate)}\n"
                      "Status: $status",
                ),
                trailing: status == "Pending"
                    ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon:
                      const Icon(Icons.check, color: Colors.green),
                      tooltip: "Approve",
                      onPressed: () => _updateLeaveStatus(
                          docs[index].id, "Approved"),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      tooltip: "Reject",
                      onPressed: () => _updateLeaveStatus(
                          docs[index].id, "Rejected"),
                    ),
                  ],
                )
                    : null,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          SizedBox(
            width: 250,
            child: DropdownButtonFormField<String>(
              value: selectedEmployee,
              hint: const Text("Select Employee"),
              items: employees.entries
                  .map((e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value),
              ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  selectedEmployee = value;
                });
              },
            ),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.date_range),
            label: Text(
              startDate == null || endDate == null
                  ? "Select Date Range"
                  : "${DateFormat('dd MMM').format(startDate!)} - ${DateFormat('dd MMM yyyy').format(endDate!)}",
            ),
            onPressed: () => _selectDateRange(context),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                startDate = null;
                endDate = null;
                selectedEmployee = null;
              });
            },
            child: const Text("Clear Filters"),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.download),
            label: const Text("Export to Excel"),
            onPressed: () {
              final status = _tabController.index == 0
                  ? "Pending"
                  : _tabController.index == 1
                  ? "Approved"
                  : "Rejected";
              _exportToExcel(status);
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.download),
            label: const Text("Export All Leaves to Excel"),
            onPressed: () {
              final status = _tabController.index == 0
                  ? "Pending"
                  : _tabController.index == 1
                  ? "Approved"
                  : "Rejected";
              _exportAllLeavesToExcel();
            },
          )
        ],
      ),
    );
  }
  Future<void> _exportToExcel(String status) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Leave Report';

    // 🧱 Headers
    final headers = [
      'Employee Name',
      'From Date',
      'To Date',
      'Status',
      'Reason',
      'Applied On'
    ];
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(1, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = '#D9EAD3';
    }

    // 🔄 Fetch filtered data
    Query query = FirebaseFirestore.instance
        .collection('leaves')
        .where('status', isEqualTo: status);

    if (selectedEmployee != null && selectedEmployee!.isNotEmpty) {
      query = query.where('userId', isEqualTo: selectedEmployee);
    }
    if (startDate != null && endDate != null) {
      query = query
          .where('startDate', isGreaterThanOrEqualTo: startDate)
          .where('endDate', isLessThanOrEqualTo: endDate);
    }

    final snapshot = await query.get();
    final docs = snapshot.docs;

    // 🧾 Add rows
    for (int i = 0; i < docs.length; i++) {
      final data = docs[i].data() as Map<String, dynamic>;
      final name = employees[data['userId']] ?? 'Unknown';
      final start = (data['startDate'] as Timestamp).toDate();
      final end = (data['endDate'] as Timestamp).toDate();
      final applied = (data['timestamp'] as Timestamp).toDate();

      sheet.getRangeByIndex(i + 2, 1).setText(name);
      sheet.getRangeByIndex(i + 2, 2).setDateTime(start);
      sheet.getRangeByIndex(i + 2, 3).setDateTime(end);
      sheet.getRangeByIndex(i + 2, 4).setText(data['status'] ?? '');
      sheet.getRangeByIndex(i + 2, 5).setText(data['reason'] ?? '');
      sheet.getRangeByIndex(i + 2, 6).setDateTime(applied);
    }

    // 🧮 Set column width & date format
    sheet.autoFitColumn(1);
    for (int i = 2; i <= 6; i++) {
      sheet.autoFitColumn(i);
    }

    sheet.getRangeByName('B2:C1000').numberFormat = 'dd-mmm-yyyy';
    sheet.getRangeByName('F2:F1000').numberFormat = 'dd-mmm-yyyy hh:mm';

    // 💾 Save file
    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final downloadsDir = Directory("C:/Users/${Platform.environment['USERNAME']}/Downloads");
    final filePath = '${downloadsDir.path}/Leaves_Report.xlsx';
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);

    // 📂 Open it
    await OpenFilex.open(filePath);

    Fluttertoast.showToast(
      msg: "Excel exported successfully!",
      backgroundColor: Colors.green,
    );
  }

  Future<void> _exportAllLeavesToExcel() async {
    try {
      final excel = Excel.createExcel();
      final Sheet sheet = excel['Leaves'];

      // Add header row
      sheet.appendRow([
        'Employee Name',
        'Start Date',
        'End Date',
        'Status',
        'Reason',
        'Applied On',
        'User ID',
      ]);

      // Fetch all leaves from Firestore
      final leavesSnapshot = await FirebaseFirestore.instance
          .collection('leaves')
          .orderBy('startDate', descending: true)
          .get();

      // Create a lookup map for employee names
      final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
      final userMap = {
        for (var u in usersSnapshot.docs)
          u.id: (u.data() as Map<String, dynamic>)['name'] ?? 'Unknown'
      };

      for (var doc in leavesSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final userId = data['userId'] ?? '';
        final employeeName = userMap[userId] ?? 'Unknown';

        final startDate = (data['startDate'] as Timestamp?)?.toDate();
        final endDate = (data['endDate'] as Timestamp?)?.toDate();
        final timestamp = (data['timestamp'] as Timestamp?)?.toDate();

        sheet.appendRow([
          employeeName,
          startDate != null ? DateFormat('dd-MM-yyyy').format(startDate) : '-',
          endDate != null ? DateFormat('dd-MM-yyyy').format(endDate) : '-',
          data['status'] ?? '-',
          data['reason'] ?? '-',
          timestamp != null ? DateFormat('dd-MM-yyyy hh:mm a').format(timestamp) : '-',
          userId,
        ]);
      }

      // 📂 Save file to Downloads folder (Windows)
      final downloadsDir = Directory("C:/Users/${Platform.environment['USERNAME']}/Downloads");
      final filePath = '${downloadsDir.path}/All_Leaves_Report.xlsx';

      final fileBytes = excel.encode();
      final file = File(filePath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(fileBytes!);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Excel exported successfully to $filePath"),
            backgroundColor: Colors.green,
          ),
        );
      }

      // 🔹 Open the file automatically
      await OpenFilex.open(filePath);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to export Excel: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Leave Requests"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Pending"),
            Tab(text: "Approved"),
            Tab(text: "Rejected"),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildFilters(),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildLeaveList("Pending"),
                _buildLeaveList("Approved"),
                _buildLeaveList("Rejected"),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

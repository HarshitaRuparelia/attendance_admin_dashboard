import 'dart:math' as math;

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
    Query query = FirebaseFirestore.instance.collection('leaves');

    // Status filter (always applied)
    query = query.where('status', isEqualTo: status);

    // Employee filter (optional)
    if (selectedEmployee != null && selectedEmployee!.isNotEmpty) {
      query = query.where('userId', isEqualTo: selectedEmployee);
    }

    // Date filter (partial-friendly)
    if (startDate != null && endDate != null) {
      query = query
          .where('startDate', isLessThanOrEqualTo: endDate)
          .where('endDate', isGreaterThanOrEqualTo: startDate);
    } else if (startDate != null && endDate == null) {
      // Show leaves starting or ending after startDate
      query = query.where('endDate', isGreaterThanOrEqualTo: startDate);
    } else if (endDate != null && startDate == null) {
      // Show leaves starting before endDate
      query = query.where('startDate', isLessThanOrEqualTo: endDate);
    }

    return query.orderBy('startDate', descending: true).snapshots();
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

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Leave marked as $status')),
      );
    }
  }

  // Widget _buildLeaveList(String status) {
  //   return StreamBuilder<QuerySnapshot>(
  //     stream: _getLeaveStream(status),
  //     builder: (context, snapshot) {
  //       if (snapshot.connectionState == ConnectionState.waiting) {
  //         return const Center(child: CircularProgressIndicator());
  //       }
  //
  //       if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
  //         return Center(child: Text("No $status leaves found"));
  //       }
  //
  //       final docs = snapshot.data!.docs;
  //
  //       return ListView.builder(
  //         itemCount: docs.length,
  //         itemBuilder: (context, index) {
  //           final data = docs[index].data() as Map<String, dynamic>;
  //           final userId = data['userId'] ?? '';
  //           final name = employees[userId] ?? 'Unknown';
  //           final startDate = (data['startDate'] as Timestamp).toDate();
  //           final endDate = (data['endDate'] as Timestamp).toDate();
  //           final appliedOn = (data['appliedOn'] as Timestamp?)?.toDate();
  //           final reason = (data['reason'] ?? '').toString();
  //           final leaveType = (data['type'] ?? 'N/A').toString();
  //
  //           return Container(
  //             margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
  //             padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  //             decoration: BoxDecoration(
  //               color: Colors.grey.shade50,
  //               borderRadius: BorderRadius.circular(8),
  //               border: BoxBorder.all(color: Colors.grey.shade300),
  //             ),
  //             child: Column(
  //               crossAxisAlignment: CrossAxisAlignment.start,
  //               children: [
  //
  //                 /// 🔹 ROW 1 → Name | Dates | Applied | Type | Status
  //                 Row(
  //                   children: [
  //
  //                     /// Name
  //                     Expanded(
  //                       flex: 2,
  //                       child: Text(
  //                         name,
  //                         style: const TextStyle(
  //                           fontWeight: FontWeight.w600,
  //                           fontSize: 13,
  //                         ),
  //                         overflow: TextOverflow.ellipsis,
  //                       ),
  //                     ),
  //
  //                     /// Date Range
  //                     Expanded(
  //                       flex: 2,
  //                       child: Text(
  //                         "${DateFormat('dd MMM').format(startDate)} → "
  //                             "${DateFormat('dd MMM yyyy').format(endDate)}",
  //                         style: const TextStyle(fontSize: 12),
  //                         overflow: TextOverflow.ellipsis,
  //                       ),
  //                     ),
  //
  //                     /// Applied On
  //                     Expanded(
  //                       flex: 2,
  //                       child: Text(
  //                         appliedOn != null
  //                             ? "Applied: ${DateFormat('dd MMM, hh:mm a').format(appliedOn)}"
  //                             : "Applied: -",
  //                         style: const TextStyle(
  //                             fontSize: 11, color: Colors.grey),
  //                         overflow: TextOverflow.ellipsis,
  //                       ),
  //                     ),
  //
  //                     /// Leave Type
  //                     Container(
  //                       padding: const EdgeInsets.symmetric(
  //                           horizontal: 8, vertical: 3),
  //                       decoration: BoxDecoration(
  //                         color: Colors.blue.shade50,
  //                         borderRadius: BorderRadius.circular(12),
  //                       ),
  //                       child: Text(
  //                         leaveType,
  //                         style: const TextStyle(
  //                           fontSize: 10,
  //                           color: Colors.blue,
  //                           fontWeight: FontWeight.w600,
  //                         ),
  //                       ),
  //                     ),
  //
  //                     const SizedBox(width: 8),
  //
  //                     /// Status Badge
  //                     Container(
  //                       padding: const EdgeInsets.symmetric(
  //                           horizontal: 8, vertical: 3),
  //                       decoration: BoxDecoration(
  //                         color: status == "Approved"
  //                             ? Colors.green.shade50
  //                             : status == "Rejected"
  //                             ? Colors.red.shade50
  //                             : Colors.orange.shade50,
  //                         borderRadius: BorderRadius.circular(12),
  //                       ),
  //                       child: Text(
  //                         status,
  //                         style: TextStyle(
  //                           fontSize: 10,
  //                           fontWeight: FontWeight.w600,
  //                           color: status == "Approved"
  //                               ? Colors.green
  //                               : status == "Rejected"
  //                               ? Colors.red
  //                               : Colors.orange,
  //                         ),
  //                       ),
  //                     ),
  //                   ],
  //                 ),
  //
  //                 const SizedBox(height: 6),
  //
  //                 /// 🔹 ROW 2 → Reason + Approve/Reject
  //                 Row(
  //                   children: [
  //
  //                     /// Reason
  //                     Expanded(
  //                       child: Text(
  //                         reason.isNotEmpty ? reason : "-",
  //                         style: const TextStyle(
  //                           fontSize: 12,
  //                           color: Colors.black87,
  //                         ),
  //                         overflow: TextOverflow.ellipsis,
  //                         maxLines: 1,
  //                       ),
  //                     ),
  //
  //                     /// Buttons (Only if Pending)
  //                     if (status == "Pending")
  //                       Row(
  //                         children: [
  //                           IconButton(
  //                             icon: const Icon(Icons.check_circle,
  //                                 color: Colors.green, size: 20),
  //                             padding: EdgeInsets.zero,
  //                             constraints: const BoxConstraints(),
  //                             onPressed: () =>
  //                                 _updateLeaveStatus(docs[index].id, "Approved"),
  //                           ),
  //                           const SizedBox(width: 6),
  //                           IconButton(
  //                             icon: const Icon(Icons.cancel,
  //                                 color: Colors.red, size: 20),
  //                             padding: EdgeInsets.zero,
  //                             constraints: const BoxConstraints(),
  //                             onPressed: () =>
  //                                 _updateLeaveStatus(docs[index].id, "Rejected"),
  //                           ),
  //                         ],
  //                       ),
  //                   ],
  //                 ),
  //               ],
  //             ),
  //           );
  //         },
  //       );
  //     },
  //   );
  // }

  Widget _buildLeaveList(String status) {
    return StreamBuilder<QuerySnapshot>(
      stream: _getLeaveStream(status),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text("No $status leaves found"));
        }

        final docs = snapshot.data!.docs;

        return LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;

            final tableWidth = math.min(screenWidth, 1200.0);
            return SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: Center(
                child: SizedBox(
                  width: tableWidth,

                  child: DataTable(
                    columnSpacing: 20,
                    headingRowHeight: 45,
                    dataRowMinHeight: 55,
                    dataRowMaxHeight: 65,
                    headingRowColor:
                    MaterialStateProperty.all(Colors.grey.shade200),
                    columns: const [
                      DataColumn(label: Text("Name")),
                      DataColumn(label: Text("Start → End")),
                      DataColumn(label: Text("Applied On")),
                      DataColumn(label: Text("Type")),
                      DataColumn(label: Text("Status")),
                      DataColumn(label: Text("Reason")),
                      DataColumn(label: Text("Action")),
                    ],
                    rows: docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;

                      final userId = data['userId'] ?? '';
                      final name = employees[userId] ?? 'Unknown';

                      final startDate =
                      (data['startDate'] as Timestamp).toDate();
                      final endDate =
                      (data['endDate'] as Timestamp).toDate();
                      final appliedOn =
                      (data['appliedOn'] as Timestamp?)?.toDate();

                      final leaveType =
                      (data['type'] ?? 'N/A').toString();
                      final reason =
                      (data['reason'] ?? '').toString();

                      return DataRow(
                        cells: [

                          /// Name
                          DataCell(Text(name)),

                          /// Date Range
                          DataCell(
                            Text(
                              "${DateFormat('dd MMM').format(startDate)} → "
                                  "${DateFormat('dd MMM yyyy').format(endDate)}",
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500),
                            ),
                          ),

                          /// Applied On
                          DataCell(
                            Text(
                              appliedOn != null
                                  ? DateFormat(
                                  'dd MMM yyyy, hh:mm a')
                                  .format(appliedOn)
                                  : "-",
                            ),
                          ),

                          /// Leave Type
                          DataCell(
                            Text(
                              leaveType,
                              style: const TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),

                          /// Status
                          DataCell(
                            Text(
                              status,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: status == "Approved"
                                    ? Colors.green
                                    : status == "Rejected"
                                    ? Colors.red
                                    : Colors.orange,
                              ),
                            ),
                          ),

                          /// Reason (More Space Now)
                          DataCell(
                            InkWell(
                              onTap: () {
                                _showReasonDialog(context, reason);
                              },
                              child: SizedBox(
                                width: 180,
                                child: Text(
                                  reason.isNotEmpty ? reason : "-",
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 3,
                                  style: const TextStyle(
                                    //color: Colors.blue,
                                    //decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          /// Action
                          DataCell(
                            status == "Pending"
                                ? Row(
                              children: [
                                IconButton(
                                  icon: const Icon(
                                      Icons.check,
                                      color:
                                      Colors.green),
                                  onPressed: () =>
                                      _updateLeaveStatus(
                                          doc.id,
                                          "Approved"),
                                ),
                                IconButton(
                                  icon: const Icon(
                                      Icons.close,
                                      color:
                                      Colors.red),
                                  onPressed: () =>
                                      _updateLeaveStatus(
                                          doc.id,
                                          "Rejected"),
                                ),
                              ],
                            )
                                : const Text("-"),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
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
          ElevatedButton.icon(
            icon: const Icon(Icons.clear),
            onPressed: () {
              setState(() {
                startDate = null;
                endDate = null;
                selectedEmployee = null;
              });
            },
            label: const Text("Clear Filters"),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.download_for_offline),
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
            icon: const Icon(Icons.download_for_offline),
            label: const Text("Export All"),
            onPressed: _exportAllLeavesToExcel,
          ),
        ],
      ),
    );
  }

  Future<void> _exportToExcel(String status) async {
    try {
      final workbook = xlsio.Workbook();
      final sheet = workbook.worksheets[0];
      sheet.name = "Leave Report";

      // 🧱 Headers
      final headers = [
        'Employee Name',
        'From Date',
        'To Date',
        'Status',
        'Reason',
        'Leave Type',
        'Applied On',
        'User ID'
      ];

      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.getRangeByIndex(1, i + 1);
        cell.setText(headers[i]);
        cell.cellStyle.bold = true;
        cell.cellStyle.backColor = '#D9EAD3';
      }

      // 🔄 Firestore Query
      Query query = FirebaseFirestore.instance
          .collection('leaves')
          .where('status', isEqualTo: status);

      if (selectedEmployee != null && selectedEmployee!.isNotEmpty) {
        query = query.where('userId', isEqualTo: selectedEmployee);
      }

      if (startDate != null && endDate != null) {
        query = query
            .where('startDate', isLessThanOrEqualTo: endDate)
            .where('endDate', isGreaterThanOrEqualTo: startDate);
      } else if (startDate != null && endDate == null) {
        query = query.where('endDate', isGreaterThanOrEqualTo: startDate);
      } else if (endDate != null && startDate == null) {
        query = query.where('startDate', isLessThanOrEqualTo: endDate);
      }

      final snapshot = await query.get();

      // 🧾 Add data rows
      for (int i = 0; i < snapshot.docs.length; i++) {
        final data = snapshot.docs[i].data() as Map<String, dynamic>;

        final name = employees[data['userId']] ?? 'Unknown';
        final userId = data['userId'] ?? '-';
        final start = (data['startDate'] as Timestamp?)?.toDate();
        final end = (data['endDate'] as Timestamp?)?.toDate() ?? start;
        final applied = (data['appliedOn'] as Timestamp?)?.toDate();

        sheet.getRangeByIndex(i + 2, 1).setText(name);
        sheet.getRangeByIndex(i + 2, 2).setDateTime(start ?? DateTime.now());
        sheet.getRangeByIndex(i + 2, 3).setDateTime(end ?? start ?? DateTime.now());
        sheet.getRangeByIndex(i + 2, 4).setText(data['status'] ?? '');
        sheet.getRangeByIndex(i + 2, 5).setText(data['reason'] ?? '');
        sheet.getRangeByIndex(i + 2, 6).setText(data['type'] ?? '');
        if (applied != null) {
          sheet.getRangeByIndex(i + 2, 7).setDateTime(applied);
        }
        sheet.getRangeByIndex(i + 2, 8).setText(userId);
      }

      // 🧮 Format columns
      sheet.getRangeByName('B2:C1000').numberFormat = 'dd-mmm-yyyy';
      sheet.getRangeByName('G2:G1000').numberFormat = 'dd-mmm-yyyy hh:mm AM/PM';

      // Auto-fit all columns
      for (var col = 1; col <= headers.length; col++) {
        sheet.autoFitColumn(col);
      }

      // 💾 Save File
      final bytes = workbook.saveAsStream();
      workbook.dispose();

      String downloadsPath = "";
      if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        downloadsPath = "$userProfile\\Downloads";
      } else {
        final dir = await getApplicationDocumentsDirectory();
        downloadsPath = dir.path;
      }

      final filePath = "$downloadsPath\\Leave_Report_${status}.xlsx";
      final file = File(filePath);

      try {
        await file.writeAsBytes(bytes, flush: true);
        await OpenFilex.open(filePath);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ Exported successfully: $filePath"),
            backgroundColor: Colors.green,),
        );
      } on FileSystemException {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("⚠️ Please close the Excel file before exporting again."),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // 🪟 Open file explorer automatically (Windows)
      if (Platform.isWindows) {
        Process.start('explorer.exe', [filePath]);
      }
    } catch (e) {
      print("error1 :   $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Failed to export: $e"),
            backgroundColor: Colors.red),
      );
    }
  }



  Future<void> _exportAllLeavesToExcel() async {
    try {
      final workbook = xlsio.Workbook();
      final sheet = workbook.worksheets[0];

      // 🧾 Headers
      final headers = [
        'Employee Name',
        'From Date',
        'To Date',
        'Status',
        'Reason',
        'Leave Type',
        'Applied On',
        'User ID',
      ];

      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.getRangeByIndex(1, i + 1);
        cell.setText(headers[i]);
        cell.cellStyle.bold = true;
        cell.cellStyle.backColor = '#D9EAD3';
      }

      // 🧠 Fetch leaves
      Query query = FirebaseFirestore.instance
          .collection('leaves')
          .orderBy('startDate', descending: true);

// Apply date filters
      if (startDate != null && endDate != null) {
        query = query
            .where('startDate', isLessThanOrEqualTo: endDate)
            .where('endDate', isGreaterThanOrEqualTo: startDate);
      } else if (startDate != null && endDate == null) {
        query = query.where('endDate', isGreaterThanOrEqualTo: startDate);
      } else if (endDate != null && startDate == null) {
        query = query.where('startDate', isLessThanOrEqualTo: endDate);
      }

// Apply employee filter if selected
      if (selectedEmployee != null && selectedEmployee!.isNotEmpty) {
        query = query.where('userId', isEqualTo: selectedEmployee);
      }

      final leavesSnapshot = await query.get();

      // 🧠 Fetch users
      final usersSnapshot =
      await FirebaseFirestore.instance.collection('users').get();

      final userMap = {
        for (var u in usersSnapshot.docs)
          u.id: (u.data() as Map<String, dynamic>)['name'] ?? 'Unknown'
      };

      // 📝 Write rows
      for (int i = 0; i < leavesSnapshot.docs.length; i++) {
        final data = leavesSnapshot.docs[i].data() as Map<String, dynamic>;
        final userId = data['userId'] ?? '';
        final employeeName = userMap[userId] ?? 'Unknown';
        final startDate = (data['startDate'] as Timestamp?)?.toDate();
        final endDate = (data['endDate'] as Timestamp?)?.toDate();
        final appliedOn = (data['appliedOn'] as Timestamp?)?.toDate();
        final type = data['type'] ?? '-';

        sheet.getRangeByIndex(i + 2, 1).setText(employeeName);
        if (startDate != null) {
          sheet.getRangeByIndex(i + 2, 2).setDateTime(startDate);
        }
        if (endDate != null) {
          sheet.getRangeByIndex(i + 2, 3).setDateTime(endDate);
        }
        sheet.getRangeByIndex(i + 2, 4).setText(data['status'] ?? '-');
        sheet.getRangeByIndex(i + 2, 5).setText(data['reason'] ?? '-');
        sheet.getRangeByIndex(i + 2, 6).setText(type);
        if (appliedOn != null) {
          sheet.getRangeByIndex(i + 2, 7).setDateTime(appliedOn);
        }
        sheet.getRangeByIndex(i + 2, 8).setText(userId);
      }

      // 📅 Format columns
      sheet.getRangeByName('B2:D1000').numberFormat = 'dd-mmm-yyyy';
      sheet.getRangeByName('G2:G1000').numberFormat = 'dd-mmm-yyyy hh:mm AM/PM';

      // 🪄 Auto-fit columns safely
      for (var col = 1; col <= headers.length; col++) {
        sheet.autoFitColumn(col);
      }

      // 💾 Save file
      final bytes = workbook.saveAsStream();
      workbook.dispose();

      String downloadsPath = "";
      if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        downloadsPath = "$userProfile\\Downloads";
      } else {
        final dir = await getApplicationDocumentsDirectory();
        downloadsPath = dir.path;
      }

      final filePath = "$downloadsPath\\All_Leaves_Report.xlsx";
      final file = File(filePath);

      try {
        await file.writeAsBytes(bytes, flush: true);
        await OpenFilex.open(filePath);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ All leaves exported successfully!"),
              backgroundColor: Colors.green),
        );
      } on FileSystemException {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  "⚠️ Please close the Excel file before exporting again."),
              backgroundColor: Colors.orange),
        );
        return;
      }

      if (Platform.isWindows) {
        Process.start('explorer.exe', [filePath]);
      }
    } catch (e) {
      //print("error:   $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Failed to export: $e"),
            backgroundColor: Colors.red),
      );
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

  void _showReasonDialog(BuildContext context, String reason) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Leave Reason"),
          content: SingleChildScrollView(
            child: Text(
              reason.isNotEmpty ? reason : "No reason provided",
              style: const TextStyle(fontSize: 15),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );

  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'leave_approval_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  List<Map<String, dynamic>> employees = [];
  String? selectedEmployee;
  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    _fetchEmployeeNames();
    final today = DateTime.now();
    startDate = DateTime(today.year, today.month, today.day);
    endDate = startDate;
  }

  Future<void> _fetchEmployeeNames() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('users').get();

      final list = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          "uid": data["uid"]?.toString() ?? doc.id,
          "name": data["name"]?.toString() ?? "Unknown",
        };
      }).toList();

      setState(() {
        employees = List<Map<String, dynamic>>.from(list);
      });
    } catch (e) {
      print("Error fetching employees: $e");
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2026),
      initialDateRange: DateTimeRange(start: startDate!, end: endDate!),
    );

    if (picked != null) {
      setState(() {
        startDate = picked.start;
        endDate = picked.end;
      });
    }
  }

  void _showImageDialog(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(child: Image.network(url)),
      ),
    );
  }

  void _showFullAddressDialog(String address) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Full Address"),
        content: SelectableText(address),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  /*Stream<Map<String, List<Map<String, dynamic>>>> _combinedStream() async* {
    final attendanceQuery = FirebaseFirestore.instance.collection("attendance");
    final leavesQuery = FirebaseFirestore.instance.collection("leaves");

    DateTime start = startDate!;
    DateTime end = endDate!.add(const Duration(days: 1));

    final attendanceSnap = await attendanceQuery
        .where("punchInTime", isGreaterThanOrEqualTo: start)
        .where("punchInTime", isLessThan: end)
        .get();

    final leaveSnap = await leavesQuery
        .where("startDate", isLessThanOrEqualTo: end)
        .where("endDate", isGreaterThanOrEqualTo: start)
        .get();

    final attendance = attendanceSnap.docs.map((d) {
      final data = d.data();
      data["id"] = d.id;
      data["type"] = "attendance";
      return data;
    }).toList();

    final leaves = leaveSnap.docs.map((d) {
      final data = d.data();
      data["id"] = d.id;
      data["type"] = "leave";
      return data;
    }).toList();

    yield {"attendance": attendance, "leaves": leaves};
  }
   */

  Stream<Map<String, List<Map<String, dynamic>>>> _combinedStream() async* {
    final start = startDate!;
    final end = endDate!.add(const Duration(days: 1));

    final attendanceStream = FirebaseFirestore.instance
        .collection("attendance")
        .where("punchInTime", isGreaterThanOrEqualTo: start)
        .where("punchInTime", isLessThan: end)
        .snapshots();

    final leavesStream = FirebaseFirestore.instance
        .collection("leaves")
        .where("startDate", isLessThanOrEqualTo: end)
        .where("endDate", isGreaterThanOrEqualTo: start)
        .snapshots();

    await for (final attendanceSnap in attendanceStream) {
      final leaveSnap = await leavesStream.first; // re-use current leaves

      final attendance = attendanceSnap.docs.map((d) {
        final data = d.data();
        data["id"] = d.id;
        data["type"] = "attendance";
        return data;
      }).toList();

      final leaves = leaveSnap.docs.map((d) {
        final data = d.data();
        data["id"] = d.id;
        data["type"] = "leave";
        return data;
      }).toList();

      yield {"attendance": attendance, "leaves": leaves};
    }
  }


  Future<void> _exportToExcel(
      List<Map<String, dynamic>> attendance,
      List<Map<String, dynamic>> leaves,
      ) async {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];

    sheet.appendRow([
      'Employee',
      'Type',
      'Punch In',
      'Punch Out',
      'Date',
      'Total Hours',
      'Leave Status',
      'Exempt',
      'In Address',
      'Out Address',
      'Selfie In URL',
      'Selfie Out URL',
    ]);

    for (var record in attendance) {
      final employee = employees.firstWhere(
            (e) => e["uid"] == record["userId"],
        orElse: () => {"name": "Unknown"},
      );

      final punchInTime = (record["punchInTime"] as Timestamp?)?.toDate();
      final punchOutTime = (record["punchOutTime"] as Timestamp?)?.toDate();
      final duration = (punchInTime != null && punchOutTime != null)
          ? punchOutTime.difference(punchInTime)
          : null;

      sheet.appendRow([
        employee["name"] ?? "Unknown",
        "Attendance",
        punchInTime != null ? DateFormat('hh:mm a').format(punchInTime) : "-",
        punchOutTime != null ? DateFormat('hh:mm a').format(punchOutTime) : "-",
        punchInTime != null ? DateFormat('dd MMM yyyy').format(punchInTime) : "-",
        duration != null
            ? "${duration.inHours}h ${duration.inMinutes.remainder(60)}m"
            : "-",
        "-",
        record["isExempt"] == true ? "Yes" : "No",
        record["punchInAddress"] ?? "-",
        record["punchOutAddress"] ?? "-",
        record["punchInSelfieUrl"] ?? "-",
        record["punchOutSelfieUrl"] ?? "-",
      ]);
    }

    for (var leave in leaves) {
      final employee = employees.firstWhere(
            (e) => e["uid"] == leave["userId"],
        orElse: () => {"name": "Unknown"},
      );
      final start = (leave["startDate"] as Timestamp).toDate();
      final end = (leave["endDate"] as Timestamp).toDate();

      sheet.appendRow([
        employee["name"] ?? "Unknown",
        "Leave",
        "-",
        "-",
        "${DateFormat('dd MMM').format(start)} - ${DateFormat('dd MMM').format(end)}",
        "0h 0m",
        leave["status"] ?? "-",
        "-",
        "-",
        "-",
        "-",
        "-",
      ]);
    }

    String downloadsPath = "";
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      downloadsPath = "$userProfile\\Downloads";
    } else {
      final dir = await getApplicationDocumentsDirectory();
      downloadsPath = dir.path;
    }

    final filePath = "$downloadsPath\\attendance_leaves.xlsx";
    final fileBytes = excel.encode();
    if (fileBytes != null) {
      final file = File(filePath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(fileBytes);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ Exported successfully: $filePath")),
      );
      if (Platform.isWindows) Process.start('explorer.exe', [filePath]);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Dashboard"),
        centerTitle: true,
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('leaves')
                .where('status', isEqualTo: 'Pending')
                .snapshots(),
            builder: (context, snapshot) {
              final count = snapshot.data?.docs.length ?? 0;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications),
                    tooltip: "View Leave Requests",
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const LeaveApprovalScreen()),
                      );
                    },
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          count.toString(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: StreamBuilder<Map<String, List<Map<String, dynamic>>>>(
            stream: _combinedStream(),
            builder: (context, snapshot) {
              final today = DateTime.now();

              final attendance = snapshot.data?["attendance"] ?? [];
              final leaves = snapshot.data?["leaves"] ?? [];
              final allRecords = [...attendance, ...leaves]
                  .where((data) =>
              selectedEmployee == null ||
                  data["userId"] == selectedEmployee)
                  .toList();

              final hasRecords = allRecords.isNotEmpty;

              return Column(
                children: [
                  // 🔹 Always-visible Filters
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          hint: const Text("Filter by Employee"),
                          value: selectedEmployee,
                          items: employees
                              .map((e) => DropdownMenuItem<String>(
                            value: e["uid"],
                            child: Text(e["name"]),
                          ))
                              .toList(),
                          onChanged: (value) {
                            setState(() => selectedEmployee = value);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.clear),
                        label: const Text("Clear Filters"),
                        onPressed: () {
                          setState(() {
                            selectedEmployee = null;
                            startDate = DateTime(today.year, today.month, today.day);
                            endDate = startDate;
                          });
                        },
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.date_range),
                        label: Text(
                          startDate != null && endDate != null
                              ? "${DateFormat('dd MMM').format(startDate!)} - ${DateFormat('dd MMM yyyy').format(endDate!)}"
                              : "Select Date Range",
                        ),
                        onPressed: () => _selectDateRange(context),
                      ),
                      const SizedBox(width: 12),

                      // ✅ Export button only enabled when data is present
                      ElevatedButton.icon(
                        icon: const Icon(Icons.download),
                        label: const Text("Export to Excel"),
                        onPressed: hasRecords
                            ? () async {
                          _exportToExcel(attendance, leaves);
                        }
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 🔹 Data Section
                  Expanded(
                    child: !snapshot.hasData
                        ? const Center(child: CircularProgressIndicator())
                        : allRecords.isEmpty
                        ? const Center(
                      child: Text("No records found for selected range."),
                    )
                        : Scrollbar(
                      thumbVisibility: true,
                      trackVisibility: true,
                      interactive: true,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: Scrollbar(
                          thumbVisibility: true,
                          trackVisibility: true,
                          interactive: true,
                          notificationPredicate: (_) => true,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columnSpacing: 20,
                              dataRowMaxHeight: 70,
                              columns: const [
                                DataColumn(label: Text("Employee")),
                                DataColumn(label: Text("Type")),
                                DataColumn(label: Text("Selfie In")),
                                DataColumn(label: Text("In Address")),
                                DataColumn(label: Text("Selfie Out")),
                                DataColumn(label: Text("Out Address")),
                                DataColumn(label: Text("Punch In")),
                                DataColumn(label: Text("Punch Out")),
                                DataColumn(label: Text("Date / Range")),
                                DataColumn(label: Text("Total Hours")),
                                DataColumn(label: Text("Leave Status")),
                                DataColumn(label: Text("Exempt")),
                              ],
                              rows: allRecords.map((data) {
                                final isLeave = data["type"] == "leave";
                                final employee = employees.firstWhere(
                                      (e) => e["uid"] == data["userId"],
                                  orElse: () =>
                                  {"uid": "", "name": "Unknown"},
                                );

                                final punchInTime =
                                (data["punchInTime"] as Timestamp?)
                                    ?.toDate();
                                final punchOutTime =
                                (data["punchOutTime"] as Timestamp?)
                                    ?.toDate();
                                final duration = (punchInTime != null &&
                                    punchOutTime != null)
                                    ? punchOutTime.difference(punchInTime)
                                    : null;

                                return DataRow(
                                  color: WidgetStatePropertyAll(
                                      isLeave ? Colors.yellow[100] : null),
                                  cells: [
                                    DataCell(Text(employee["name"] ?? "Unknown")),
                                    DataCell(Text(isLeave
                                        ? "Leave"
                                        : "Attendance")),
                                    DataCell(isLeave
                                        ? const Text("-")
                                        : InkWell(
                                      onTap: () => _showImageDialog(
                                          data["punchInSelfieUrl"] ?? ""),
                                      child: Image.network(
                                        data["punchInSelfieUrl"] ?? "",
                                        width: 50,
                                        height: 50,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                        const Icon(Icons
                                            .image_not_supported),
                                      ),
                                    )),
                                    DataCell(isLeave
                                        ? const Text("-")
                                        : InkWell(
                                      onTap: () =>
                                          _showFullAddressDialog(
                                              data["punchInAddress"] ??
                                                  ""),
                                      child: SizedBox(
                                        width: 200,
                                        child: Text(
                                          data["punchInAddress"] ?? "-",
                                          maxLines: 2,
                                          overflow:
                                          TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )),
                                    DataCell(isLeave
                                        ? const Text("-")
                                        : InkWell(
                                      onTap: () => _showImageDialog(
                                          data["punchOutSelfieUrl"] ??
                                              ""),
                                      child: Image.network(
                                        data["punchOutSelfieUrl"] ?? "",
                                        width: 50,
                                        height: 50,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                        const Icon(Icons
                                            .image_not_supported),
                                      ),
                                    )),
                                    DataCell(isLeave
                                        ? const Text("-")
                                        : InkWell(
                                      onTap: () =>
                                          _showFullAddressDialog(
                                              data["punchOutAddress"] ??
                                                  ""),
                                      child: SizedBox(
                                        width: 200,
                                        child: Text(
                                          data["punchOutAddress"] ?? "-",
                                          maxLines: 2,
                                          overflow:
                                          TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )),
                                    DataCell(Text(isLeave
                                        ? "-"
                                        : punchInTime != null
                                        ? DateFormat('hh:mm a')
                                        .format(punchInTime)
                                        : "-")),
                                    DataCell(Text(isLeave
                                        ? "-"
                                        : punchOutTime != null
                                        ? DateFormat('hh:mm a')
                                        .format(punchOutTime)
                                        : "-")),
                                    DataCell(Text(isLeave
                                        ? "${DateFormat('dd MMM').format((data["startDate"] as Timestamp).toDate())} - ${DateFormat('dd MMM').format((data["endDate"] as Timestamp).toDate())}"
                                        : punchInTime != null
                                        ? DateFormat('dd MMM yyyy')
                                        .format(punchInTime)
                                        : "-")),
                                    DataCell(Text(isLeave
                                        ? "0h 0m"
                                        : duration != null
                                        ? "${duration.inHours}h ${duration.inMinutes.remainder(60)}m"
                                        : "-")),
                                    DataCell(Text(isLeave
                                        ? (data["status"] ?? "-")
                                        : "-")),
                                    DataCell(
                                      isLeave
                                          ? const Text("N/A")
                                          : StatefulBuilder(
                                        builder:
                                            (context, setInnerState) {
                                          final isExempt =
                                              data['isExempt'] ?? false;
                                          return ElevatedButton(
                                            onPressed: () async {
                                              final docRef =
                                              FirebaseFirestore
                                                  .instance
                                                  .collection(
                                                  "attendance")
                                                  .doc(data["id"]);
                                              await docRef.update(
                                                  {'isExempt': !isExempt});
                                              setInnerState(() =>
                                              data['isExempt'] =
                                              !isExempt);
                                            },
                                            style: ElevatedButton
                                                .styleFrom(
                                              backgroundColor: isExempt
                                                  ? Colors.green
                                                  : Colors.grey,
                                            ),
                                            child: Text(isExempt
                                                ? "Exempted"
                                                : "Mark Exempt"),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),



    );
  }
}

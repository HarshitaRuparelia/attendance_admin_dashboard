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
  List<Map<String, String>> employees = [];
  String? selectedEmployee;
  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    _fetchEmployeeNames();
  }

  /// 🔹 Fetch employees from Firestore `users` collection
  Future<void> _fetchEmployeeNames() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('users').get();

      final list = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          "uid": data["uid"]?.toString() ?? "",
          "name": data["name"]?.toString() ?? "Unknown",
        };
      }).toList();

      setState(() {
        employees = list;
      });
    } catch (e) {
      print("Error fetching employees: $e");
    }
  }

  /// 🔹 Get attendance stream (with safe filtering)
  Stream<QuerySnapshot> _getAttendanceStream() {
    Query query = FirebaseFirestore.instance.collection("attendance");

    if (selectedEmployee != null && selectedEmployee!.isNotEmpty) {
      query = query.where("userId", isEqualTo: selectedEmployee);
    }
    if (startDate != null && endDate != null) {
      final startOfRange = DateTime(startDate!.year, startDate!.month, startDate!.day);
      final endOfRange = DateTime(endDate!.year, endDate!.month, endDate!.day).add(const Duration(days: 1));

      query = query
          .where("punchInTime", isGreaterThanOrEqualTo: startOfRange)
          .where("punchInTime", isLessThan: endOfRange);
    }
    query = query.orderBy("punchInTime", descending: true);
    return query.snapshots();
  }

  /// 🔹 Select a date
  Future<void> _selectDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2026),
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

  /// 🔹 Open selfie in full screen
  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(
          child: Image.network(imageUrl, fit: BoxFit.contain),
        ),
      ),
    );
  }
  void _showFullAddressDialog(BuildContext context, String address) {
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
  Future<void> _exportToExcel(List<QueryDocumentSnapshot> docs) async {
    final excel = Excel.createExcel();

    final sheet = excel['Sheet1'];
    /*if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }*/
    // Header row
    sheet.appendRow([
      'Employee',
      'Punch In Time',
      'In Address',
      'In Selfie',
      'Punch Out Time',
      'Out Address',
      'Out Selfie',
      'Date',
      'Total Hours',
      'Late Mark'
    ]);

    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;

      final userId = data["userId"] ?? "";
      final employee = employees.firstWhere(
            (e) => e["uid"] == userId,
        orElse: () => {"name": "Unknown"},
      );

      final punchInTime = (data["punchInTime"] as Timestamp?)?.toDate();
      final punchOutTime = (data["punchOutTime"] as Timestamp?)?.toDate();
      final punchInAddress = data["punchInAddress"] ?? "-";
      final punchOutAddress = data["punchOutAddress"] ?? "-";
      final punchInSelfie = data["punchInSelfieUrl"] ?? "";
      final punchOutSelfie = data["punchOutSelfieUrl"] ?? "";

      final duration = (punchInTime != null && punchOutTime != null)
          ? punchOutTime.difference(punchInTime)
          : null;

      sheet.appendRow([
        employee["name"] ?? "Unknown",
        punchInTime != null ? DateFormat('hh:mm a').format(punchInTime) : "-",
        punchInAddress,
        punchInSelfie,
        punchOutTime != null ? DateFormat('hh:mm a').format(punchOutTime) : "-",
        punchOutAddress,
        punchOutSelfie,
        punchInTime != null
            ? DateFormat('dd MMM yyyy').format(punchInTime)
            : "-",
        duration != null
            ? "${duration.inHours}h ${duration.inMinutes.remainder(60)}m"
            : "-",
        data['isExempt'] == true ? "Exempted" : "Not Exempted",
      ]);
    }

    // Save file
    final dir = await getApplicationDocumentsDirectory();

    String downloadsPath = "";
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        downloadsPath = '$userProfile\\Downloads';
      } else {
        final tempDir = await getTemporaryDirectory();
        downloadsPath = tempDir.path;
      }
    } else {
      final dir = await getApplicationDocumentsDirectory();
      downloadsPath = dir.path;
    }

    final filePath = "$downloadsPath\\attendance_export.xlsx";
    final fileBytes = excel.encode();
    if (fileBytes != null) {
      try {
        final file = File(filePath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(fileBytes);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Exported successfully: $filePath")),
        );
        if (Platform.isWindows) {
          Process.start('explorer.exe', [filePath]);
        }
      }
      catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
              "❌ Failed to save file. Close any open Excel files.")),
        );
      }
    }
  }
  void _showLeaveRequests(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: SizedBox(
            width: 700,
            height: 500,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: const Text(
                    "Pending Leave Requests",
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection("leaves")
                        .where("status", isEqualTo: "Pending")
                        .orderBy("timestamp", descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(child: Text("Error: ${snapshot.error}"));
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(child: Text("No pending leave requests."));
                      }

                      final docs = snapshot.data!.docs;

                      return ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          final data = docs[index].data() as Map<String, dynamic>;
                          final startDate = (data['startDate'] as Timestamp).toDate();
                          final endDate = (data['endDate'] as Timestamp).toDate();
                          final userId = data["userId"] ?? "";
                          final employee = employees.firstWhere(
                                (e) => e["uid"] == userId,
                            orElse: () => {"name": "Unknown"},
                          );
                          return ListTile(
                            title: Text(
                              employee['name'] ?? "Unknown Employee",
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              "From: ${DateFormat('dd MMM yyyy').format(startDate)}\n"
                                  "To: ${DateFormat('dd MMM yyyy').format(endDate)}\n"
                                  "Reason: ${data['reason'] ?? '-'}",
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                  onPressed: () async {
                                    await FirebaseFirestore.instance
                                        .collection("leaves")
                                        .doc(docs[index].id)
                                        .update({"status": "Approved"});
                                  },
                                  child: const Text("Approve"),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                  onPressed: () async {
                                    await FirebaseFirestore.instance
                                        .collection("leaves")
                                        .doc(docs[index].id)
                                        .update({"status": "Rejected"});
                                  },
                                  child: const Text("Reject"),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
                          builder: (context) => const LeaveApprovalScreen(),
                        ),
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
                            fontWeight: FontWeight.bold,
                          ),
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
        child: Column(
          children: [
            /// 🔹 Filters Row
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: selectedEmployee,
                    hint: const Text("Select Employee"),
                    items: employees.map((emp) {
                      return DropdownMenuItem<String>(
                        value: emp["uid"],
                        child: Text(emp["name"] ?? "Unknown"),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedEmployee = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),

                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      startDate == null || endDate == null
                          ? "Select Date Range"
                          : "${DateFormat('dd MMM').format(startDate!)} - ${DateFormat('dd MMM yyyy').format(endDate!)}",
                    ),
                    onPressed: () => _selectDateRange(context),
                  ),
                ),

                const SizedBox(width: 16),
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
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text("Export to Excel"),
                  onPressed: () async {
                    final snapshot = await _getAttendanceStream().first;
                    final docs = snapshot.docs;
                    if (docs.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("No data to export")),
                      );
                      return;
                    }
                    await _exportToExcel(docs);
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

            /// 🔹 Attendance Table
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _getAttendanceStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text("No attendance records found."));
                  }

                  final docs = snapshot.data!.docs;

                  final ScrollController _horizontalController = ScrollController();
                  final ScrollController _verticalController = ScrollController();

                  return Scrollbar(
                    controller: _horizontalController,
                    thumbVisibility: true, // Always show scroll thumb
                    trackVisibility: true,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      controller: _horizontalController,
                      child: Scrollbar(
                        controller: _verticalController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          controller: _verticalController,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 1300), // Force full table width
                            child: DataTable(
                              columnSpacing: 20,
                              columns: const [
                                DataColumn(label: Text("Employee")),
                                DataColumn(label: Text("Punch In Time")),
                                DataColumn(label: Text("In Address")),
                                DataColumn(label: Text("In Selfie")),
                                DataColumn(label: Text("Punch Out Time")),
                                DataColumn(label: Text("Out Address")),
                                DataColumn(label: Text("Out Selfie")),
                                DataColumn(label: Text("Date")),
                                DataColumn(label: Text("Total Hours")),
                                DataColumn(label: Text("Late Mark")),
                              ],
                              rows: docs.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                final userId = data["userId"] ?? "";
                                final employee = employees.firstWhere(
                                      (e) => e["uid"] == userId,
                                  orElse: () => {"name": "Unknown"},
                                );

                                final punchInTime = (data["punchInTime"] as Timestamp?)?.toDate();
                                final punchOutTime = (data["punchOutTime"] as Timestamp?)?.toDate();
                                final punchInAddress = data["punchInAddress"] ?? "-";
                                final punchOutAddress = data["punchOutAddress"] ?? "-";
                                final punchInSelfie = data["punchInSelfieUrl"] ?? "";
                                final punchOutSelfie = data["punchOutSelfieUrl"] ?? "";
                                final duration = (punchInTime != null && punchOutTime != null)
                                    ? punchOutTime.difference(punchInTime)
                                    : null;

                                return DataRow(
                                  cells: [
                                    DataCell(Text(employee["name"] ?? "Unknown")),
                                    DataCell(Text(punchInTime != null
                                        ? DateFormat('hh:mm a').format(punchInTime)
                                        : "-")),
                                    DataCell(
                                      InkWell(
                                        onTap: () => _showFullAddressDialog(context, punchInAddress),
                                        child: SizedBox(
                                          width: 200,
                                          child: Text(
                                            punchInAddress,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      punchInSelfie.isNotEmpty
                                          ? InkWell(
                                        onTap: () => _showImageDialog(punchInSelfie),
                                        child: Image.network(punchInSelfie, height: 50),
                                      )
                                          : const Text("-"),
                                    ),
                                    DataCell(Text(punchOutTime != null
                                        ? DateFormat('hh:mm a').format(punchOutTime)
                                        : "-")),
                                    DataCell(
                                      InkWell(
                                        onTap: () => _showFullAddressDialog(context, punchOutAddress),
                                        child: SizedBox(
                                          width: 200,
                                          child: Text(
                                            punchOutAddress,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      punchOutSelfie.isNotEmpty
                                          ? InkWell(
                                        onTap: () => _showImageDialog(punchOutSelfie),
                                        child: Image.network(punchOutSelfie, height: 50),
                                      )
                                          : const Text("-"),
                                    ),
                                    DataCell(Text(punchInTime != null
                                        ? DateFormat('dd MMM yyyy').format(punchInTime)
                                        : "-")),
                                    DataCell(
                                      duration != null
                                          ? Row(
                                        children: [
                                          if (duration.inHours < 9 && !(data['isExempt'] ?? false))
                                            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                                          const SizedBox(width: 4),
                                          Text(
                                            duration.inHours < 9 && !(data['isExempt'] ?? false)
                                                ? "Half Day (${duration.inHours}h ${duration.inMinutes.remainder(60)}m)"
                                                : "${duration.inHours}h ${duration.inMinutes.remainder(60)}m",
                                            style: TextStyle(
                                              color: (duration.inHours < 9 && !(data['isExempt'] ?? false))
                                                  ? Colors.red
                                                  : Colors.black,
                                              fontWeight: (duration.inHours < 9 && !(data['isExempt'] ?? false))
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      )
                                          : const Text("-"),
                                    ),
                                    DataCell(
                                      ElevatedButton(
                                        onPressed: () async {
                                          // Toggle exemption in Firestore
                                          final docRef = FirebaseFirestore.instance.collection("attendance").doc(doc.id);
                                          final currentExempt = data['isExempt'] ?? false;
                                          await docRef.update({'isExempt': !currentExempt});
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: (data['isExempt'] ?? false) ? Colors.green : Colors.grey,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        ),
                                        child: Text((data['isExempt'] ?? false) ? "Exempted" : "Mark Exempt"),
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
                  );

                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

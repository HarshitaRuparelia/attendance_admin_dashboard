import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'leave_approval_screen.dart';
import 'holiday_calendar_dialog.dart';
import 'package:rxdart/rxdart.dart';

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
  final ScrollController _scrollController = ScrollController();

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
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();

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
      builder: (context) =>
          Dialog(child: InteractiveViewer(child: Image.network(url))),
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

  Stream<Map<String, List<Map<String, dynamic>>>> _combinedStream() {
    final start = startDate!;
    final end = endDate!.add(const Duration(days: 1));
    print("✅ Combined stream refreshed for $startDate → $endDate");

    final attendanceStream = FirebaseFirestore.instance
        .collection("attendance")
        .where("punchInTime", isGreaterThanOrEqualTo: start)
        .where("punchInTime", isLessThan: end)
        .snapshots();

    final leavesStream = FirebaseFirestore.instance
        .collection("leaves")
        .snapshots();

    final holidaysStream = FirebaseFirestore.instance
        .collection("holidays")
        .where("date", isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where("date", isLessThan: Timestamp.fromDate(end))
        .snapshots();

    return Rx.combineLatest3(attendanceStream, leavesStream, holidaysStream, (
      QuerySnapshot attendanceSnap,
      QuerySnapshot leaveSnap,
      QuerySnapshot holidaySnap,
    ) {
      final attendance = attendanceSnap.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        data["id"] = d.id;
        data["type"] = "attendance";
        return data;
      }).toList();

      final leaves = leaveSnap.docs
          .map((d) {
            final data = d.data() as Map<String, dynamic>;
            data["id"] = d.id;
            data["type"] = "leave";
            return data;
          })
          .where((leave) {
            final sDate = (leave["startDate"] as Timestamp).toDate();
            final eDate = (leave["endDate"] as Timestamp).toDate();
            return sDate.isBefore(end) && eDate.isAfter(start);
          })
          .toList();

      final holidays = holidaySnap.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        data["id"] = d.id;
        data["type"] = "holiday";
        return data;
      }).toList();

      return {"attendance": attendance, "leaves": leaves, "holidays": holidays};
    });
  }

  Future<void> _exportToExcel(
    List<Map<String, dynamic>> attendance,
    List<Map<String, dynamic>> leaves,
    List<Map<String, dynamic>> holidays,
  ) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];

      sheet.appendRow([
        'Employee',
        'Type',
        'Punch In',
        'Punch Out',
        'Date',
        'Total Minutes',
        'Leave Status',
        'Exempt Status',
        'In Address',
        'Out Address',
        'Selfie In URL',
        'Selfie Out URL',
        'Leave/Holiday Name',
      ]);

      for (var record in attendance) {
        final employee = employees.firstWhere(
              (e) => e["uid"] == record["userId"],
          orElse: () => {"name": "Unknown"},
        );

        final punchInTime = (record["punchInTime"] as Timestamp?)?.toDate();
        final punchOutTime = (record["punchOutTime"] as Timestamp?)?.toDate();

        final exemptionStatus = record["exemptionStatus"] ?? "none";

        // Duration in minutes (if punchOut exists)
        final totalMinutes = record['totalHours'] ?? 0;

        // Exempt status text
        String exemptText;
        if (punchInTime != null && punchOutTime == null) {
          exemptText = "Not punched out yet";
        } else if (exemptionStatus == "requested") {
          exemptText = "Exemption Requested";
        } else if (exemptionStatus == "approved") {
          exemptText = "Approved";
        } else {
          exemptText = "Mark Exempt";
        }

        sheet.appendRow([
          employee["name"] ?? "Unknown",
          "Attendance",
          punchInTime != null ? DateFormat('hh:mm a').format(punchInTime) : "-",
          punchOutTime != null
              ? DateFormat('hh:mm a').format(punchOutTime)
              : "-",
          punchInTime != null
              ? DateFormat('dd MMM yyyy').format(punchInTime)
              : "-",
          totalMinutes, // 0 if not punched out
          "-", // leave status
          exemptText,
          record["punchInAddress"] ?? "-",
          record["punchOutAddress"] ?? "-",
          record["punchInSelfieUrl"] ?? "-",
          record["punchOutSelfieUrl"] ?? "-",
          "-", // holiday name
        ]);
      }


      // Leave rows
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
          0,
          leave["status"] ?? "-",
          "-",
          "-",
          "-",
          "-",
          "-",
          leave["reason"] ?? "-", // no holiday name
        ]);
      }

      // Holiday rows
      for (var holiday in holidays) {
        final date = (holiday["date"] as Timestamp?)?.toDate();
        sheet.appendRow([
          "-",
          "Holiday",
          "-",
          "-",
          date != null ? DateFormat('dd MMM yyyy').format(date) : "-",
          0,
          "-",
          "-",
          "-",
          "-",
          "-",
          "-",
          holiday["name"] ?? "-", // ✅ include holiday name
        ]);
      }

      // Save Excel
      String downloadsPath = "";
      if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        downloadsPath = "$userProfile\\Downloads";
      } else {
        final dir = await getApplicationDocumentsDirectory();
        downloadsPath = dir.path;
      }

      final filePath = "$downloadsPath\\Attendance_leaves_Report.xlsx";
      final fileBytes = excel.encode();

      if (fileBytes != null) {
        final file = File(filePath);
        try {
          file.createSync(recursive: true);
          file.writeAsBytesSync(fileBytes);
        } on FileSystemException {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "⚠️ Please close the Excel file before exporting again.",
              ),
            ),
          );
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ Exported successfully: $filePath")),
        );

        if (Platform.isWindows) {
          Process.start('explorer.exe', [filePath]);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("❌ Failed to export: $e")));
    }
  }
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Dashboard"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: "Mark Holiday",
            onPressed: () async {
              final updated = await showDialog<bool>(
                context: context,
                builder: (context) => const HolidayCalendarDialog(),
              );
              if (updated == true) {
                setState(() {
                  // just trigger rebuild — StreamBuilder will refresh
                });
              }
            },
          ),
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
        child: StreamBuilder<Map<String, List<Map<String, dynamic>>>>(
          stream: _combinedStream(),
          builder: (context, snapshot) {
            final today = DateTime.now();

            final attendance = snapshot.data?["attendance"] ?? [];
            final leaves = snapshot.data?["leaves"] ?? [];
            final holidays = snapshot.data?["holidays"] ?? [];

            final allRecords = [...attendance, ...leaves, ...holidays]
                .where(
                  (data) =>
                      selectedEmployee == null ||
                      data["userId"] == selectedEmployee ||
                      data["type"] == "holiday",
                )
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
                        hint: const Text("Select Employee"),
                        value: selectedEmployee,
                        items: employees
                            .map(
                              (e) => DropdownMenuItem<String>(
                                value: e["uid"],
                                child: Text(e["name"]),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() => selectedEmployee = value);
                        },
                      ),
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
                    ElevatedButton.icon(
                      icon: const Icon(Icons.clear),
                      label: const Text("Clear Filters"),
                      onPressed: () {
                        setState(() {
                          selectedEmployee = null;
                          startDate = DateTime(
                            today.year,
                            today.month,
                            today.day,
                          );
                          endDate = startDate;
                        });
                      },
                    ),
                    const SizedBox(width: 12),


                    // ✅ Export button only enabled when data is present
                    ElevatedButton.icon(
                      icon: const Icon(Icons.download_for_offline),
                      label: const Text("Export to Excel"),
                      onPressed: hasRecords
                          ? () async {
                              _exportToExcel(attendance, leaves, holidays);
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
                          controller: _scrollController,
                          thumbVisibility: true,
                          trackVisibility: true,
                          interactive: true,
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            scrollDirection: Axis.vertical,
                            child: Scrollbar(
                              thumbVisibility: true,
                              trackVisibility: true,
                              interactive: true,
                              notificationPredicate: (_) => true,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columnSpacing: 15,
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
                                    final type = data["type"];
                                    final isLeave = type == "leave";
                                    final isHoliday = type == "holiday";

                                    final employee = employees.firstWhere(
                                      (e) => e["uid"] == data["userId"],
                                      orElse: () => {
                                        "uid": "",
                                        "name": "Unknown",
                                      },
                                    );

                                    final punchInTime =
                                        (data["punchInTime"] as Timestamp?)
                                            ?.toDate();
                                    final punchOutTime =
                                        (data["punchOutTime"] as Timestamp?)
                                            ?.toDate();
                                    /*final duration =
                                        (punchInTime != null &&
                                            punchOutTime != null)
                                        ? punchOutTime.difference(punchInTime)
                                        : null;*/

                                    final exemptionStatus =
                                        data['exemptionStatus'] ?? "none";
                                    bool isHalfDay = false;
                                    String totalHoursText = "-";

                                    if (!isLeave &&
                                        !isHoliday) {
                                      if (punchOutTime == null) {
                                        // ❗ User did NOT punch out
                                        totalHoursText = "-";
                                      }
                                      else {
                                        // Use totalMinutes from DB
                                        final totalMinutes = data['totalHours'] ??
                                            0; // totalHours stored in minutes
                                        final hours = totalMinutes ~/ 60;
                                        final minutes = totalMinutes % 60;

                                        if (hours < 9 &&
                                            exemptionStatus != "approved") {
                                          isHalfDay = true;
                                          totalHoursText =
                                          "$hours h ${minutes.toString().padLeft(2, '0')} m (Half Day)";
                                        } else {
                                          totalHoursText =
                                          "$hours h ${minutes.toString().padLeft(2, '0')} m";
                                        }
                                      }
                                      } else if (isLeave) {
                                      totalHoursText = "0 h 00 m";
                                    } else if (isHoliday) {
                                      totalHoursText = "-";
                                    }


                                    final rowColor = isHoliday
                                        ? Colors.green[100]
                                        : isLeave
                                        ? Colors.yellow[50]
                                        : null;

                                    return DataRow(
                                      color: WidgetStatePropertyAll(rowColor),
                                      cells: [
                                        DataCell(
                                          Text(
                                            isHoliday
                                                ? "-"
                                                : employee["name"] ?? "Unknown",
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            isHoliday
                                                ? "Holiday"
                                                : isLeave
                                                ? "Leave"
                                                : "Attendance",
                                          ),
                                        ),
                                        DataCell(
                                          isLeave || isHoliday
                                              ? const Text("-")
                                              : InkWell(
                                                  onTap: () => _showImageDialog(
                                                    data["punchInSelfieUrl"] ??
                                                        "",
                                                  ),
                                                  child: Image.network(
                                                    data["punchInSelfieUrl"] ??
                                                        "",
                                                    width: 50,
                                                    height: 50,
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (
                                                          _,
                                                          __,
                                                          ___,
                                                        ) => const Icon(
                                                          Icons
                                                              .image_not_supported,
                                                        ),
                                                  ),
                                                ),
                                        ),
                                        DataCell(
                                          isLeave || isHoliday
                                              ? const Text("-")
                                              : InkWell(
                                                  onTap: () =>
                                                      _showFullAddressDialog(
                                                        data["punchInAddress"] ??
                                                            "",
                                                      ),
                                                  child: SizedBox(
                                                    width: 200,
                                                    child: Text(
                                                      data["punchInAddress"] ??
                                                          "-",
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                        ),
                                        DataCell(
                                          isLeave || isHoliday
                                              ? const Text("-")
                                              : InkWell(
                                                  onTap: () => _showImageDialog(
                                                    data["punchOutSelfieUrl"] ??
                                                        "",
                                                  ),
                                                  child: Image.network(
                                                    data["punchOutSelfieUrl"] ??
                                                        "",
                                                    width: 50,
                                                    height: 50,
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (
                                                          _,
                                                          __,
                                                          ___,
                                                        ) => const Icon(
                                                          Icons
                                                              .image_not_supported,
                                                        ),
                                                  ),
                                                ),
                                        ),
                                        DataCell(
                                          isLeave || isHoliday
                                              ? const Text("-")
                                              : InkWell(
                                                  onTap: () =>
                                                      _showFullAddressDialog(
                                                        data["punchOutAddress"] ??
                                                            "",
                                                      ),
                                                  child: SizedBox(
                                                    width: 200,
                                                    child: Text(
                                                      data["punchOutAddress"] ??
                                                          "-",
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                        ),
                                        DataCell(
                                          isLeave || isHoliday
                                              ? const Text("-")
                                              : Tooltip(
                                            message: data['isLate'] == true ? "⚠️ Late Punch In" : "",
                                            child: Text(
                                              punchInTime != null
                                                  ? DateFormat('hh:mm a').format(punchInTime)
                                                  : "-",
                                              style: TextStyle(
                                                color: (data['isLate'] == true) ? Colors.red : Colors.black,
                                                fontWeight: (data['isLate'] == true)
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                          ),
                                        ),

                                        DataCell(
                                          Text(
                                            isLeave || isHoliday
                                                ? "-"
                                                : punchOutTime != null
                                                ? DateFormat(
                                                    'hh:mm a',
                                                  ).format(punchOutTime)
                                                : "-",
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            isHoliday
                                                ? DateFormat(
                                                    'dd MMM yyyy',
                                                  ).format(
                                                    (data["date"] as Timestamp)
                                                        .toDate(),
                                                  )
                                                : isLeave
                                                ? "${DateFormat('dd MMM').format((data["startDate"] as Timestamp).toDate())} - ${DateFormat('dd MMM').format((data["endDate"] as Timestamp).toDate())}"
                                                : punchInTime != null
                                                ? DateFormat(
                                                    'dd MMM yyyy',
                                                  ).format(punchInTime)
                                                : "-",
                                          ),
                                        ),
                                        DataCell(
                                          (isHalfDay &&
                                                  (data['exemptionStatus'] !=
                                                      "approved"))
                                              ? Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.access_time_filled,
                                                      color: Colors.red,
                                                      size: 20,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        totalHoursText,
                                                        style: const TextStyle(
                                                          color: Colors.red,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : Row(
                                                  children: [
                                                    if (data['exemptionStatus'] ==
                                                        "approved")
                                                      Tooltip(
                                                        message:
                                                            "Exempted by Admin",
                                                        waitDuration: Duration(
                                                          milliseconds: 300,
                                                        ),
                                                        child: const Icon(
                                                          Icons.verified_user,
                                                          color: Colors.green,
                                                          size: 20,
                                                        ),
                                                      ),
                                                    if (data['exemptionStatus'] ==
                                                        "approved")
                                                      const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        totalHoursText,
                                                        style: TextStyle(
                                                          color:
                                                              data['exemptionStatus'] ==
                                                                  "approved"
                                                              ? Colors.green
                                                              : Colors.black,
                                                          fontWeight:
                                                              data['exemptionStatus'] ==
                                                                  "approved"
                                                              ? FontWeight.bold
                                                              : FontWeight
                                                                    .normal,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                        ),

                                        DataCell(
                                          Text(
                                            isHoliday
                                                ? data["name"] ?? "-"
                                                : isLeave
                                                ? (data["status"] ?? "-")
                                                : "-",
                                          ),
                                        ),
                                        DataCell(
                                          isLeave || isHoliday
                                              ? const Text("N/A")
                                              : StatefulBuilder(
                                            builder: (context, setInnerState) {
                                              final exemptionStatus = data['exemptionStatus'] ?? "none";
                                              final punchOutTime = data["punchOutTime"] as Timestamp?;

                                              String buttonText;
                                              Color buttonColor;

                                              if (punchOutTime == null) {
                                                buttonText = "Not punched out yet";
                                                buttonColor = Colors.redAccent;
                                              } else if (exemptionStatus == "requested") {
                                                buttonText = "Exemption Requested";
                                                buttonColor = Colors.orangeAccent;
                                              } else if (exemptionStatus == "approved") {
                                                buttonText = "Exempted ✅";
                                                buttonColor = Colors.green;
                                              } else {
                                                buttonText = "Mark Exempt";
                                                buttonColor = Colors.grey;
                                              }

                                              return ElevatedButton(
                                                onPressed: (exemptionStatus == "approved" || punchOutTime == null)
                                                    ? null
                                                    : () async {
                                                  final docRef = FirebaseFirestore.instance
                                                      .collection("attendance")
                                                      .doc(data["id"]);
                                                  await docRef.update({'exemptionStatus': "approved"});
                                                  setInnerState(() => data['exemptionStatus'] = "approved");
                                                  setState(() {});
                                                },
                                                style: ElevatedButton.styleFrom(backgroundColor: buttonColor),
                                                child: Text(buttonText),
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

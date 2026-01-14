import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'leave_approval_screen.dart';
import 'holiday_calendar_dialog.dart';
import 'package:rxdart/rxdart.dart';
import 'package:data_table_2/data_table_2.dart';

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
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 1, 0, 1),
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
  double calculateTotalHours(List<Map<String, dynamic>> attendance) {
    int totalMinutes = 0;

    for (final a in attendance) {
      final minutes = a['totalHours'];
      if (minutes is int && minutes > 0) {
        totalMinutes += minutes;
      }
    }

    // Convert minutes → hours (2 decimal places)
    return double.parse((totalMinutes / 60).toStringAsFixed(2));
  }


  Stream<Map<String, List<Map<String, dynamic>>>> _combinedStream() {
    final DateTime start = DateTime(startDate!.year, startDate!.month, startDate!.day);
    final DateTime end = DateTime(endDate!.year, endDate!.month, endDate!.day, 23, 59, 59);

    print("✅ Combined stream refreshed for $start → $end");

    // --- ATTENDANCE: punchIn inside the range ---
    final attendanceStream = FirebaseFirestore.instance
        .collection("attendance")
        .where("punchInTime", isLessThanOrEqualTo: Timestamp.fromDate(end))
        .snapshots();

    // --- LEAVES: any part of leave overlapping range ---
    final leaveStream = FirebaseFirestore.instance
        .collection("leaves")
        .where("startDate", isLessThanOrEqualTo: Timestamp.fromDate(end))
        .snapshots();

    // --- HOLIDAYS inside range ---
    final holidayStream = FirebaseFirestore.instance
        .collection("holidays")
        .where("date", isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where("date", isLessThanOrEqualTo: Timestamp.fromDate(end))
        .snapshots();

    return Rx.combineLatest3(
      attendanceStream,
      leaveStream,
      holidayStream,
          (QuerySnapshot attendanceSnap,
          QuerySnapshot leaveSnap,
          QuerySnapshot holidaySnap) {

        // --- Helper: Check date overlap between two ranges ---
        bool overlaps(DateTime aStart, DateTime aEnd) {
          return aStart.isBefore(end) && aEnd.isAfter(start);
        }

        // --------------------
        // ATTENDANCE PROCESSING
        // --------------------
        final attendance = attendanceSnap.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          data["id"] = doc.id;
          data["type"] = "attendance";
          return data;
        }).where((rec) {
          final punchIn = (rec["punchInTime"] as Timestamp?)?.toDate();
          final punchOut = (rec["punchOutTime"] as Timestamp?)?.toDate() ?? punchIn;

          if (punchIn == null) return false;
          return overlaps(punchIn, punchOut!);
        }).toList();

        // --------------------
        // LEAVES PROCESSING
        // --------------------
        final leaves = leaveSnap.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          data["id"] = doc.id;
          data["type"] = "leave";
          return data;
        }).where((leave) {
          final s = (leave["startDate"] as Timestamp).toDate();
          final e = (leave["endDate"] as Timestamp).toDate();
          return !s.isAfter(end) && !e.isBefore(start); // ✅ inclusive check
        }).toList();


        // --------------------
        // HOLIDAYS
        // --------------------
        final holidays = holidaySnap.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          data["id"] = doc.id;
          data["type"] = "holiday";
          return data;
        }).toList();

        // RETURN COMBINED
        return {
          "attendance": attendance,
          "leaves": leaves,
          "holidays": holidays,
        };
      },
    );
  }

  bool isInDateRange(DateTime date) {
    if (startDate == null && endDate == null) return true;

    final start = startDate != null
        ? DateTime(startDate!.year, startDate!.month, startDate!.day)
        : null;

    final end = endDate != null
        ? DateTime(endDate!.year, endDate!.month, endDate!.day, 23, 59, 59)
        : null;

    if (start != null && end != null) {
      return !date.isBefore(start) && !date.isAfter(end);
    }

    if (start != null) {
      return !date.isBefore(start);
    }

    if (end != null) {
      return !date.isAfter(end);
    }

    return true;
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
        'Total Hours',
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
        final totalMinutes = (record['totalHours'] ?? 0) as int;
        final totalHours = (totalMinutes / 60);

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
          totalHours, // 0 if not punched out
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

        final sameDay = DateUtils.isSameDay(start, end);
        String date = "";

        if (sameDay) {
          date = DateFormat('dd MMM yyyy').format(start);
        }
        else {
          date = "${DateFormat('dd MMM yyyy').format(start)} - ${DateFormat('dd MMM yyyy').format(end)}";
        }


        sheet.appendRow([
          employee["name"] ?? "Unknown",
          "Leave",
          "-",
          "-",
          date,
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

            // 🔹 Employee filter
            final filteredAttendance = selectedEmployee == null
                ? attendance
                : attendance.where((a) => a["userId"] == selectedEmployee).toList();

            final filteredLeaves = selectedEmployee == null
                ? leaves
                : leaves.where((l) => l["userId"] == selectedEmployee).toList();

            // Holidays are global
            final filteredHolidays = holidays;
            final dateFilteredAttendance = filteredAttendance.where((a) {
              final punchIn = (a["punchInTime"] as Timestamp?)?.toDate();
              return punchIn != null && isInDateRange(punchIn);
            }).toList();
            final totalWorkedHours = calculateTotalHours(dateFilteredAttendance);

            final dateFilteredLeaves = filteredLeaves.where((l) {
              final start = (l["startDate"] as Timestamp).toDate();
              final end = (l["endDate"] as Timestamp).toDate();

              if (startDate != null && endDate != null) {
                return !(end.isBefore(startDate!) || start.isAfter(endDate!));
              }

              if (startDate != null && endDate == null) {
                return !startDate!.isBefore(start) && !startDate!.isAfter(end);
              }

              return true;
            }).toList();

            final dateFilteredHolidays = filteredHolidays.where((h) {
              final date = (h["date"] as Timestamp?)?.toDate();
              return date != null && isInDateRange(date);
            }).toList();

            final allRecords = [
              ...dateFilteredAttendance,
              ...dateFilteredLeaves,
              ...dateFilteredHolidays,
            ];

            final hasRecords = allRecords.isNotEmpty;

            return Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: BoxBorder.all(color: Colors.black45),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        selectedEmployee == null
                            ? "All Employees"
                            : employees
                            .firstWhere(
                              (e) => e["uid"] == selectedEmployee,
                          orElse: () => {"name": "Unknown"},
                        )["name"] ??
                            "Unknown",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      Text(
                        "Total Hours: $totalWorkedHours hrs",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),

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
                        startDate == endDate
                            ? DateFormat('dd MMM yyyy').format(startDate!)
                            : "${DateFormat('dd MMM').format(startDate!)} - ${DateFormat('dd MMM yyyy').format(endDate!)}"


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
                              _exportToExcel(dateFilteredAttendance, dateFilteredLeaves, dateFilteredHolidays);
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
                : DataTable2(
            fixedTopRows: 1,                       // ❄ Freeze header
            columnSpacing: 6,
            headingRowHeight: 56,
            dataRowHeight: 70,
           minWidth: 1400,                        // Table width
            //horizontalMargin: 10,
            scrollController: _scrollController,
            columns: const [
            DataColumn2(label: Text("Employee")),
            DataColumn2(label: Text("Type")),
            DataColumn2(label: Text("Selfie In")),
            DataColumn2(label: Text("In Address")),
            DataColumn2(label: Text("Selfie Out")),
            DataColumn2(label: Text("Out Address")),
            DataColumn2(label: Text("Punch In")),
            DataColumn2(label: Text("Punch Out")),
            DataColumn2(label: Text("Date / Range")),
            DataColumn2(label: Text("Total Hours")),
            DataColumn2(label: Text("Leave Status")),
            DataColumn2(label: Text("Exempt")),
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
                                        ? Colors.green[200]
                                        : isLeave
                                        ? Colors.yellow[200]
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

                                    Container(
                                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                    decoration: BoxDecoration(
                                    color: data['autoLogout'] == true ? Colors.red.withOpacity(0.15) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                    isLeave || isHoliday
                                    ? "-"
                                        : punchOutTime != null
                                        ? "${DateFormat('hh:mm a').format(punchOutTime)}${data['autoLogout']==true ? ' \n(Auto punch-out)' : ''}"
                                        : "-",
                                    ),
                                    ),
                                    ),


                                    DataCell(
                                          Text(
                                            isHoliday
                                                ? DateFormat('dd MMM yyyy').format((data["date"] as Timestamp).toDate())
                                                : isLeave
                                                ? () {
                                              final leaveStart = (data["startDate"] as Timestamp).toDate();
                                              final leaveEnd = (data["endDate"] as Timestamp).toDate();
                                              return leaveStart == leaveEnd
                                                  ? DateFormat('dd MMM yyyy').format(leaveStart)
                                                  : "${DateFormat('dd MMM').format(leaveStart)} - ${DateFormat('dd MMM').format(leaveEnd)}";
                                            }()
                                                : punchInTime != null
                                                ? DateFormat('dd MMM yyyy').format(punchInTime)
                                                : "-",
                                          ),
                                        ),



                                        DataCell(
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              minWidth: 120, // 👈 adjust until one-line
                                            ),
                                            child: Row(
                                              children: [
                                                if (isHalfDay && data['exemptionStatus'] != "approved") ...[
                                                  const Icon(Icons.access_time_filled, color: Colors.red, size: 20),
                                                  const SizedBox(width: 6),
                                                ],

                                                if (!isHalfDay && data['exemptionStatus'] == "approved") ...[
                                                  Tooltip(
                                                    message: "Exempted by Admin",
                                                    child: const Icon(Icons.verified_user,
                                                        color: Colors.green, size: 20),
                                                  ),
                                                  const SizedBox(width: 6),
                                                ],

                                                Expanded(
                                                  child: Text(
                                                    totalHoursText,
                                                    maxLines: 1,
                                                    softWrap: false,
                                                    overflow: TextOverflow.visible, // 👈 no wrapping, no ellipsis
                                                    style: TextStyle(
                                                      color: (data['exemptionStatus'] == "approved")
                                                          ? Colors.green
                                                          : (isHalfDay ? Colors.red : Colors.black),
                                                      fontWeight: (data['exemptionStatus'] == "approved" ||
                                                          isHalfDay)
                                                          ? FontWeight.bold
                                                          : FontWeight.normal,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
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
                                              : Builder(
                                            builder: (context) {
                                              final exemptionStatus = data['exemptionStatus'] ?? "none";
                                              final punchOutTime = data["punchOutTime"] as Timestamp?;

                                              String buttonText;
                                              Color buttonColor;
                                              bool enabled = true;

                                              if (punchOutTime == null) {
                                                buttonText = "Not punched out yet";
                                                buttonColor = Colors.redAccent;
                                                enabled = false;
                                              } else if (exemptionStatus == "requested") {
                                                buttonText = "Exemption Requested";
                                                buttonColor = Colors.orangeAccent;
                                              } else if (exemptionStatus == "approved") {
                                                buttonText = "Exempted ✅";
                                                buttonColor = Colors.green;
                                                enabled = false;
                                              } else {
                                                buttonText = "Mark Exempt";
                                                buttonColor = Colors.grey;
                                              }

                                              return ConstrainedBox(
                                                constraints: const BoxConstraints(
                                                  minWidth: 250,   // 👈 make this big to force max width
                                                ), // 👈 prevents overflow inside DataTable
                                                child: ElevatedButton(
                                                  onPressed: enabled
                                                      ? () async {
                                                    await FirebaseFirestore.instance
                                                        .collection("attendance")
                                                        .doc(data["id"])
                                                        .update({'exemptionStatus': "approved"});

                                                    setState(() {
                                                      data['exemptionStatus'] = "approved";
                                                    });
                                                  }
                                                      : null,
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: buttonColor,
                                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                                  ),
                                                  child: Text(
                                                    buttonText,
                                                    maxLines: 2,
                                                    //softWrap: false,
                                                   overflow: TextOverflow.visible,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),


                                      ],
                                    );
                                  }).toList(),

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

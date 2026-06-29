import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'employee_monthly_summary_screen.dart';
import 'leave_approval_screen.dart';
import 'ope_claim_approval_screen.dart';
import 'employee_management_screen.dart';
import 'leave_balance_screen.dart';
import 'holiday_calendar_dialog.dart';
import 'package:rxdart/rxdart.dart';
import 'package:data_table_2/data_table_2.dart';

import 'user_logs_screen.dart';
import 'clock_hours_screen.dart';
import 'employee_utils.dart';
import 'searchable_employee_dropdown.dart';
import 'attendance_utils.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  List<Map<String, dynamic>> employees = [];
  Map<String, Map<String, dynamic>> _employeeLookup = {};
  String? selectedEmployee;
  DateTime? startDate;
  DateTime? endDate;
  final ScrollController _scrollController = ScrollController();
  bool _showAllNotPunched = false;

  // String sortBy = "name";   // default sorting
  bool sortAscending = true;
  int? sortColumnIndex;
  List<Map<String, dynamic>> _sortedRecords = [];
  static const int _rowsPerPage = 100;
  int _tablePage = 0;

  @override
  void initState() {
    super.initState();
    _fetchEmployeeNames();
    final today = DateTime.now();
    startDate = DateTime(today.year, today.month, today.day);
    endDate = startDate;
  }

  void _sort<T>(Comparable<T> Function(Map<String, dynamic> d) getField,
      int columnIndex,
      bool ascending, {
        bool sortAllTypes = false,
        bool silent = false, // 👈 ADD THIS
      })
  {
    if (!sortAllTypes) {
      final attendanceRecords =
      _sortedRecords.where((e) => e["type"] == "attendance").toList();

      attendanceRecords.sort((a, b) {
        final aValue = getField(a);
        final bValue = getField(b);
        return ascending
            ? Comparable.compare(aValue, bValue)
            : Comparable.compare(bValue, aValue);
      });

      final others =
      _sortedRecords.where((e) => e["type"] != "attendance").toList();

      _sortedRecords = [...attendanceRecords, ...others];
    } else {
      _sortedRecords.sort((a, b) {
        final aValue = getField(a);
        final bValue = getField(b);
        return ascending
            ? Comparable.compare(aValue, bValue)
            : Comparable.compare(bValue, aValue);
      });
    }

    if (!silent) {
      setState(() {
        sortColumnIndex = columnIndex;
        sortAscending = ascending;
        _tablePage = 0;
      });
    }
  }

  List<Map<String, dynamic>> _getEmployeesNotPunchedInSelectedDate({
    required DateTime selectedDate,
    required List<Map<String, dynamic>> attendanceRecords,
    required List<Map<String, dynamic>> leaveRecords,
  }) {
    final dayStart =
    DateTime(selectedDate.year, selectedDate.month, selectedDate.day);

    final dayEnd = dayStart.add(const Duration(days: 1));

    // Employees who punched in that selected day
    final punchedInUserIds = attendanceRecords
        .where((a) {
      final punchIn = (a["punchInTime"] as Timestamp?)?.toDate();
      if (punchIn == null) return false;

      return !punchIn.isBefore(dayStart) &&
          punchIn.isBefore(dayEnd);
    })
        .map((a) => a["userId"])
        .toSet();

    // Employees on leave that day
    final leaveUserIds = leaveRecords
        .where((leave) {
      final start = (leave["startDate"] as Timestamp).toDate();
      final end = (leave["endDate"] as Timestamp).toDate();

      return !start.isAfter(dayStart) &&
          !end.isBefore(dayStart);
    })
        .map((l) => l["userId"])
        .toSet();

    return employees.where((emp) {
      if (!isEmployeeVisibleOnDate(emp, selectedDate)) return false;

      return !punchedInUserIds.contains(emp["uid"]) &&
          !leaveUserIds.contains(emp["uid"]);
    }).toList();
  }


  Future<void> _fetchEmployeeNames() async {
    try {
      final all = await fetchAllEmployees();
      if (!mounted) return;
      setState(() {
        _employeeLookup = buildEmployeeLookup(all);
        employees = all.where(isSelectableEmployeeRecord).toList();
      });
    } catch (e) {
      print("Error fetching employees: $e");
    }
  }

  Map<String, dynamic> _lookupEmployee(String userId) {
    return lookupEmployeeRecord(userId, _employeeLookup);
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
        _tablePage = 0;
      });
    }
  }

  void _applySorting(List<Map<String, dynamic>> records) {
    _sortedRecords = List<Map<String, dynamic>>.from(records);

    if (sortColumnIndex != null) {
      switch (sortColumnIndex) {
        case 1: // Type
          _sort(
                (d) {
              switch (d["type"]) {
                case "attendance":
                  return 0;
                case "leave":
                  return 1;
                case "holiday":
                  return 2;
                default:
                  return 3;
              }
            },
            1,
            sortAscending,
            sortAllTypes: true,
            silent: true,
          );
          break;

        case 6: // Punch In
          _sort(
                (d) {
              if (d["type"] != "attendance") return DateTime(9999);
              return (d["punchInTime"] as Timestamp?)?.toDate() ??
                  DateTime(9999);
            },
            6,
            sortAscending,
            silent: true,
          );
          break;

        case 9: // Total Hours
          _sort(
                (d) {
              if (d["type"] != "attendance") return 99999;
              return d["totalHours"] ?? 0;
            },
            9,
            sortAscending,
            silent: true,
          );
          break;

        case 0: // Employee
          _sort(
                (d) {
              if (d["type"] == "holiday") {
                return "ZZZZ"; // push holidays to bottom
              }

              final employee = _lookupEmployee(d['userId']?.toString() ?? '');

              return employee["name"].toString().toLowerCase();
            },
            0,
            sortAscending,
            silent: true,
          );
          break;
        case 8: // Date / Range
          _sort(
                (d) {
              if (d["type"] == "attendance") {
                return (d["punchInTime"] as Timestamp?)?.toDate() ??
                    DateTime(9999);
              }

              if (d["type"] == "leave") {
                return (d["startDate"] as Timestamp?)?.toDate() ??
                    DateTime(9999);
              }

              if (d["type"] == "holiday") {
                return (d["date"] as Timestamp?)?.toDate() ??
                    DateTime(9999);
              }

              return DateTime(9999);
            },
            8,
            sortAscending,
            silent: true,
          );
          break;
      }
    } else {
      // Default sort by Punch In
      _sort(
            (d) {
          if (d["type"] != "attendance") return DateTime(9999);
          return (d["punchInTime"] as Timestamp?)?.toDate() ??
              DateTime(9999);
        },
        6,
        true,
        silent: true,
      );
    }
  }

  void _showImageDialog(String url) {
    if (url.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) =>
          Dialog(child: InteractiveViewer(child: Image.network(url))),
    );
  }

  void _showFullDetailsDialog(String details) {
    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: const Text("Full Detail"),
            content: SelectableText(details),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close"),
              ),
            ],
          ),
    );
  }

  Future<void> _confirmDeleteAttendance(Map<String, dynamic> data) async {
    final employee = _lookupEmployee(data['userId']?.toString() ?? '');
    final name = employee['name']?.toString() ?? 'Unknown';
    final punchIn = (data['punchInTime'] as Timestamp?)?.toDate();
    final punchOut = (data['punchOutTime'] as Timestamp?)?.toDate();
    final totalMinutes =
        AttendanceUtils.parseStoredMinutes(data['totalHours']) ?? 0;
    final recordId = data['id']?.toString();

    if (recordId == null || recordId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete: record id missing')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete duplicate attendance?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Employee: $name'),
            if (punchIn != null)
              Text('Punch in: ${DateFormat('dd MMM yyyy, hh:mm a').format(punchIn)}'),
            if (punchOut != null)
              Text('Punch out: ${DateFormat('dd MMM yyyy, hh:mm a').format(punchOut)}'),
            Text('Hours: ${AttendanceUtils.formatMinutes(totalMinutes)}'),
            const SizedBox(height: 12),
            const Text(
              'This removes only the selected entry. The other duplicate '
              'for this day will remain.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(recordId)
          .delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted attendance entry for $name')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  String calculateTotalHours(
    List<Map<String, dynamic>> attendance,
    List<Map<String, dynamic>> leaves,
    List<Map<String, dynamic>> holidays,
  ) {
    if (startDate == null || endDate == null) {
      return formatHoursMinutes(0);
    }

    return calculateWorkedHoursTextInRange(
      rangeStart: startDate!,
      rangeEnd: endDate!,
      attendanceRecords: attendance,
      leaveRecords: leaves,
      holidayDateKeys: buildHolidayDateKeys(holidays),
      employeeLookup: _employeeLookup,
      userId: selectedEmployee,
    );
  }


  Stream<Map<String, List<Map<String, dynamic>>>> _combinedStream() {
    final DateTime start = DateTime(
        startDate!.year, startDate!.month, startDate!.day);
    final DateTime end = DateTime(
        endDate!.year, endDate!.month, endDate!.day, 23, 59, 59);

    print("✅ Combined stream refreshed for $start → $end");

    // --- ATTENDANCE: punchIn inside the range ---
    final attendanceStream = FirebaseFirestore.instance
        .collection("attendance")
        .where("punchInTime", isLessThanOrEqualTo: Timestamp.fromDate(end))
        .where("punchInTime", isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .snapshots();

    // --- LEAVES: any part of leave overlapping range ---
    final leaveStream = FirebaseFirestore.instance
        .collection("leaves")
        .where("startDate", isLessThanOrEqualTo: Timestamp.fromDate(end))
        .where("endDate", isGreaterThanOrEqualTo: Timestamp.fromDate(start))
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

          // 👇 FIND employee (include resigned for date visibility checks)
          final emp = _lookupEmployee(rec['userId']?.toString() ?? '');

          if (!isEmployeeVisibleOnDate(emp, punchIn)) {
            return false;
          }

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

          // 👇 FIND employee (include resigned for date visibility checks)
          final emp = _lookupEmployee(leave['userId']?.toString() ?? '');

          if (!isEmployeeVisibleOnDate(emp, s)) return false;

          return !s.isAfter(end) && !e.isBefore(start);
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
  Future<void> _exportToExcel(List<Map<String, dynamic>> attendance,
      List<Map<String, dynamic>> leaves,
      List<Map<String, dynamic>> holidays,) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      final holidayDateKeys = buildHolidayDateKeys(holidays);

      final attendanceForExport = selectedEmployee != null &&
              selectedEmployee!.isNotEmpty &&
              startDate != null &&
              endDate != null
          ? listWorkedAttendanceRecordsInRange(
              userId: selectedEmployee!,
              employee: _lookupEmployee(selectedEmployee!),
              rangeStart: startDate!,
              rangeEnd: endDate!,
              attendanceRecords: attendance,
              leaveRecords: leaves,
              holidayDateKeys: holidayDateKeys,
            )
          : attendance;

      sheet.appendRow([
        'Employee',
        'Type',
        'Punch In',
        'Punch Out',
        'Date',
        'Total Hours',
        'Leave Status',
        'Exempt Status',
        'Exemption Reason',
        'In Address',
        'Out Address',
        'Selfie In URL',
        'Selfie Out URL',
        'Leave/Holiday Name',
      ]);

      for (var record in attendanceForExport) {
        final employee = _lookupEmployee(record['userId']?.toString() ?? '');

        final punchInTime = (record["punchInTime"] as Timestamp?)?.toDate();
        if (punchInTime != null &&
            !isEmployeeVisibleOnDate(employee, punchInTime)) {
          continue;
        }
        final punchOutTime = (record["punchOutTime"] as Timestamp?)?.toDate();

        final exemptionStatus = record["exemptionStatus"] ?? "none";
        final exemptionReason = record["exemptionReason"] ?? "-";

        final totalMinutes =
            AttendanceUtils.parseStoredMinutes(record['totalHours']) ?? 0;
        final totalHours = AttendanceUtils.toDecimalHours(totalMinutes);

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
          exemptionReason,
          record["punchInAddress"] ?? "-",
          record["punchOutAddress"] ?? "-",
          record["punchInSelfieUrl"] ?? "-",
          record["punchOutSelfieUrl"] ?? "-",
          "-", // holiday name
        ]);
      }


      // Leave rows
      for (var leave in leaves) {
        final employee = _lookupEmployee(leave['userId']?.toString() ?? '');

        final start = (leave["startDate"] as Timestamp).toDate();
        if (!isEmployeeVisibleOnDate(employee, start)) {
          continue;
        }
        final end = (leave["endDate"] as Timestamp).toDate();

        final sameDay = DateUtils.isSameDay(start, end);
        String date = "";

        if (sameDay) {
          date = DateFormat('dd MMM yyyy').format(start);
        }
        else {
          date = "${DateFormat('dd MMM yyyy').format(start)} - ${DateFormat(
              'dd MMM yyyy').format(end)}";
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
          "-",
          holiday["name"] ?? "-", // ✅ include holiday name
        ]);
      }

      if (startDate != null && endDate != null) {
        sheet.appendRow([]);
        final totalWorkedHours = calculateWorkedHoursTextInRange(
          rangeStart: startDate!,
          rangeEnd: endDate!,
          attendanceRecords: attendance,
          leaveRecords: leaves,
          holidayDateKeys: holidayDateKeys,
          employeeLookup: _employeeLookup,
          userId: selectedEmployee,
        );
        final totalLabel = selectedEmployee != null &&
                selectedEmployee!.isNotEmpty
            ? '${_lookupEmployee(selectedEmployee!)['name']} - Total Worked Hours'
            : 'Total Worked Hours';
        sheet.appendRow([
          totalLabel,
          '',
          '',
          '',
          '',
          totalWorkedHours,
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

  Widget _buildPendingBadgeButton({
    required IconData icon,
    required String tooltip,
    required Stream<QuerySnapshot> stream,
    required VoidCallback onPressed,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: Icon(icon),
              tooltip: tooltip,
              onPressed: onPressed,
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
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Text(
                    count.toString(),
                    textAlign: TextAlign.center,
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
    );
  }

  Future<void> _onAdminMenuSelected(String value) async {
    switch (value) {
      case 'logs':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UserLogsScreen()),
        );
        break;
      case 'holiday':
        final updated = await showDialog<bool>(
          context: context,
          builder: (context) => const HolidayCalendarDialog(),
        );
        if (updated == true && mounted) setState(() {});
        break;
      case 'employees':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EmployeeManagementScreen()),
        );
        _fetchEmployeeNames();
        break;
      case 'leave_balance':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LeaveBalanceScreen()),
        );
        break;
    }
  }

  PopupMenuItem<String> _adminMenuItem({
    required String value,
    required IconData icon,
    required String label,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, List<Map<String, dynamic>>>>(
        stream: _combinedStream(),
        builder: (context, snapshot) {
          final attendance = snapshot.data?["attendance"] ?? [];
          final leaves = snapshot.data?["leaves"] ?? [];
          final holidays = snapshot.data?["holidays"] ?? [];

          List<Map<String, dynamic>> employeesNotPunched = [];

          if (startDate != null &&
              endDate != null &&
              DateUtils.isSameDay(startDate!, endDate!)) {
            employeesNotPunched =
                _getEmployeesNotPunchedInSelectedDate(
                  selectedDate: startDate!,
                  attendanceRecords: attendance,
                  leaveRecords: leaves,
                );
          }

          return Scaffold(
            appBar: AppBar(
              title: const Text("Admin Dashboard"),
              centerTitle: true,

              // ✅ ACTION BUTTONS BACK
              actions: [
                _buildPendingBadgeButton(
                  icon: Icons.notifications,
                  tooltip: 'Leave Requests',
                  stream: FirebaseFirestore.instance
                      .collection('leaves')
                      .where('status', isEqualTo: 'Pending')
                      .snapshots(),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LeaveApprovalScreen(),
                      ),
                    );
                  },
                ),
                _buildPendingBadgeButton(
                  icon: Icons.receipt_long,
                  tooltip: 'OPE Claims',
                  stream: FirebaseFirestore.instance
                      .collection('ope_claims')
                      .where('status', isEqualTo: 'pending')
                      .snapshots(),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OpeClaimApprovalScreen(),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.analytics),
                  tooltip: 'Monthly Summary',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EmployeeMonthlySummaryScreen(
                          employees: employees,
                        ),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.schedule),
                  tooltip: 'Clock Hours',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ClockHoursScreen(),
                      ),
                    );
                  },
                ),
                PopupMenuButton<String>(
                  tooltip: 'More options',
                  onSelected: _onAdminMenuSelected,
                  itemBuilder: (context) => [
                    _adminMenuItem(
                      value: 'holiday',
                      icon: Icons.calendar_month,
                      label: 'Mark Holiday',
                    ),
                    _adminMenuItem(
                      value: 'employees',
                      icon: Icons.people,
                      label: 'Employee Management',
                    ),
                    _adminMenuItem(
                      value: 'leave_balance',
                      icon: Icons.event_available,
                      label: 'Leave Balance',
                    ),
                    _adminMenuItem(
                      value: 'logs',
                      icon: Icons.history,
                      label: 'User Logs',
                    ),
                  ],
                ),
              ],
            ),

              body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Builder(
                      builder: (context) {
                        final today = DateTime.now();

                        // final attendance = snapshot.data?["attendance"] ?? [];
                        // final leaves = snapshot.data?["leaves"] ?? [];
                        // final holidays = snapshot.data?["holidays"] ?? [];

                        // 🔹 Employee filter
                        final filteredAttendance = selectedEmployee == null
                            ? attendance
                            : attendance
                            .where((a) => a["userId"] == selectedEmployee)
                            .toList();

                        final filteredLeaves = selectedEmployee == null
                            ? leaves
                            : leaves
                            .where((l) => l["userId"] == selectedEmployee)
                            .toList();
                        // Holidays are global
                        final filteredHolidays = holidays;
                        final dateFilteredAttendance = filteredAttendance
                            .where((a) {
                          final punchIn = (a["punchInTime"] as Timestamp?)
                              ?.toDate();
                          return punchIn != null && isInDateRange(punchIn);
                        }).toList();
                        final duplicateAttendanceDayKeys =
                            findDuplicateAttendanceDayKeys(
                          dateFilteredAttendance,
                        );
                        final duplicateAttendanceLabels =
                            formatDuplicateAttendanceLabels(
                          duplicateDayKeys: duplicateAttendanceDayKeys,
                          employeeLookup: _employeeLookup,
                        );
                        final totalWorkedHours = calculateTotalHours(
                          attendance,
                          leaves,
                          holidays,
                        );

                        final dateFilteredLeaves = filteredLeaves.where((l) {
                          final start = (l["startDate"] as Timestamp).toDate();
                          final end = (l["endDate"] as Timestamp).toDate();

                          if (startDate != null && endDate != null) {
                            return !(end.isBefore(startDate!) ||
                                start.isAfter(endDate!));
                          }

                          if (startDate != null && endDate == null) {
                            return !startDate!.isBefore(start) && !startDate!
                                .isAfter(
                                end);
                          }

                          return true;
                        }).toList();

                        final dateFilteredHolidays = filteredHolidays.where((
                            h) {
                          final date = (h["date"] as Timestamp?)?.toDate();
                          return date != null && isInDateRange(date);
                        }).toList();

                        final allRecords = [
                          ...dateFilteredAttendance,
                          ...dateFilteredLeaves,
                          ...dateFilteredHolidays,
                        ];
                        _applySorting(allRecords);

                        final totalRecords = _sortedRecords.length;
                        final totalPages = totalRecords == 0
                            ? 1
                            : ((totalRecords - 1) ~/ _rowsPerPage) + 1;
                        final safePage =
                            _tablePage.clamp(0, totalPages - 1);
                        if (safePage != _tablePage) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() => _tablePage = safePage);
                          });
                        }
                        final pageStart = safePage * _rowsPerPage;
                        final pageRecords = _sortedRecords
                            .skip(pageStart)
                            .take(_rowsPerPage)
                            .toList();

                        final hasRecords = totalRecords > 0;
                        final duplicateSummaryText =
                            duplicateAttendanceLabels.isEmpty
                                ? null
                                : duplicateAttendanceLabels.length <= 2
                                    ? duplicateAttendanceLabels.join(', ')
                                    : '${duplicateAttendanceLabels.take(2).join(', ')} '
                                        '+${duplicateAttendanceLabels.length - 2} more';

                        return Column(
                          children: [
                            // ✅ ADD NOT PUNCHED SECTION HERE
                            if (employeesNotPunched.isNotEmpty)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                  border: BoxBorder.all(color: Colors.grey.shade300),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.warning_amber_rounded,
                                          color: Colors.red,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          "Not Punched In Today (${employeesNotPunched.length})",
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFFD32F2F),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),

                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: (_showAllNotPunched
                                          ? employeesNotPunched
                                          : employeesNotPunched.take(8).toList())
                                          .map((emp) => Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(20),
                                            border: BoxBorder.all(color: Colors.grey.shade300)
                                        ),
                                        child: Text(
                                          emp["name"],
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                        ),
                                      ))
                                          .toList(),
                                    ),

                                    if (employeesNotPunched.length > 8)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 10),
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _showAllNotPunched = !_showAllNotPunched;
                                            });
                                          },
                                          child: Text(
                                            _showAllNotPunched
                                                ? "Show Less"
                                                : "+${employeesNotPunched.length - 8} more",
                                            style: const TextStyle(
                                              color: Colors.blue,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),


                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.amberAccent.shade100,
                                borderRadius: BorderRadius.circular(10),
                                border: BoxBorder.all(color: Colors.black45),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      selectedEmployee == null
                                          ? "All Employees"
                                          : _lookupEmployee(
                                              selectedEmployee!,
                                            )['name'] ??
                                              "Unknown",
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (duplicateSummaryText != null) ...[
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 3,
                                      child: Tooltip(
                                        message: duplicateAttendanceLabels
                                            .join('\n'),
                                        waitDuration:
                                            const Duration(milliseconds: 400),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.content_copy,
                                              size: 16,
                                              color: Colors.deepOrange.shade800,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'Duplicate: '
                                                '${duplicateAttendanceDayKeys.length} '
                                                '— $duplicateSummaryText',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors
                                                      .deepOrange.shade900,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 12),
                                  Text(
                                    'Total Hours: $totalWorkedHours',
                                    style: const TextStyle(
                                      fontSize: 16,
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
                                  child: SearchableEmployeeDropdown(
                                    value: selectedEmployee,
                                    employees: employeeListToNameMap(employees),
                                    showClearOption: true,
                                    clearOptionLabel: 'All Employees',
                                    onChanged: (value) {
                                      setState(() {
                                        selectedEmployee = value;
                                        _tablePage = 0;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.date_range),
                                  label: Text(
                                      startDate == endDate
                                          ? DateFormat('dd MMM yyyy').format(
                                          startDate!)
                                          : "${DateFormat('dd MMM').format(
                                          startDate!)} - ${DateFormat(
                                          'dd MMM yyyy')
                                          .format(
                                          endDate!)}"


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
                                      _tablePage = 0;
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
                                    _exportToExcel(
                                        dateFilteredAttendance,
                                        dateFilteredLeaves,
                                        dateFilteredHolidays);
                                  }
                                      : null,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // 🔹 Data Section
                            Expanded(
                              child: !snapshot.hasData
                                  ? const Center(
                                  child: CircularProgressIndicator())
                                  : allRecords.isEmpty
                                  ? const Center(
                                child: Text(
                                    "No records found for selected range."),
                              )
                                  : DataTable2(
                                fixedTopRows: 1,
                                // ❄ Freeze header
                                columnSpacing: 5,
                                headingRowHeight: 56,
                                dataRowHeight: 70,
                                minWidth: 1400,
                                // Table width
                                //horizontalMargin: 10,
                                scrollController: _scrollController,
                                sortColumnIndex: sortColumnIndex,
                                sortAscending: sortAscending,
                                columns: [
                                  DataColumn2(
                                    label: const Text("Employee"),
                                    onSort: (columnIndex, ascending) {
                                      _sort(
                                            (d) {
                                          if (d["type"] != "attendance")
                                            return "";
                                          final employee = _lookupEmployee(
                                            d['userId']?.toString() ?? '',
                                          );
                                          return employee["name"];
                                        },
                                        columnIndex,
                                        ascending,
                                      );
                                    },
                                  ),

                                  DataColumn2(
                                    label: const Text("Type"),
                                    onSort: (columnIndex, ascending) {
                                      _sort(
                                            (d) {
                                          switch (d["type"]) {
                                            case "attendance":
                                              return 0;
                                            case "leave":
                                              return 1;
                                            case "holiday":
                                              return 2;
                                            default:
                                              return 3;
                                          }
                                        },
                                        columnIndex,
                                        ascending,
                                        sortAllTypes: true,
                                      );
                                    },
                                  ),

                                  const DataColumn2(label: Text("Selfie In")),
                                  const DataColumn2(label: Text("In Address")),
                                  const DataColumn2(label: Text("Selfie Out")),
                                  const DataColumn2(label: Text("Out Address")),
                                  // const DataColumn2(label: Text("Punch In")),
                                  DataColumn2(
                                    label: const Text("Punch In"),
                                    onSort: (columnIndex, ascending) {
                                      _sort(
                                            (d) {
                                          if (d["type"] != "attendance") {
                                            return DateTime(9999);
                                          }
                                          return (d["punchInTime"] as Timestamp?)
                                              ?.toDate() ??
                                              DateTime(9999);
                                        },
                                        columnIndex,
                                        ascending,
                                      );
                                    },
                                  ),

                                  const DataColumn2(label: Text("Punch Out")),
                                  DataColumn2(
                                    label: const Text("Date / Range"),
                                    onSort: (columnIndex, ascending) {
                                      _sort(
                                            (d) {
                                          if (d["type"] == "attendance") {
                                            return (d["punchInTime"] as Timestamp?)?.toDate() ??
                                                DateTime(9999);
                                          }

                                          if (d["type"] == "leave") {
                                            return (d["startDate"] as Timestamp?)?.toDate() ??
                                                DateTime(9999);
                                          }

                                          if (d["type"] == "holiday") {
                                            return (d["date"] as Timestamp?)?.toDate() ??
                                                DateTime(9999);
                                          }

                                          return DateTime(9999);
                                        },
                                        columnIndex,
                                        ascending,
                                      );
                                    },
                                  ),
                                  DataColumn2(
                                    label: const Text("Total Hours"),
                                    onSort: (columnIndex, ascending) {
                                      _sort(
                                            (d) {
                                          if (d["type"] != "attendance")
                                            return 99999;
                                          return d["totalHours"] ?? 0;
                                        },
                                        columnIndex,
                                        ascending,
                                      );
                                    },
                                  ),

                                  const DataColumn2(
                                      label: Text("Leave Status")),
                                  const DataColumn2(label: Text("Exempt")),
                                  const DataColumn2(
                                    label: Text(
                                      "Exemption Reason",
                                      maxLines: 2,
                                      softWrap: true,
                                    ),
                                  ),
                                  const DataColumn2(label: Text("Actions")),
                                ],
                                rows: pageRecords.map((data) {
                                  final type = data["type"];
                                  final isLeave = type == "leave";
                                  final isHoliday = type == "holiday";
                                  final employee = _lookupEmployee(
                                    data['userId']?.toString() ?? '',
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

                                  bool isHalfDay = false;
                                  String totalHoursText = "-";

                                  if (!isLeave &&
                                      !isHoliday) {
                                    if (punchOutTime == null) {
                                      totalHoursText = "-";
                                    } else {
                                      final totalMinutes =
                                          AttendanceUtils.parseStoredMinutes(
                                                data['totalHours'],
                                              ) ??
                                              0;
                                      totalHoursText =
                                          AttendanceUtils.formatMinutes(
                                        totalMinutes,
                                      );

                                      if (totalMinutes <
                                              AttendanceUtils.fullDayMinutes &&
                                          !AttendanceUtils.isExemptionApproved(
                                            data,
                                          )) {
                                        isHalfDay = true;
                                        totalHoursText =
                                            "$totalHoursText (Half Day)";
                                      }
                                    }
                                  } else if (isLeave) {
                                    totalHoursText = "0 h 00 m";
                                  } else if (isHoliday) {
                                    totalHoursText = "-";
                                  }


                                  final isDuplicate =
                                      !isLeave &&
                                      !isHoliday &&
                                      isDuplicateAttendanceEntry(
                                        data,
                                        duplicateAttendanceDayKeys,
                                      );

                                  final punchDay =
                                      AttendanceUtils.parseRecordDate(data);
                                  final isOffSatWork = !isLeave &&
                                      !isHoliday &&
                                      punchDay != null &&
                                      isScheduledOffSaturday(
                                        employee,
                                        punchDay,
                                      ) &&
                                      punchOutTime != null;

                                  final rowColor = isHoliday
                                      ? Colors.green[200]
                                      : isLeave
                                      ? Colors.yellow[200]
                                      : isDuplicate
                                      ? Colors.deepOrange.shade200
                                      : isOffSatWork
                                      ? Colors.teal.shade100
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
                                              : isDuplicate
                                              ? "Attendance (Duplicate)"
                                              : isOffSatWork
                                              ? "Attendance (Off Sat)"
                                              : "Attendance",
                                        ),
                                      ),
                                      DataCell(
                                        isLeave || isHoliday
                                            ? const Text("-")
                                            : InkWell(
                                          onTap: () =>
                                              _showImageDialog(
                                                data["punchInSelfieUrl"] ??
                                                    "",
                                              ),
                                          child: Image.network(
                                            data["punchInSelfieUrl"] ??
                                                "",
                                            width: 50,
                                            height: 50,
                                            cacheWidth: 100,
                                            cacheHeight: 100,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (_,
                                                __,
                                                ___,) =>
                                            const Icon(
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
                                              _showFullDetailsDialog(
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
                                          onTap: () =>
                                              _showImageDialog(
                                                data["punchOutSelfieUrl"] ??
                                                    "",
                                              ),
                                          child: Image.network(
                                            data["punchOutSelfieUrl"] ??
                                                "",
                                            width: 50,
                                            height: 50,
                                            cacheWidth: 100,
                                            cacheHeight: 100,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (_,
                                                __,
                                                ___,) =>
                                            const Icon(
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
                                              _showFullDetailsDialog(
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
                                          message: data['isLate'] == true
                                              ? "⚠️ Late Punch In"
                                              : "",
                                          child: Text(
                                            punchInTime != null
                                                ? DateFormat('hh:mm a').format(
                                                punchInTime)
                                                : "-",
                                            style: TextStyle(
                                              color: (data['isLate'] == true)
                                                  ? Colors.red
                                                  : Colors.black,
                                              fontWeight: (data['isLate'] ==
                                                  true)
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                      ),

                                      DataCell(

                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 6, horizontal: 8),
                                          decoration: BoxDecoration(
                                            color: data['autoLogout'] == true
                                                ? Colors
                                                .red
                                                .withOpacity(0.15)
                                                : Colors
                                                .transparent,
                                            borderRadius: BorderRadius.circular(
                                                6),
                                          ),
                                          child: Text(
                                            isLeave || isHoliday
                                                ? "-"
                                                : punchOutTime != null
                                                ? "${DateFormat('hh:mm a')
                                                .format(
                                                punchOutTime)}${data['autoLogout'] ==
                                                true
                                                ? ' \n(Auto punch-out)'
                                                : ''}"
                                                : "-",
                                          ),
                                        ),
                                      ),


                                      DataCell(
                                        Text(
                                          isHoliday
                                              ? DateFormat('dd MMM yyyy')
                                              .format(
                                              (data["date"] as Timestamp)
                                                  .toDate())
                                              : isLeave
                                              ? () {
                                            final leaveStart = (data["startDate"] as Timestamp)
                                                .toDate();
                                            final leaveEnd = (data["endDate"] as Timestamp)
                                                .toDate();
                                            return leaveStart == leaveEnd
                                                ? DateFormat('dd MMM yyyy')
                                                .format(
                                                leaveStart)
                                                : "${DateFormat('dd MMM')
                                                .format(
                                                leaveStart)} - ${DateFormat(
                                                'dd MMM')
                                                .format(leaveEnd)}";
                                          }()
                                              : punchInTime != null
                                              ? DateFormat('dd MMM yyyy')
                                              .format(
                                              punchInTime)
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
                                              if (isHalfDay &&
                                                  data['exemptionStatus'] !=
                                                      "approved") ...[
                                                const Icon(
                                                    Icons.access_time_filled,
                                                    color: Colors.red,
                                                    size: 20),
                                                const SizedBox(width: 6),
                                              ],

                                              if (!isHalfDay &&
                                                  data['exemptionStatus'] ==
                                                      "approved") ...[
                                                Tooltip(
                                                  message: "Exempted by Admin",
                                                  child: const Icon(
                                                      Icons.verified_user,
                                                      color: Colors.green,
                                                      size: 20),
                                                ),
                                                const SizedBox(width: 6),
                                              ],

                                              Expanded(
                                                child: Text(
                                                  totalHoursText,
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow: TextOverflow
                                                      .visible,
                                                  // 👈 no wrapping, no ellipsis
                                                  style: TextStyle(
                                                    color: (data['exemptionStatus'] ==
                                                        "approved")
                                                        ? Colors.green
                                                        : (isHalfDay
                                                        ? Colors.red
                                                        : Colors
                                                        .black),
                                                    fontWeight: (data['exemptionStatus'] ==
                                                        "approved" ||
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
                                            final exemptionStatus = data['exemptionStatus'] ??
                                                "none";
                                            final punchOutTime = data["punchOutTime"] as Timestamp?;

                                            String buttonText;
                                            Color buttonColor;
                                            bool enabled = true;

                                            if (punchOutTime == null) {
                                              buttonText =
                                              "Not punched out yet";
                                              buttonColor = Colors.redAccent;
                                              enabled = false;
                                            } else if (exemptionStatus ==
                                                "requested") {
                                              buttonText =
                                              "Exemption Requested";
                                              buttonColor = Colors.orangeAccent;
                                            } else
                                            if (exemptionStatus == "approved") {
                                              buttonText = "Exempted ✅";
                                              buttonColor = Colors.green;
                                              enabled = false;
                                            } else {
                                              buttonText = "Mark Exempt";
                                              buttonColor = Colors.grey;
                                            }

                                            return ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                minWidth: 250, // 👈 make this big to force max width
                                              ),
                                              // 👈 prevents overflow inside DataTable
                                              child: ElevatedButton(
                                                onPressed: enabled
                                                    ? () async {
                                                  await FirebaseFirestore
                                                      .instance
                                                      .collection("attendance")
                                                      .doc(data["id"])
                                                      .update(
                                                      {
                                                        'exemptionStatus': "approved"
                                                      });

                                                  setState(() {
                                                    data['exemptionStatus'] =
                                                    "approved";
                                                  });
                                                }
                                                    : null,
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: buttonColor,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8),
                                                ),
                                                child: Text(
                                                  buttonText,
                                                  maxLines: 2,
                                                  //softWrap: false,
                                                  overflow: TextOverflow
                                                      .visible,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      DataCell(
                                        isLeave || isHoliday
                                            ? const Text("-")
                                            : InkWell(
                                          onTap: () =>
                                              _showFullDetailsDialog(
                                                data["exemptionReason"] ?? "",
                                              ),
                                          child: SizedBox(
                                            width: 220,
                                            child: Text(
                                              data["exemptionReason"]
                                                  ?.toString()
                                                  .isNotEmpty == true
                                                  ? data["exemptionReason"]
                                                  : "-",
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              // style: const TextStyle(
                                              //   decoration: TextDecoration.underline,
                                              //   color: Colors.blue,
                                              // ),
                                            ),

                                          ),

                                        ),
                                      ),

                                      DataCell(
                                        isDuplicate && !isLeave && !isHoliday
                                            ? IconButton(
                                                icon: Icon(
                                                  Icons.delete_outline,
                                                  color: Colors.red.shade700,
                                                ),
                                                tooltip: 'Delete this duplicate entry',
                                                onPressed: () =>
                                                    _confirmDeleteAttendance(
                                                      data,
                                                    ),
                                              )
                                            : const SizedBox.shrink(),
                                      ),

                                    ],
                                  );
                                }).toList(),

                              ),
                            ),
                            if (hasRecords && totalRecords > _rowsPerPage)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      tooltip: 'Previous page',
                                      onPressed: safePage > 0
                                          ? () => setState(() => _tablePage--)
                                          : null,
                                      icon: const Icon(Icons.chevron_left),
                                    ),
                                    Text(
                                      'Showing ${pageStart + 1}-'
                                      '${pageStart + pageRecords.length} of '
                                      '$totalRecords  •  Page ${safePage + 1} '
                                      'of $totalPages',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Next page',
                                      onPressed: safePage < totalPages - 1
                                          ? () => setState(() => _tablePage++)
                                          : null,
                                      icon: const Icon(Icons.chevron_right),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      }
            ),
          ),
                        );
        }
          );
}
}


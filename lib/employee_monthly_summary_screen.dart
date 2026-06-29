import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:month_picker_dialog/month_picker_dialog.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'employee_utils.dart';
import 'searchable_employee_dropdown.dart';
import 'attendance_utils.dart';


class EmployeeMonthlySummaryScreen extends StatefulWidget {
  final List<Map<String, dynamic>> employees;

  const EmployeeMonthlySummaryScreen({
    super.key,
    required this.employees,
  });

  @override
  State<EmployeeMonthlySummaryScreen> createState() =>
      _EmployeeMonthlySummaryScreenState();
}

class _EmployeeMonthlySummaryScreenState
    extends State<EmployeeMonthlySummaryScreen> {

  String? selectedUid;
  DateTime? selectedMonth;

  List<Map<String, dynamic>> tableData = [];
  int totalMinutes = 0;
  int totalLeaveMinutes = 0;
  int expectedMinutes = 0;
  int presentDays = 0;
  int leaveDays = 0;
  int absentDays = 0;
  int autoPunchOutDays = 0;
  int offSatWorkDays = 0;
  List<Map<String, dynamic>> filteredData = [];
  int totalWorkingDays = 0;
  int workedDays = 0;
  String activeCardFilter = "All";
  bool isExporting = false;

  Color _statusColor(String status) {
    switch (status) {
      case "Present":
        return Colors.green.shade200;
      case "Leave":
        return Colors.blue.shade200;
      case "Auto Punch-Out":
        return Colors.orange.shade200;
      case "No Punch-In":
        return Colors.red.shade200;
      case "Weekend":
        return Colors.grey.shade300;
      case "Off-Sat Work":
        return Colors.teal.shade100;
      case "Not Employed":
        return Colors.blueGrey.shade100;
      default:
        return Colors.grey.shade200;
    }
  }

  String getEmployeeName(String? uid) {

    if (uid == null || uid == "ALL") {
      return "All Employees";
    }

    final emp = widget.employees.firstWhere(
          (e) => e["uid"] == uid,
      orElse: () => {"name": "Unknown"},
    );

    return emp["name"] ?? "Unknown";
  }

  Map<String, dynamic>? _employeeRecord(String empId) {
    for (final emp in widget.employees) {
      if (emp["uid"]?.toString() == empId) return emp;
    }
    return null;
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case "All":
        return Icons.dashboard;
      case "Present":
        return Icons.check_circle;
      case "Leave":
        return Icons.event_note;
      case "No Punch-In":
        return Icons.cancel;
      case "Auto Punch-Out":
        return Icons.timer_off;
      case "Weekend":
        return Icons.weekend;
      case "Off-Sat Work":
        return Icons.more_time;
      case "Not Employed":
        return Icons.person_off;
      default:
        return Icons.info;
    }
  }
  Widget _summaryCard(String title, int value, Color color) {

    bool isActive = activeCardFilter == title;

    return GestureDetector(
      onTap: () {

        setState(() {

          activeCardFilter = title;

          filteredData = activeCardFilter == "All"
              ? tableData
              : tableData
              .where((row) => row["status"] == activeCardFilter)
              .toList();

        });

      },
      child: Card(
        elevation: isActive ? 8 : 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isActive ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              Icon(
                _statusIcon(title),
                color: color,
                size: 16,
              ),

              Text(
                value.toString(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),

              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),

            ],
          ),
        ),
      ),
    );
  }

  List<List<Map<String, dynamic>>> _splitIntoColumns(
    List<Map<String, dynamic>> data,
    int columnCount,
  ) {
    if (data.isEmpty) return [[]];
    if (columnCount <= 1) return [data];

    final chunkSize = (data.length / columnCount).ceil();
    final chunks = <List<Map<String, dynamic>>>[];

    for (int i = 0; i < data.length; i += chunkSize) {
      chunks.add(
        data.sublist(i, i + chunkSize > data.length ? data.length : i + chunkSize),
      );
    }

    return chunks;
  }

  int _columnCountForHeight(int itemCount, double availableHeight) {
    const headingHeight = 36.0;
    const minRowHeight = 28.0;

    for (int columns = 3; columns <= 5; columns++) {
      final rowsPerColumn = (itemCount / columns).ceil();
      final neededHeight = headingHeight + rowsPerColumn * minRowHeight;
      if (neededHeight <= availableHeight) return columns;
    }
    return 5;
  }

  double _rowHeightForLayout(int itemCount, double availableHeight, int columns) {
    const headingHeight = 36.0;
    final rowsPerColumn = math.max(1, (itemCount / columns).ceil());
    return ((availableHeight - headingHeight) / rowsPerColumn).clamp(28.0, 52.0);
  }

  Widget _buildDayTable(
    List<Map<String, dynamic>> rows, {
    required double rowHeight,
    required bool showEmployee,
  }) {
    const headerStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.bold);
    const cellStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);

    return DataTable(
      columnSpacing: 12,
      horizontalMargin: 8,
      headingRowHeight: rowHeight,
      dataRowMinHeight: rowHeight,
      dataRowMaxHeight: rowHeight,
      columns: [
        if (showEmployee) const DataColumn(label: Text('Employee', style: headerStyle)),
        const DataColumn(label: Text('Date', style: headerStyle)),
        const DataColumn(label: Text('Day', style: headerStyle)),
        const DataColumn(label: Text('Status', style: headerStyle)),
        const DataColumn(label: Text('Hours', style: headerStyle)),
      ],
      rows: rows.map((row) {
        final minutes = (row['minutes'] as num?)?.toInt() ?? 0;
        final status = row['status']?.toString() ?? '';

        return DataRow(
          cells: [
            if (showEmployee)
              DataCell(Text(getEmployeeName(row['employeeId']), style: cellStyle)),
            DataCell(
              Text(DateFormat('dd-MMM').format(row['date']), style: cellStyle),
            ),
            DataCell(Text(DateFormat('EEE').format(row['date']), style: cellStyle)),
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(status),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  status,
                  style: cellStyle.copyWith(fontSize: 12),
                ),
              ),
            ),
            DataCell(Text(format(minutes), style: cellStyle)),
          ],
        );
      }).toList(),
    );
  }

  double _minutesToDecimalHours(int minutes) =>
      AttendanceUtils.toDecimalHours(minutes);

  String format(int mins) {
    return (mins / 60.0).toStringAsFixed(2);
  }

  String formatHoursMinutes(int mins) {
    return '${mins ~/ 60}h ${(mins % 60).toString().padLeft(2, '0')}m';
  }

  Widget _infoCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: BoxBorder.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [

          Icon(icon, size: 16, color: color),

          const SizedBox(width: 6),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [

              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),

              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  Future<void> exportToExcel() async {
    setState(() {
      isExporting = true;
    });
    try {
      var excel = Excel.createExcel();
      Sheet sheet = excel['Sheet1'];

      /// HEADER
      sheet.appendRow([
        "Employee",
        "Date",
        "Day",
        "Status",
        "Worked Hours"
      ]);

      var headerStyle = CellStyle(bold: true);

      for (int col = 0; col < 5; col++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
            .cellStyle = headerStyle;
      }

      sheet.setColWidth(0, 25); // Employee
      sheet.setColWidth(1, 25); // Date
      sheet.setColWidth(2, 15); // Day <-- NEW
      sheet.setColWidth(3, 20); // Status
      sheet.setColWidth(4, 18); // Worked Hours

      if (selectedMonth == null) return;

      final employeeIds =
      widget.employees.map((e) => e["uid"].toString()).toList();

      for (var empId in employeeIds) {

        /// LOAD EMPLOYEE DATA
        selectedUid = empId;
        await _loadSummary();

        String empName = getEmployeeName(empId);

        for (var row in tableData) {

          final date = row["date"] as DateTime;
          final status = row["status"];
          int minutes = (row["minutes"] as num?)?.toInt() ?? 0;

          sheet.appendRow([
            empName,
            DateFormat('dd-MMM-yyyy').format(date),
            DateFormat('EEE').format(date),
            status,
            _minutesToDecimalHours(minutes),
          ]);
        }

        /// SUMMARY SECTION
        sheet.appendRow([]);

        sheet.appendRow([empName, "Total Working Days", "", "", totalWorkingDays]);
        for (int col = 0; col < 5; col++) {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: sheet.maxRows - 1))
              .cellStyle = headerStyle;
        }
        sheet.appendRow([empName, "Employee Worked Days", "", "", workedDays]);
        for (int col = 0; col < 5; col++) {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: sheet.maxRows - 1))
              .cellStyle = headerStyle;
        }

        sheet.appendRow([
          empName,
          "Expected Hours",
          "",
          "",
          formatHoursMinutes(expectedMinutes),
        ]);
        for (int col = 0; col < 5; col++) {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: sheet.maxRows - 1))
              .cellStyle = headerStyle;
        }

        sheet.appendRow([
          empName,
          "Worked Hours",
          "",
          "",
          formatHoursMinutes(totalMinutes),
        ]);
        for (int col = 0; col < 5; col++) {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: sheet.maxRows - 1))
              .cellStyle = headerStyle;
        }

        // sheet.appendRow([
        //   empName,
        //   "Leave Hours",
        //   "",
        //   "",
        //   format(totalLeaveMinutes)
        // ]);
        // for (int col = 0; col < 5; col++) {
        //   sheet
        //       .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: sheet.maxRows - 1))
        //       .cellStyle = headerStyle;
        // }

        int actualTotal = totalMinutes;
        int difference = expectedMinutes - actualTotal;

        sheet.appendRow([
          empName,
          "Difference",
          "",
          "",
          "${formatHoursMinutes(difference.abs())} ${difference > 0 ? "(Short)" : "(Extra)"}"
        ]);
        for (int col = 0; col < 5; col++) {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: sheet.maxRows - 1))
              .cellStyle = headerStyle;
        }

        sheet.appendRow(["", "", "", "", "", ""]);
      }

      /// SAVE FILE
      String downloadsPath = "";

      if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        downloadsPath = "$userProfile\\Downloads";
      } else {
        final dir = await getApplicationDocumentsDirectory();
        downloadsPath = dir.path;
      }

      String monthName = DateFormat('MMM').format(selectedMonth!);

      final filePath =
          "$downloadsPath\\All_Summary_Report_${monthName}_${selectedMonth!.year}.xlsx";

      final fileBytes = excel.encode();

      if (fileBytes != null) {
        final file = File(filePath);

        try {
          file.createSync(recursive: true);
          file.writeAsBytesSync(fileBytes);
        } on FileSystemException {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("⚠️ Please close the Excel file before exporting.")),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("❌ Export failed: $e")));
    }
    selectedUid = "ALL";
    tableData.clear();
    filteredData.clear();

    setState(() {
      isExporting = false;
    });
  }

  Future<void> _loadSummary() async
  {
    if (selectedUid == "ALL") {
      tableData.clear();
      filteredData.clear();
      setState(() {});
      return;
    }
    if (selectedUid == null ||selectedMonth == null) return;
    final firstDay = DateTime(selectedMonth!.year, selectedMonth!.month, 1);

    final lastDay = DateTime(
      selectedMonth!.year,
      selectedMonth!.month + 1,
      0,
    );
    final lastDayEnd = DateTime(
      lastDay.year,
      lastDay.month,
      lastDay.day,
      23,
      59,
      59,
    );

    tableData.clear();
    totalMinutes = 0;
    totalLeaveMinutes = 0;
    expectedMinutes = 0;
    workedDays = 0;

    presentDays = 0;
    leaveDays = 0;
    absentDays = 0;
    autoPunchOutDays = 0;
    offSatWorkDays = 0;
    totalWorkingDays = 0;

    const dailyMinutes = AttendanceUtils.expectedDayMinutes; // 9h per working day

    /// FETCH  LEAVES
    Query leaveQuery = FirebaseFirestore.instance.collection("leaves");

    if (selectedUid != "ALL") {
      leaveQuery = leaveQuery.where("userId", isEqualTo: selectedUid);
    }

    leaveQuery = leaveQuery.where("status", isNotEqualTo: "Rejected");

    final leaveSnapshot = await leaveQuery.get();

    List<Map<String, dynamic>> approvedLeaves =
    leaveSnapshot.docs.map((e) => e.data() as Map<String, dynamic>).toList();

    /// FETCH HOLIDAYS
    final holidaySnapshot = await FirebaseFirestore.instance
        .collection("holidays")
        .get();

    List<Map<String, dynamic>> holidays =
    holidaySnapshot.docs.map((e) => e.data()).toList();

    Query query = FirebaseFirestore.instance.collection("attendance");

    if (selectedUid != "ALL") {
      query = query.where("userId", isEqualTo: selectedUid);
    }

    query = query
        .where("punchInDate", isGreaterThanOrEqualTo: Timestamp.fromDate(firstDay))
        .where("punchInDate", isLessThanOrEqualTo: Timestamp.fromDate(lastDayEnd));

    final snapshot = await query.get();

    Set<String> holidayDates = {};

    for (var h in holidays) {

      final d = (h["date"] as Timestamp).toDate();

      final key =
          "${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}";

      holidayDates.add(key);
    }

    /// 1️⃣ Build Attendance Map (Date → Record)
    Map<String, Map<String, dynamic>> attendanceMap = {};

    for (var doc in snapshot.docs) {

      final a = doc.data() as Map<String, dynamic>;

      final recordDate = AttendanceUtils.parseRecordDate(a);
      if (recordDate == null) continue;

      final key =
          "${a["userId"]}_${recordDate.year}-${recordDate.month.toString().padLeft(2,'0')}-${recordDate.day.toString().padLeft(2,'0')}";

      attendanceMap[key] = a;
    }


    List<String> employeeIds = selectedUid == "ALL"
        ? widget.employees.map((e) => e["uid"].toString()).toList()
        : [selectedUid!];

    /// 3️⃣ Loop through each calendar day in the month
    for (DateTime day = firstDay;
        !day.isAfter(lastDay);
        day = day.add(const Duration(days: 1))) {

      final key =
          "${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}";

      if (holidayDates.contains(key)) {
        for (var empId in employeeIds) {
          tableData.add({
            "employeeId": empId,
            "date": day,
            "status": "Holiday",
            "minutes": 0,
          });
        }
        continue;
      }

      for (var empId in employeeIds) {
        final employee = _employeeRecord(empId) ?? {};

        if (!isEmployeeActiveForSummaryDay(employee, day)) {
          tableData.add({
            "employeeId": empId,
            "date": day,
            "status": "Not Employed",
            "minutes": 0,
          });
          continue;
        }

        if (isWeekendDayForEmployee(employee, day)) {
          final record = attendanceMap["${empId}_$key"];

          if (isScheduledOffSaturday(employee, day)) {
            final offSatMinutes = minutesFromAttendanceRecord(record);
            if (offSatMinutes != null) {
              totalMinutes += offSatMinutes;
              workedDays++;

              tableData.add({
                "employeeId": empId,
                "date": day,
                "status": "Off-Sat Work",
                "minutes": offSatMinutes,
              });
              continue;
            }
          }

          tableData.add({
            "employeeId": empId,
            "date": day,
            "status": "Weekend",
            "minutes": 0,
          });
          continue;
        }

        totalWorkingDays++;

        final record = attendanceMap["${empId}_$key"];

        bool isLeaveDay = false;

        for (var leave in approvedLeaves) {
          if (leave["userId"] != empId) continue;

          final s = (leave["startDate"] as Timestamp).toDate();
          final e = (leave["endDate"] as Timestamp).toDate();

          final start = DateTime(s.year, s.month, s.day);
          final end = DateTime(e.year, e.month, e.day);

          if (!day.isBefore(start) && !day.isAfter(end)) {
            isLeaveDay = true;
            break;
          }
        }

        if (isLeaveDay) {
          leaveDays++;
          totalLeaveMinutes += dailyMinutes;

          tableData.add({
            "employeeId": empId,
            "date": day,
            "status": "Leave",
            "minutes": dailyMinutes,
          });

          continue;
        }

        expectedMinutes += dailyMinutes;

        if (record == null || record['punchOutTime'] == null) {
          absentDays++;

          tableData.add({
            "employeeId": empId,
            "date": day,
            "status": "No Punch-In",
            "minutes": 0,
          });
        } else {
          final minutes =
              AttendanceUtils.parseStoredMinutes(record['totalHours']) ?? 0;
          totalMinutes += minutes;

          if (record["autoLogout"] == true) {
            autoPunchOutDays++;
            workedDays++;

            tableData.add({
              "employeeId": empId,
              "date": day,
              "status": "Auto Punch-Out",
              "minutes": minutes,
            });
          } else {
            presentDays++;
            workedDays++;

            tableData.add({
              "employeeId": empId,
              "date": day,
              "status": "Present",
              "minutes": minutes,
            });
          }
        }
      }
    }

    filteredData = activeCardFilter == "All"
        ? tableData
        : tableData.where((r) => r["status"] == activeCardFilter).toList();

    presentDays =
        tableData.where((r) => r["status"] == "Present").length;

    offSatWorkDays =
        tableData.where((r) => r["status"] == "Off-Sat Work").length;

    leaveDays =
        tableData.where((r) => r["status"] == "Leave").length;

    absentDays =
        tableData.where((r) => r["status"] == "No Punch-In").length;

    autoPunchOutDays =
        tableData.where((r) => r["status"] == "Auto Punch-Out").length;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isSingleEmployee =
        selectedUid != null && selectedUid != 'ALL' && selectedMonth != null;
    final appBarTitle = isSingleEmployee
        ? '${getEmployeeName(selectedUid)} · ${DateFormat.yMMM().format(selectedMonth!)}'
        : 'Employee Monthly Summary';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          appBarTitle,
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: Stack(
          children: [

      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [

            /// FILTER ROW
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                /// LEFT SIDE : FILTERS
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [

                      Expanded(
                        child: SearchableEmployeeDropdown(
                          value: selectedUid,
                          employees: employeeListToNameMap(
                            widget.employees.where(isSelectableEmployeeRecord).toList(),
                          ),
                          showClearOption: false,
                          fixedOptionValue: 'ALL',
                          fixedOptionLabel: 'All Employees',
                          hint: 'Select Employee',
                          onChanged: (value) async {
                            if (value == null) return;
                            setState(() => selectedUid = value);

                            if (selectedMonth != null) {
                              await _loadSummary();
                            }
                          },
                        ),
                      ),

                      const SizedBox(width: 12),

                      ElevatedButton(
                        onPressed: () async {

                          final picked = await showMonthPicker(
                            context: context,
                            initialDate: selectedMonth ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );

                          if (picked != null) {
                            setState(() {
                              selectedMonth = DateTime(picked.year, picked.month);
                            });
                          }

                        },
                        child: Text(
                          selectedMonth == null
                              ? "Select Month"
                              : DateFormat.yMMM().format(selectedMonth!),
                        ),
                      ),

                      const SizedBox(width: 12),

                      ElevatedButton(
                        onPressed: selectedUid == null ||
                            selectedMonth == null ||
                            selectedUid == "ALL"
                            ? null
                            : _loadSummary,
                        child: const Text("Load"),
                      ),
                      const SizedBox(width: 12),
                      if (selectedUid == "ALL")
                      ElevatedButton.icon(
                        icon: const Icon(Icons.download),
                        label: const Text("Export Excel"),
                        onPressed: selectedMonth == null || isExporting
                            ? null
                            : exportToExcel,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                /// RIGHT SIDE : SUMMARY
                if (isSingleEmployee)
                  Expanded(
                    flex: 3,
                    child: Builder(
                      builder: (_) {

                        int actualTotal = totalMinutes;
                        int difference = expectedMinutes - actualTotal;
                        final expectedDayCount = totalWorkingDays - leaveDays;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [

                                _infoCard(
                                  "Working Days",
                                  "$totalWorkingDays",
                                  Icons.calendar_month,
                                  Colors.blue,
                                ),

                                _infoCard(
                                  "Worked Days",
                                  "$workedDays",
                                  Icons.badge,
                                  Colors.green,
                                ),

                                _infoCard(
                                  "Expected Hours",
                                  formatHoursMinutes(expectedMinutes),
                                  Icons.schedule,
                                  Colors.orange,
                                ),

                                _infoCard(
                                  "Worked Hours",
                                  formatHoursMinutes(totalMinutes),
                                  Icons.timer,
                                  Colors.teal,
                                ),

                                _infoCard(
                                  "Difference",
                                  "${formatHoursMinutes(difference.abs())} ${difference > 0 ? "Short" : "Extra"}",
                                  Icons.analytics,
                                  difference > 0 ? Colors.red : Colors.green,
                                ),
                              ],
                            ),
                            if (expectedDayCount > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Tooltip(
                                  message:
                                      'Excludes weekends, holidays, leave '
                                      'and not-employed days',
                                  child: Text(
                                    'Expected hours = 9 h × '
                                    '$expectedDayCount working days',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (selectedUid != "ALL" && selectedUid != null)
            Row(
              children: [
                Expanded(child: _summaryCard("All", tableData.length, Colors.grey)),
                Expanded(child: _summaryCard("Present", presentDays, Colors.green)),
                if (offSatWorkDays > 0)
                  Expanded(
                    child: _summaryCard(
                      "Off-Sat Work",
                      offSatWorkDays,
                      Colors.teal,
                    ),
                  ),
                Expanded(child: _summaryCard("Leave", leaveDays, Colors.blue)),
                Expanded(child: _summaryCard("No Punch-In", absentDays, Colors.red)),
                Expanded(child: _summaryCard("Auto Punch-Out", autoPunchOutDays, Colors.orange)),
              ],
            ),
            const SizedBox(height: 4),
            if (selectedUid == "ALL")
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  "Export all employee attendance for the selected month.",
                  style: TextStyle(fontSize: 16),
                ),
              ),

            /// TABLE — fits viewport without scroll (for screenshots)
            if (selectedUid == null)
              const Expanded(
                child: Center(
                  child: Text(
                    "Select Employee and Month to view attendance",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
              )
            else if (selectedUid != "ALL")
              Expanded(
                child: filteredData.isEmpty
                    ? const Center(child: Text('No data for this month'))
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = _columnCountForHeight(
                            filteredData.length,
                            constraints.maxHeight,
                          );
                          final rowHeight = _rowHeightForLayout(
                            filteredData.length,
                            constraints.maxHeight,
                            columns,
                          );
                          final chunks = _splitIntoColumns(filteredData, columns);

                          final tableRow = Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (int i = 0; i < chunks.length; i++) ...[
                                if (i > 0)
                                  VerticalDivider(
                                    width: 20,
                                    thickness: 2,
                                    color: Colors.grey.shade400,
                                  ),
                                Expanded(
                                  child: _buildDayTable(
                                    chunks[i],
                                    rowHeight: rowHeight,
                                    showEmployee: false,
                                  ),
                                ),
                              ],
                            ],
                          );

                          final rowsPerColumn =
                              math.max(1, (filteredData.length / columns).ceil());
                          final neededHeight = 36.0 + rowsPerColumn * rowHeight;

                          if (neededHeight > constraints.maxHeight) {
                            return FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.topCenter,
                              child: SizedBox(
                                width: constraints.maxWidth,
                                height: neededHeight,
                                child: tableRow,
                              ),
                            );
                          }

                          return tableRow;
                        },
                      ),
              ),
          ],
        ),

      ),
            if (isExporting)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 10),
                      Text(
                        "Exporting Excel...",
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      )
                    ],
                  ),
                ),
              ),
    ],
      ),
    );
  }
}
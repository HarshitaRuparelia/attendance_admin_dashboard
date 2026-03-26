import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:month_picker_dialog/month_picker_dialog.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';


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
        child: Container(
          width: 120,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Column(
            children: [

              Icon(
                _statusIcon(title),
                color: color,
                size: 15,
              ),

              Text(
                value.toString(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),


              Text(title),

            ],
          ),
        ),
      ),
    );
  }

  bool isWorkingSaturday(DateTime day) {

    if (day.weekday != DateTime.saturday) return true;

    int saturdayCount = ((day.day - 1) ~/ 7) + 1;

    // Only 1st and 3rd Saturday are working
    return saturdayCount == 1 || saturdayCount == 3;
  }

  String format(int mins) {
    return "${mins ~/ 60}h ${(mins % 60).toString().padLeft(2, '0')}m";
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
                  fontSize: 10,
                  color: Colors.grey,
                ),
              ),

              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
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

        int empWorkedMinutes = 0;
        int empLeaveMinutes = 0;
        int empExpectedMinutes = 0;
        int empWorkedDays = 0;

        for (var row in tableData) {

          final date = row["date"] as DateTime;
          final status = row["status"];
          int minutes = (row["minutes"] as num?)?.toInt() ?? 0;

          //double hours = double.parse((minutes / 60).toStringAsFixed(2)); if want in decimal excel hrs then use this.

          sheet.appendRow([
            empName,
            DateFormat('dd-MMM-yyyy').format(date),
            DateFormat('EEE').format(date),
            status,
            format(minutes)
          ]);

          /// CALCULATE SUMMARY
          if (status == "Present" || status == "Auto Punch-Out") {
            empWorkedMinutes += minutes;
            empWorkedDays++;
            empExpectedMinutes += 570;
          }

          if (status == "Leave") {
            empLeaveMinutes += minutes;
            empExpectedMinutes += 570;
          }

          if (status == "No Punch-In") {
            empExpectedMinutes += 570;
          }
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
        format(expectedMinutes)
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
        format(totalMinutes)
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
          "${format(difference.abs())} ${difference > 0 ? "(Short)" : "(Extra)"}"
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
    final lastWorkingDay = lastDay;

    tableData.clear();
    totalMinutes = 0;
    totalLeaveMinutes = 0;
    expectedMinutes = 0;
    workedDays = 0;

    presentDays = 0;
    leaveDays = 0;
    absentDays = 0;
    autoPunchOutDays = 0;
    totalWorkingDays = 0;

    const dailyMinutes = 570; // 9h30m

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
        .where("punchInDate", isLessThanOrEqualTo: Timestamp.fromDate(lastDay));

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

      final ts = a["punchInTime"];
      if (ts == null) continue;

      final d = (ts as Timestamp).toDate();
      final recordDate = DateTime(d.year, d.month, d.day);

      final key =
          "${a["userId"]}_${recordDate.year}-${recordDate.month.toString().padLeft(2,'0')}-${recordDate.day.toString().padLeft(2,'0')}";

      attendanceMap[key] = a;
    }


    List<String> employeeIds = selectedUid == "ALL"
        ? widget.employees.map((e) => e["uid"].toString()).toList()
        : [selectedUid!];

    /// 3️⃣ Loop Through Each Day

    for (DateTime day = firstDay;
    !day.isAfter(lastWorkingDay);
    day = day.add(const Duration(days: 1))) {

      /// Skip Sundays
      if (day.weekday == DateTime.sunday) continue;

      /// Skip 2nd & 4th Saturday
      if (!isWorkingSaturday(day)) continue;

      final key =
          "${day.year}-${day.month.toString().padLeft(2,'0')}-${day.day.toString().padLeft(2,'0')}";

      /// Company holiday
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

      totalWorkingDays++;

      for (var empId in employeeIds) {

        /// 🔹 RECORD LOOKUP
        final record = attendanceMap["${empId}_$key"];

        /// 🔹 CHECK LEAVE
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

        /// LEAVE
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

        /// ABSENT
        if (record == null) {

          absentDays++;

          tableData.add({
            "employeeId": empId,
            "date": day,
            "status": "No Punch-In",
            "minutes": 0,
          });

        } else {

          final minutes = ((record["totalHours"] ?? 0) as num).toInt();
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

    final halfIndex = (filteredData.length / 2).ceil();

    final firstHalf = filteredData.sublist(0, halfIndex);
    final secondHalf = filteredData.sublist(halfIndex);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Employee Monthly Summary"),
      ),
      body: Stack(
          children: [

      Padding(
        padding: const EdgeInsets.all(16),
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
                        child: DropdownButtonFormField<String>(
                          value: selectedUid,
                          hint: const Text("Select Employee"),
                          items: [
                            const DropdownMenuItem(
                              value: "ALL",
                              child: Text("All Employees"),
                            ),
                            ...widget.employees.map<DropdownMenuItem<String>>((emp) {
                              return DropdownMenuItem(
                                value: emp["uid"].toString(),
                                child: Text(emp["name"]),
                              );
                            }).toList(),
                          ],
                          onChanged: (value) async {
                            setState(() {
                              selectedUid = value;
                            });

                            if (selectedMonth != null) {
                              await _loadSummary();
                            }
                          },
                        ),
                      ),

                      const SizedBox(width: 20),

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

                      const SizedBox(width: 15),

                      ElevatedButton(
                        onPressed: selectedUid == null ||
                            selectedMonth == null ||
                            selectedUid == "ALL"
                            ? null
                            : _loadSummary,
                        child: const Text("Load"),
                      ),
                      const SizedBox(width: 20),
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

                const SizedBox(width: 30),

                /// RIGHT SIDE : SUMMARY
                if (selectedUid != null && selectedUid != "ALL")
                  Expanded(
                    flex: 3,
                    child: Builder(
                      builder: (_) {

                        int actualTotal = totalMinutes;
                        int difference = expectedMinutes - actualTotal;

                        return Wrap(
                          spacing: 10,
                          runSpacing: 6,
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
                              format(expectedMinutes),
                              Icons.schedule,
                              Colors.orange,
                            ),

                            _infoCard(
                              "Worked Hours",
                              format(totalMinutes),
                              Icons.timer,
                              Colors.teal,
                            ),

                            _infoCard(
                              "Difference",
                              "${format(difference.abs())} ${difference > 0 ? "Short" : "Extra"}",
                              Icons.analytics,
                              difference > 0 ? Colors.red : Colors.green,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            if (selectedUid != "ALL")
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _summaryCard("All", tableData.length, Colors.grey),
                _summaryCard("Present", presentDays, Colors.green),
                _summaryCard("Leave", leaveDays, Colors.blue),
                _summaryCard("No Punch-In", absentDays, Colors.red),
                _summaryCard("Auto Punch-Out", autoPunchOutDays, Colors.orange),

              ],
            ),
            const SizedBox(height: 5),
            if (selectedUid == "ALL")
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  "Export all employee attendance for the selected month.",
                  style: TextStyle(fontSize: 16),
                ),
              ),

            /// TABLE
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
                child: Row(
                  children: [

                    /// LEFT TABLE
                    Expanded(
                      child: SingleChildScrollView(
                        child: DataTable(
                          columnSpacing: 18,
                          headingRowHeight: 36,

                          columns: const [
                            DataColumn(label: Text("Employee")),
                            DataColumn(label: Text("Date")),
                            DataColumn(label: Text("Day")),
                            DataColumn(label: Text("Status")),
                            DataColumn(label: Text("Worked Hours")),
                          ],
                          rows: firstHalf.map((row) {

                            final minutes = row["minutes"];
                            final hours = minutes ~/ 60;
                            final mins = minutes % 60;

                            return DataRow(
                              cells: [

                                DataCell(Text(getEmployeeName(row["employeeId"]))),

                                DataCell(Text(
                                    DateFormat('dd-MMM-yyyy').format(row["date"]))),

                                DataCell(Text(
                                    DateFormat('EEE').format(row["date"]))),

                                DataCell(
                                  Chip(
                                    label: Text(row["status"]),
                                    backgroundColor: _statusColor(row["status"]),
                                  ),
                                ),

                                DataCell(Text(
                                    "$hours h ${mins.toString().padLeft(2, '0')} m")),
                              ],
                            );

                          }).toList(),
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    /// RIGHT TABLE
                    Expanded(
                      child: SingleChildScrollView(
                        child: DataTable(
                          columnSpacing: 18,
                          headingRowHeight: 36,
                          columns: const [
                            DataColumn(label: Text("Employee")),
                            DataColumn(label: Text("Date")),
                            DataColumn(label: Text("Day")),
                            DataColumn(label: Text("Status")),
                            DataColumn(label: Text("Worked Hours")),
                          ],
                          rows: secondHalf.map((row) {

                            final minutes = row["minutes"];
                            final hours = minutes ~/ 60;
                            final mins = minutes % 60;

                            return DataRow(
                              cells: [

                                DataCell(Text(getEmployeeName(row["employeeId"]))),

                                DataCell(Text(
                                    DateFormat('dd-MMM-yyyy').format(row["date"]))),

                                DataCell(Text(
                                    DateFormat('EEE').format(row["date"]))),

                                DataCell(
                                  Chip(
                                    label: Text(row["status"]),
                                    backgroundColor: _statusColor(row["status"]),
                                  ),
                                ),

                                DataCell(Text(
                                    "$hours h ${mins.toString().padLeft(2, '0')} m")),
                              ],
                            );

                          }).toList(),
                        ),
                      ),
                    ),
                  ],
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
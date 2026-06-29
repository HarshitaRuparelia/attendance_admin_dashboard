import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'employee_utils.dart';
import 'leave_utils.dart';
import 'searchable_employee_dropdown.dart';

class LeaveBalanceScreen extends StatefulWidget {
  const LeaveBalanceScreen({super.key});

  @override
  State<LeaveBalanceScreen> createState() => _LeaveBalanceScreenState();
}

class _LeaveBalanceScreenState extends State<LeaveBalanceScreen> {
  LeaveCycle _selectedCycle = LeaveCycle.containing(DateTime.now());
  String? _selectedEmployeeId;
  List<Map<String, dynamic>> _employees = [];
  List<EmployeeLeaveStats> _stats = [];
  Map<String, String> _employeeNames = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void reassemble() {
    super.reassemble();
    setState(() {
      _stats = [];
      _loading = true;
    });
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final employees =
          (await fetchAllEmployees()).where(isSelectableEmployeeRecord).toList();
      final stats = await buildLeaveStatsForEmployees(
        employees: employees,
        cycle: _selectedCycle,
      );
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _employeeNames = employeeListToNameMap(employees);
        _stats = stats;
        _loading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('LeaveBalanceScreen load error: $e');
      debugPrint('$stackTrace');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading leave data: $e')),
      );
    }
  }

  List<EmployeeLeaveStats> get _filteredStats {
    if (_selectedEmployeeId == null || _selectedEmployeeId!.isEmpty) {
      return _stats;
    }
    return _stats
        .where((stat) => stat.userId == _selectedEmployeeId)
        .toList();
  }

  String get _accrualHelpText {
    final cycleLabel = _selectedCycle.label;
    final range =
        '${DateFormat('dd MMM yyyy').format(_selectedCycle.start)} – '
        '${DateFormat('dd MMM yyyy').format(_selectedCycle.end)}';
    return 'Leave year $cycleLabel ($range). '
        'Accrued = 1 leave per eligible month (max 12). '
        'New joiners get the join month only if they join on or before the 5th. '
        'Total = Opening + Accrued. Balance = Total − Taken. '
        'Tap Opening to edit.';
  }

  Future<void> _pickCycle() async {
    final cycles = LeaveCycle.recentCycles(count: 6);
    final picked = await showDialog<LeaveCycle>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select leave year (Apr–Mar)'),
        content: SizedBox(
          width: 280,
          child: ListView(
            shrinkWrap: true,
            children: cycles.map((cycle) {
              return ListTile(
                title: Text(cycle.label),
                subtitle: Text(
                  '${DateFormat('MMM yyyy').format(cycle.start)} – '
                  '${DateFormat('MMM yyyy').format(cycle.end)}',
                ),
                selected: cycle.startYear == _selectedCycle.startYear,
                onTap: () => Navigator.pop(context, cycle),
              );
            }).toList(),
          ),
        ),
      ),
    );

    if (picked != null && picked.startYear != _selectedCycle.startYear) {
      setState(() => _selectedCycle = picked);
      await _loadData();
    }
  }

  Future<void> _editOpeningBalance(EmployeeLeaveStats stat) async {
    final employee = _employees.firstWhere(
      (e) => e['uid'] == stat.userId,
      orElse: () => {},
    );
    if (employee.isEmpty) return;

    final controller = TextEditingController(
      text: stat.openingBalance.toStringAsFixed(1),
    );

    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Opening balance · ${stat.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Leave year ${_selectedCycle.label}',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Opening balance (days)',
                border: OutlineInputBorder(),
                helperText: 'Default is 0. Used at the start of this Apr–Mar cycle.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value == null || value < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter a valid number')),
                );
                return;
              }
              Navigator.pop(context, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result == null) return;

    final docId = employee['docId']?.toString() ?? stat.userId;
    final cycleKey = _selectedCycle.startYear.toString();
    try {
      final docRef =
          FirebaseFirestore.instance.collection('users').doc(docId);
      final existingDoc = await docRef.get();
      final existingData = existingDoc.data() ?? {};
      final balances = Map<String, dynamic>.from(
        existingData['leaveOpeningBalances'] is Map
            ? existingData['leaveOpeningBalances'] as Map
            : {},
      );
      balances[cycleKey] = result;
      await docRef.update({'leaveOpeningBalances': balances});
      if (!mounted) return;
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    }
  }

  Widget _buildStatTile(
    String label,
    String value,
    Color color, {
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: Card(
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
            child: Column(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSingleEmployeeSummary(EmployeeLeaveStats stat) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${stat.name} · Leave ${_selectedCycle.label}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatTile(
                'Opening',
                stat.openingBalance.toStringAsFixed(1),
                Colors.blueGrey,
                onTap: () => _editOpeningBalance(stat),
              ),
              const SizedBox(width: 12),
              _buildStatTile(
                'Total',
                stat.total.toStringAsFixed(1),
                Colors.blue,
              ),
              const SizedBox(width: 12),
              _buildStatTile(
                'Accrued',
                stat.accrued.toStringAsFixed(1),
                Colors.orange,
              ),
              const SizedBox(width: 12),
              _buildStatTile(
                'Taken',
                stat.taken.toStringAsFixed(1),
                Colors.deepPurple,
              ),
              const SizedBox(width: 12),
              _buildStatTile(
                'Balance',
                stat.balance.toStringAsFixed(1),
                stat.balance < 0 ? Colors.red : Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _accrualHelpText,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredStats;
    final isSingleEmployee = _selectedEmployeeId != null &&
        _selectedEmployeeId!.isNotEmpty &&
        filtered.length == 1;
    final totals = filtered.fold<(double, double, double, double, double)>(
      (0, 0, 0, 0, 0),
      (sum, stat) => (
        sum.$1 + stat.openingBalance,
        sum.$2 + stat.total,
        sum.$3 + stat.accrued,
        sum.$4 + stat.taken,
        sum.$5 + stat.balance,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isSingleEmployee
              ? '${filtered.first.name} · Leave ${_selectedCycle.label}'
              : 'Leave Balance',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _pickCycle,
                        icon: const Icon(Icons.calendar_today),
                        label: Text('Year: ${_selectedCycle.label}'),
                      ),
                      SizedBox(
                        width: 280,
                        child: SearchableEmployeeDropdown(
                          value: _selectedEmployeeId,
                          employees: _employeeNames,
                          onChanged: (value) {
                            setState(() => _selectedEmployeeId = value);
                          },
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() => _selectedEmployeeId = null);
                        },
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear Filter'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!isSingleEmployee)
                    Card(
                      color: Colors.orange.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Wrap(
                          spacing: 24,
                          runSpacing: 8,
                          children: [
                            Text(
                              'Opening: ${totals.$1.toStringAsFixed(1)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Total: ${totals.$2.toStringAsFixed(1)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Accrued: ${totals.$3.toStringAsFixed(1)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Taken: ${totals.$4.toStringAsFixed(1)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Balance: ${totals.$5.toStringAsFixed(1)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (!isSingleEmployee)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _accrualHelpText,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (isSingleEmployee)
                    _buildSingleEmployeeSummary(filtered.first)
                  else
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('No leave data found'))
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final tableWidth =
                                    math.min(constraints.maxWidth, 1100.0);
                                return SingleChildScrollView(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      width: tableWidth,
                                      child: DataTable(
                                        headingRowColor:
                                            WidgetStateProperty.all(
                                          Colors.grey.shade200,
                                        ),
                                        columns: const [
                                          DataColumn(label: Text('Employee')),
                                          DataColumn(label: Text('Opening')),
                                          DataColumn(label: Text('Total')),
                                          DataColumn(label: Text('Accrued')),
                                          DataColumn(label: Text('Taken')),
                                          DataColumn(label: Text('Balance')),
                                        ],
                                        rows: filtered.map((stat) {
                                          return DataRow(
                                            cells: [
                                              DataCell(Text(stat.name)),
                                              DataCell(
                                                InkWell(
                                                  onTap: () =>
                                                      _editOpeningBalance(stat),
                                                  child: Text(
                                                    stat.openingBalance
                                                        .toStringAsFixed(1),
                                                    style: const TextStyle(
                                                      color: Colors.blueGrey,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              DataCell(
                                                Text(stat.total
                                                    .toStringAsFixed(1)),
                                              ),
                                              DataCell(
                                                Text(stat.accrued
                                                    .toStringAsFixed(1)),
                                              ),
                                              DataCell(
                                                Text(
                                                  stat.taken.toStringAsFixed(1),
                                                ),
                                              ),
                                              DataCell(
                                                Text(
                                                  stat.balance
                                                      .toStringAsFixed(1),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: stat.balance < 0
                                                        ? Colors.red
                                                        : Colors.green,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        }).toList(),
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

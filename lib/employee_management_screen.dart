import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'employee_utils.dart';

class EmployeeManagementScreen extends StatefulWidget {
  const EmployeeManagementScreen({super.key});

  @override
  State<EmployeeManagementScreen> createState() =>
      _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  List<Map<String, dynamic>> _employees = [];
  bool _loading = true;
  String _searchQuery = '';
  String _statusFilter = 'All';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    setState(() => _loading = true);
    try {
      final employees = await fetchAllEmployees();
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _loading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('EmployeeManagementScreen load error: $e');
      debugPrint('$stackTrace');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading employees: $e')),
      );
    }
  }

  bool _isActiveEmployee(Map<String, dynamic> employee) {
    return isSelectableEmployeeRecord(employee);
  }

  List<Map<String, dynamic>> get _filteredEmployees {
    return _employees.where((employee) {
      final name = employee['name']?.toString().toLowerCase() ?? '';
      final email = employee['email']?.toString().toLowerCase() ?? '';
      final query = _searchQuery.trim().toLowerCase();
      if (query.isNotEmpty &&
          !name.contains(query) &&
          !email.contains(query)) {
        return false;
      }

      final active = _isActiveEmployee(employee);
      if (_statusFilter == 'Active' && !active) return false;
      if (_statusFilter == 'Resigned' && active) return false;
      return true;
    }).toList();
  }

  int get _activeCount =>
      _employees.where((e) => _isActiveEmployee(e)).length;

  int get _resignedCount => _employees.length - _activeCount;

  Future<void> _markResigned(Map<String, dynamic> employee) async {
    final initialDate = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Last working day',
    );
    if (picked == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark employee as resigned?'),
        content: Text(
          '${employee['name']} will be set inactive and hidden from '
          'active employee lists after ${DateFormat('dd MMM yyyy').format(picked)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final docId = employee['docId']?.toString() ?? employee['uid']?.toString();
    if (docId == null || docId.isEmpty) return;

    final resignedDay = DateTime(picked.year, picked.month, picked.day);

    try {
      await FirebaseFirestore.instance.collection('users').doc(docId).update({
        'isActive': false,
        'resignedDate': Timestamp.fromDate(resignedDay),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${employee['name']} marked as resigned')),
      );
      await _loadEmployees();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update: $e')),
      );
    }
  }

  bool _worksOnFirstThirdSat(Map<String, dynamic> employee) {
    return employee['clientSiteSchedule'] != true;
  }

  Future<void> _toggleWorksFirstThirdSat(Map<String, dynamic> employee) async {
    final docId = employee['docId']?.toString() ?? employee['uid']?.toString();
    if (docId == null || docId.isEmpty) return;

    final newWorksFirstThird = employee['clientSiteSchedule'] == true;
    final newClientSite = !newWorksFirstThird;

    try {
      await FirebaseFirestore.instance.collection('users').doc(docId).update({
        'clientSiteSchedule': newClientSite,
        'offFirstThirdSaturday': newClientSite,
        'worksOnOffSaturdays': false,
      });

      if (!mounted) return;
      setState(() {
        employee['clientSiteSchedule'] = newClientSite;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newWorksFirstThird
                ? '${employee['name']} — works on 1st & 3rd Sat (company schedule)'
                : '${employee['name']} — client deputed, off on 1st & 3rd Sat',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update: $e')),
      );
    }
  }

  Widget _buildWorksFirstThirdSwitch(Map<String, dynamic> employee) {
    final worksFirstThird = _worksOnFirstThirdSat(employee);

    return Tooltip(
      message: worksFirstThird
          ? 'Works on 1st & 3rd Saturday (company default).\n'
              'Off days: 2nd & 4th Saturday.'
          : 'Client-deputed schedule.\n'
              'Off on 1st & 3rd Saturday, works 2nd & 4th.',
      waitDuration: const Duration(milliseconds: 400),
      child: Switch(
        value: worksFirstThird,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: (_) => _toggleWorksFirstThirdSat(employee),
      ),
    );
  }

  Widget _summaryCard(String label, String value, Color color) {
    return Expanded(
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEmployees;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadEmployees,
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
                  Row(
                    children: [
                      _summaryCard(
                        'Total',
                        _employees.length.toString(),
                        Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      _summaryCard(
                        'Active',
                        _activeCount.toString(),
                        Colors.green,
                      ),
                      const SizedBox(width: 12),
                      _summaryCard(
                        'Resigned',
                        _resignedCount.toString(),
                        Colors.orange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 280,
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: 'Search employee',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) =>
                              setState(() => _searchQuery = value),
                        ),
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'All', label: Text('All')),
                            ButtonSegment(
                              value: 'Active',
                              label: Text('Active'),
                            ),
                            ButtonSegment(
                              value: 'Resigned',
                              label: Text('Resigned'),
                            ),
                          ],
                          selected: {_statusFilter},
                          onSelectionChanged: (value) {
                            setState(() => _statusFilter = value.first);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Showing ${filtered.length} employee(s)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No employees found'))
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              const minTableWidth = 1280.0;
                              final tableWidth =
                                  math.max(constraints.maxWidth, minTableWidth);
                              return SingleChildScrollView(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: SizedBox(
                                    width: tableWidth,
                                    child: DataTable(
                                      columnSpacing: 16,
                                      horizontalMargin: 12,
                                      headingRowHeight: 44,
                                      dataRowMinHeight: 48,
                                      headingRowColor:
                                          WidgetStateProperty.all(
                                        Colors.grey.shade200,
                                      ),
                                      columns: const [
                                        DataColumn(label: Text('Name')),
                                        DataColumn(label: Text('Email')),
                                        DataColumn(label: Text('Created')),
                                        DataColumn(label: Text('Status')),
                                        DataColumn(label: Text('Resigned')),
                                        DataColumn(
                                          label: Tooltip(
                                            message:
                                                'Works on 1st & 3rd Saturday\n'
                                                'ON: company schedule (off 2nd & 4th Sat)\n'
                                                'OFF: client-deputed (off 1st & 3rd Sat)',
                                            child: Text(
                                              'Works on 1st & 3rd',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataColumn(label: Text('Action')),
                                      ],
                                      rows: filtered.map((employee) {
                                        final active =
                                            _isActiveEmployee(employee);
                                        final resignedDate =
                                            employee['resignedDate']
                                                as DateTime?;
                                        final createdAt =
                                            employee['createdAt'] as DateTime?;
                                        return DataRow(
                                          cells: [
                                            DataCell(
                                              Text(
                                                employee['name']?.toString() ??
                                                    'Unknown',
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                employee['email']?.toString() ??
                                                    '-',
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                createdAt != null
                                                    ? DateFormat(
                                                        'dd MMM yyyy',
                                                      ).format(createdAt)
                                                    : '-',
                                              ),
                                            ),
                                            DataCell(
                                              Chip(
                                                label: Text(
                                                  active
                                                      ? 'Active'
                                                      : 'Resigned',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                backgroundColor: active
                                                    ? Colors.green
                                                    : Colors.orange,
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                resignedDate != null
                                                    ? DateFormat('dd MMM yyyy')
                                                        .format(resignedDate)
                                                    : '-',
                                              ),
                                            ),
                                            DataCell(
                                              active
                                                  ? _buildWorksFirstThirdSwitch(
                                                      employee,
                                                    )
                                                  : Text(
                                                      _worksOnFirstThirdSat(
                                                              employee)
                                                          ? 'Yes'
                                                          : 'No',
                                                    ),
                                            ),
                                            DataCell(
                                              active
                                                  ? Tooltip(
                                                      message: 'Mark Resigned',
                                                      child: IconButton(
                                                        icon: const Icon(
                                                          Icons.person_off,
                                                          size: 20,
                                                        ),
                                                        onPressed: () =>
                                                            _markResigned(
                                                              employee,
                                                            ),
                                                      ),
                                                    )
                                                  : const Text('-'),
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

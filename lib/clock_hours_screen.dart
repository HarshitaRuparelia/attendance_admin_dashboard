import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'clock_time_utils.dart';
import 'employee_utils.dart';
import 'searchable_employee_dropdown.dart';

class ClockHoursScreen extends StatefulWidget {
  const ClockHoursScreen({super.key});

  @override
  State<ClockHoursScreen> createState() => _ClockHoursScreenState();
}

class _ClockHoursScreenState extends State<ClockHoursScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  Map<String, String> _employees = {};
  String? _selectedEmployee;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedClient;
  String? _selectedTask;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 0);
    _loadEmployees();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    final active = await fetchActiveEmployeeNameMap();
    if (!mounted) return;
    setState(() => _employees = active);
  }

  bool _matchesDateRange(DateTime? workDate) {
    if (workDate == null) return false;
    final day = DateTime(workDate.year, workDate.month, workDate.day);
    if (_startDate != null) {
      final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
      if (day.isBefore(start)) return false;
    }
    if (_endDate != null) {
      final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
      if (day.isAfter(end)) return false;
    }
    return true;
  }

  List<ClockHourEntry> _filterEntries(List<ClockHourEntry> entries) {
    return entries.where((entry) {
      if (_selectedEmployee != null &&
          _selectedEmployee!.isNotEmpty &&
          entry.employeeId != _selectedEmployee) {
        return false;
      }
      if (_selectedClient != null &&
          entry.clientName.toLowerCase() != _selectedClient!.toLowerCase()) {
        return false;
      }
      if (_selectedTask != null &&
          entry.taskName.toLowerCase() != _selectedTask!.toLowerCase()) {
        return false;
      }
      return _matchesDateRange(entry.workDate);
    }).toList();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked.start;
      _endDate = picked.end;
    });
  }

  Future<void> _exportHours(List<ClockHourEntry> entries) async {
    if (entries.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final path = await exportClockHoursToExcel(entries: entries);
      if (!mounted) return;
      await openExportedFile(path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported ${entries.length} rows to $path'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String get _dateRangeLabel {
    if (_startDate == null || _endDate == null) return 'Select date range';
    return '${DateFormat('dd MMM').format(_startDate!)} - '
        '${DateFormat('dd MMM yyyy').format(_endDate!)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clock Hours'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.schedule), text: 'Clocked Hours'),
            Tab(icon: Icon(Icons.list_alt), text: 'Clients & Tasks'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ClockHoursViewTab(
            employees: _employees,
            selectedEmployee: _selectedEmployee,
            selectedClient: _selectedClient,
            selectedTask: _selectedTask,
            dateRangeLabel: _dateRangeLabel,
            exporting: _exporting,
            onEmployeeChanged: (value) =>
                setState(() => _selectedEmployee = value),
            onClientChanged: (value) => setState(() => _selectedClient = value),
            onTaskChanged: (value) => setState(() => _selectedTask = value),
            onPickDateRange: _pickDateRange,
            onClearFilters: () => setState(() {
              _selectedEmployee = null;
              _selectedClient = null;
              _selectedTask = null;
              final now = DateTime.now();
              _startDate = DateTime(now.year, now.month, 1);
              _endDate = DateTime(now.year, now.month + 1, 0);
            }),
            filterEntries: _filterEntries,
            onExport: _exportHours,
          ),
          const _ClockMasterDataTab(),
        ],
      ),
    );
  }
}

class _ClockHoursViewTab extends StatelessWidget {
  final Map<String, String> employees;
  final String? selectedEmployee;
  final String? selectedClient;
  final String? selectedTask;
  final String dateRangeLabel;
  final bool exporting;
  final ValueChanged<String?> onEmployeeChanged;
  final ValueChanged<String?> onClientChanged;
  final ValueChanged<String?> onTaskChanged;
  final VoidCallback onPickDateRange;
  final VoidCallback onClearFilters;
  final List<ClockHourEntry> Function(List<ClockHourEntry>) filterEntries;
  final Future<void> Function(List<ClockHourEntry>) onExport;

  const _ClockHoursViewTab({
    required this.employees,
    required this.selectedEmployee,
    required this.selectedClient,
    required this.selectedTask,
    required this.dateRangeLabel,
    required this.exporting,
    required this.onEmployeeChanged,
    required this.onClientChanged,
    required this.onTaskChanged,
    required this.onPickDateRange,
    required this.onClearFilters,
    required this.filterEntries,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ClockHourEntry>>(
      stream: watchClockHours(),
      builder: (context, hoursSnapshot) {
        return StreamBuilder<List<ClockMasterItem>>(
          stream: watchActiveClockClients(),
          builder: (context, clientsSnapshot) {
            return StreamBuilder<List<ClockMasterItem>>(
              stream: watchActiveClockTasks(),
              builder: (context, tasksSnapshot) {
                final allEntries = hoursSnapshot.data ?? [];
                final filtered = filterEntries(allEntries);
                final totalHours =
                    filtered.fold<double>(0, (sum, e) => sum + e.hours);
                final clients = clientsSnapshot.data ?? [];
                final tasks = tasksSnapshot.data ?? [];
                final loading = hoursSnapshot.connectionState ==
                        ConnectionState.waiting &&
                    !hoursSnapshot.hasData;

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 260,
                            child: SearchableEmployeeDropdown(
                              value: selectedEmployee,
                              employees: employees,
                              onChanged: onEmployeeChanged,
                              labelText: 'Employee',
                            ),
                          ),
                          SizedBox(
                            width: 200,
                            child: _MasterFilterDropdown(
                              label: 'Client',
                              value: selectedClient,
                              items: clients.map((c) => c.name).toList(),
                              onChanged: onClientChanged,
                            ),
                          ),
                          SizedBox(
                            width: 200,
                            child: _MasterFilterDropdown(
                              label: 'Task',
                              value: selectedTask,
                              items: tasks.map((t) => t.name).toList(),
                              onChanged: onTaskChanged,
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: onPickDateRange,
                            icon: const Icon(Icons.date_range),
                            label: Text(dateRangeLabel),
                          ),
                          OutlinedButton.icon(
                            onPressed: onClearFilters,
                            icon: const Icon(Icons.clear),
                            label: const Text('Clear'),
                          ),
                          ElevatedButton.icon(
                            onPressed: exporting || filtered.isEmpty
                                ? null
                                : () => onExport(filtered),
                            icon: exporting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.download),
                            label: const Text('Export Excel'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amberAccent.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.black45),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${filtered.length} entr${filtered.length == 1 ? 'y' : 'ies'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Total: ${formatClockHours(totalHours)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: loading
                            ? const Center(child: CircularProgressIndicator())
                            : filtered.isEmpty
                                ? Center(
                                    child: Text(
                                      allEntries.isEmpty
                                          ? 'No clock hours logged yet.\n'
                                              'Employees will log client, task and hours '
                                              'from the employee app.\n\n'
                                              'Set up clients and tasks in the next tab.'
                                          : 'No entries match the selected filters.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 15,
                                      ),
                                    ),
                                  )
                                : Card(
                                    clipBehavior: Clip.antiAlias,
                                    child: ListView.separated(
                                      itemCount: filtered.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final entry = filtered[index];
                                        final dateText = entry.workDate != null
                                            ? DateFormat('dd MMM yyyy')
                                                .format(entry.workDate!)
                                            : '-';
                                        return ListTile(
                                          leading: CircleAvatar(
                                            child: Text(
                                              entry.employeeName.isNotEmpty
                                                  ? entry.employeeName[0]
                                                      .toUpperCase()
                                                  : '?',
                                            ),
                                          ),
                                          title: Text(
                                            '${entry.employeeName} · $dateText',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          subtitle: Text(
                                            '${entry.clientName} · ${entry.taskName}'
                                            '${entry.notes.isNotEmpty ? '\n${entry.notes}' : ''}',
                                          ),
                                          trailing: Text(
                                            formatClockHours(entry.hours),
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _MasterFilterDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _MasterFilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text('All $label${label.endsWith('s') ? '' : 's'}'),
        ),
        ...items.map(
          (name) => DropdownMenuItem<String>(
            value: name,
            child: Text(name, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _ClockMasterDataTab extends StatefulWidget {
  const _ClockMasterDataTab();

  @override
  State<_ClockMasterDataTab> createState() => _ClockMasterDataTabState();
}

class _ClockMasterDataTabState extends State<_ClockMasterDataTab> {
  bool _importing = false;
  bool _downloadingTemplate = false;

  Future<void> _downloadTemplate() async {
    setState(() => _downloadingTemplate = true);
    try {
      final path = await downloadClockMasterTemplate();
      if (!mounted) return;
      await openExportedFile(path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Template saved: $path'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Template download failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _downloadingTemplate = false);
    }
  }

  Future<void> _importExcel() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.first;
    final bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read the selected file.')),
      );
      return;
    }

    setState(() => _importing = true);
    try {
      final result = await importClockMasterDataFromExcelBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.summaryText()),
          duration: const Duration(seconds: 5),
          backgroundColor: result.totalChanges > 0 ? Colors.green : Colors.orange,
        ),
      );
      if (result.errors.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Import warnings'),
            content: SingleChildScrollView(
              child: Text(result.errors.join('\n')),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _promptAdd({required bool isClient}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isClient ? 'Add client' : 'Add task'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: isClient ? 'Client name' : 'Task name',
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return;

    try {
      final outcome = isClient
          ? await addClockClient(result)
          : await addClockTask(result);
      if (!mounted) return;
      final label = switch (outcome) {
        ClockImportItemResult.added => 'Added',
        ClockImportItemResult.reactivated => 'Reactivated',
        ClockImportItemResult.skipped => 'Already exists',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label: $result')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add: $e')),
      );
    }
  }

  Future<void> _approveItem(ClockMasterItem item, {required bool isClient}) async {
    if (isClient) {
      await approveClockClient(item.id);
    } else {
      await approveClockTask(item.id);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Approved: ${item.name}'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _rejectItem(ClockMasterItem item, {required bool isClient}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject request?'),
        content: Text(
          'Reject "${item.name}" requested by ${item.requestedByName}? '
          'It will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    if (isClient) {
      await rejectClockClient(item.id);
    } else {
      await rejectClockTask(item.id);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Rejected: ${item.name}')),
    );
  }

  Future<void> _confirmDeactivate(ClockMasterItem item, {required bool isClient}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${isClient ? 'client' : 'task'}?'),
        content: Text(
          '"${item.name}" will be permanently deleted. '
          'Existing clock hour entries are not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    if (isClient) {
      await deactivateClockClient(item.id);
    } else {
      await deactivateClockTask(item.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Excel import',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Use the template with two sheets: "Clients" and "Tasks". '
                    'Row 1 is the header; names start from row 2. '
                    'Import adds new names and skips duplicates.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _downloadingTemplate ? null : _downloadTemplate,
                        icon: _downloadingTemplate
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download),
                        label: const Text('Download template'),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _importing ? null : _importExcel,
                        icon: _importing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.upload_file),
                        label: const Text('Import Excel'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _MasterListPanel(
                    title: 'Clients',
                    stream: watchAllClockClients(),
                    onAdd: () => _promptAdd(isClient: true),
                    onRemove: (item) => _confirmDeactivate(item, isClient: true),
                    onApprove: (item) => _approveItem(item, isClient: true),
                    onReject: (item) => _rejectItem(item, isClient: true),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _MasterListPanel(
                    title: 'Tasks',
                    stream: watchAllClockTasks(),
                    onAdd: () => _promptAdd(isClient: false),
                    onRemove: (item) => _confirmDeactivate(item, isClient: false),
                    onApprove: (item) => _approveItem(item, isClient: false),
                    onReject: (item) => _rejectItem(item, isClient: false),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MasterListPanel extends StatelessWidget {
  final String title;
  final Stream<List<ClockMasterItem>> stream;
  final VoidCallback onAdd;
  final Future<void> Function(ClockMasterItem item) onRemove;
  final Future<void> Function(ClockMasterItem item) onApprove;
  final Future<void> Function(ClockMasterItem item) onReject;

  const _MasterListPanel({
    required this.title,
    required this.stream,
    required this.onAdd,
    required this.onRemove,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<ClockMasterItem>>(
              stream: stream,
              builder: (context, snapshot) {
                final items = (snapshot.data ?? [])
                    .where(
                      (item) =>
                          (item.isApproved && item.isActive) || item.isPending,
                    )
                    .toList()
                  ..sort((a, b) {
                    if (a.isPending != b.isPending) {
                      return a.isPending ? -1 : 1;
                    }
                    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                  });
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      'No $title yet.\nAdd manually or import Excel.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      dense: true,
                      tileColor: item.isPending ? Colors.orange.shade50 : null,
                      title: Text(item.name),
                      subtitle: Text(
                        item.isPending
                            ? 'Pending · requested by ${item.requestedByName.isEmpty ? 'employee' : item.requestedByName}'
                            : item.source == 'excel'
                                ? 'From Excel'
                                : item.source == 'employee'
                                    ? 'Added by employee (approved)'
                                    : 'Added manually',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: item.isPending
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check_circle,
                                      color: Colors.green),
                                  tooltip: 'Approve',
                                  onPressed: () => onApprove(item),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.cancel,
                                      color: Colors.red),
                                  tooltip: 'Reject',
                                  onPressed: () => onReject(item),
                                ),
                              ],
                            )
                          : IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              tooltip: 'Remove',
                              onPressed: () => onRemove(item),
                            ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'data_retention_utils.dart';
import 'employee_utils.dart';
import 'searchable_employee_dropdown.dart';
class UserLogsScreen extends StatefulWidget {
  const UserLogsScreen({super.key});

  @override
  State<UserLogsScreen> createState() => _UserLogsScreenState();
}

class _UserLogsScreenState extends State<UserLogsScreen> {
  String? selectedUid;
  bool showLogs = false;
  Map<String, String> _employees = {};

  DateTime? startDate;
  DateTime? endDate;
  bool _isDeleting = false;
  bool _isBulkCleaning = false;
  String _bulkCleanupStatus = '';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    final employees = await fetchActiveEmployeeNameMap();
    if (!mounted) return;
    setState(() => _employees = employees);
  }

  // ---------------- DATE PICKER ----------------
  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        startDate = picked.start;
        endDate = picked.end;
        showLogs = false; // re-search required
      });
    }
  }
  Future<void> _deleteLogs() async {
    if (selectedUid == null || startDate == null || endDate == null) return;
    setState(() {
      _isDeleting = true;
    });

    try {
      final query = FirebaseFirestore.instance
          .collection('logs')
          .where('uid', isEqualTo: selectedUid)
          .where(
        'timestamp',
        isGreaterThanOrEqualTo: Timestamp.fromDate(startDate!),
      )
          .where(
        'timestamp',
        isLessThanOrEqualTo: Timestamp.fromDate(
          DateTime(
            endDate!.year,
            endDate!.month,
            endDate!.day,
            23,
            59,
            59,
          ),
        ),
      );

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No logs found to delete")),
        );
        setState(() {
          _isDeleting = false;
        });
        return;
      }

      WriteBatch batch = FirebaseFirestore.instance.batch();
      int count = 0;

      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
        count++;

        // Firestore limit: 500 operations per batch
        if (count % 500 == 0) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
        }
      }

      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Deleted $count logs successfully")),
      );

      setState(() {
        showLogs = false;
      });
    } catch (e) {
      print("Exception: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error deleting logs: $e")),
      );
    }
    setState(() {
      _isDeleting = false;
    });
  }

  Future<void> _confirmDeleteLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Logs"),
        content: const Text(
          "Are you sure you want to delete all logs for the selected user "
              "within the selected date range?\n\nThis action cannot be undone.",
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete"),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _deleteLogs();
    }
  }

  Future<void> _confirmBulkRetentionCleanup() async {
    final keepLabel = retentionKeepLabel();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bulk cleanup (all users)'),
        content: Text(
          'Delete logs and attendance selfies for ALL users except:\n\n'
          '• $keepLabel\n\n'
          'Attendance records are kept; only selfie files and URLs are removed '
          'for older months.\n\n'
          'Stay on this screen until cleanup finishes — do not press Back.\n\n'
          'This cannot be undone. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete old data'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _isBulkCleaning = true;
      _bulkCleanupStatus = 'Starting cleanup...';
    });

    try {
      final result = await cleanupLogsAndSelfiesOutsideRetention(
        onProgress: (stage, count) {
          if (!mounted) return;
          setState(() {
            _bulkCleanupStatus = stage == 'logs'
                ? 'Deleting logs... ($count so far)'
                : 'Deleting selfies... ($count files so far)';
          });
        },
      );

      if (!mounted) return;
      final errorNote = result.errors.isEmpty
          ? ''
          : '\n${result.errors.length} warnings — check console.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Done. Logs deleted: ${result.logsDeleted}, '
            'selfies deleted: ${result.selfiesDeleted}, '
            'attendance rows updated: ${result.attendanceUpdated}.$errorNote',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
      for (final err in result.errors.take(5)) {
        debugPrint('Retention cleanup: $err');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bulk cleanup failed: $e')),
      );
    }

    if (mounted) {
      setState(() {
        _isBulkCleaning = false;
        _bulkCleanupStatus = '';
        showLogs = false;
      });
    }
  }


  // ---------------- LOG STREAM ----------------
  Stream<QuerySnapshot> _logsStream() {
    print("selectedUid===>  $selectedUid");
    Query query = FirebaseFirestore.instance
        .collection('logs')
        .where('uid', isEqualTo: selectedUid)
        .orderBy('timestamp', descending: true)
        .limit(500);

    if (startDate != null && endDate != null) {
      query = query
          .where(
        'timestamp',
        isGreaterThanOrEqualTo: Timestamp.fromDate(startDate!),
      )
          .where(
        'timestamp',
        isLessThanOrEqualTo: Timestamp.fromDate(
          DateTime(
            endDate!.year,
            endDate!.month,
            endDate!.day,
            23,
            59,
            59,
          ),
        ),
      );
    }

    return query.snapshots();
  }

  Future<bool> _onBackDuringCleanup() async {
    if (!_isBulkCleaning && !_isDeleting) return true;

    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cleanup in progress'),
        content: const Text(
          'Deletion is still running. If you leave now:\n\n'
          '• Some old logs/selfies may already be deleted\n'
          '• The rest may not be deleted\n'
          '• You will not see the final summary\n\n'
          'Wait on this screen until it finishes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave anyway'),
          ),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isBulkCleaning && !_isDeleting,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldLeave = await _onBackDuringCleanup();
        if (shouldLeave && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text("User Activity Logs"),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _pickDateRange,
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete, color: Colors.white),
            label: const Text("Delete Logs"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: _isDeleting
            ? null
            : selectedUid == null || startDate == null || endDate == null
                ? null
                : _confirmDeleteLogs,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildFilters(),
              const Divider(height: 1),
              Expanded(
                child: showLogs
                    ? _buildLogsList()
                    : const Center(
                  child: Text(
                    "Select a user and tap 'View Logs'",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ],
          ),

          // 🔴 FULL SCREEN LOADER WHEN DELETING
          if (_isDeleting || _isBulkCleaning)
            Container(
              color: Colors.black.withValues(alpha: 0.4),
              child: Center(
                child: Card(
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 20),
                        Text(
                          _isBulkCleaning
                              ? '$_bulkCleanupStatus\n\nDo not press Back.'
                              : 'Deleting logs...\n\nDo not press Back.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }

  // ---------------- FILTER UI ----------------
  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bulk cleanup (all users)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Keeps only ${retentionKeepLabel()}. '
                    'Deletes older logs and attendance selfies for everyone.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.cleaning_services),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _isDeleting || _isBulkCleaning
                          ? null
                          : _confirmBulkRetentionCleanup,
                      label: const Text('Delete old logs & selfies'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildUserDropdown(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.visibility),
                  label: const Text("View Logs"),
                  onPressed: selectedUid == null
                      ? null
                      : () {
                    setState(() {
                      showLogs = true;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    selectedUid = null;
                    startDate = null;
                    endDate = null;
                    showLogs = false;
                  });
                },
                child: const Text("Clear"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatLogData(Map<String, dynamic> data) {
    return data.entries
        .map((e) => "${e.key}: ${e.value}")
        .join("  |  ");
  }


  // ---------------- USERS DROPDOWN ----------------
  Widget _buildUserDropdown() {
    if (_employees.isEmpty) {
      return const LinearProgressIndicator();
    }

    return SearchableEmployeeDropdown(
      value: selectedUid,
      employees: _employees,
      showClearOption: false,
      hint: 'Select User',
      labelText: 'Select User',
      onChanged: (value) {
        setState(() {
          selectedUid = value;
          showLogs = false;
        });
      },
    );
  }

  // ---------------- LOG LIST ----------------
  Widget _buildLogsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _logsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("No logs found"));
        }

        final logs = snapshot.data!.docs;

        return ListView.builder(
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final doc = logs[index];
            final Map<String, dynamic> logData =
                doc['data'] as Map<String, dynamic>? ?? {};

            final Timestamp? ts = doc['timestamp'];
            final String event = doc['event'] ?? "-";

            final String timeText = ts != null
                ? DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate())
                : "No timestamp";

            // 🔴 Highlight special events
            bool isCritical = event.toLowerCase().contains("delete") ||
                event.toLowerCase().contains("change") ||
                event.toLowerCase().contains("manual");

            return Card(
              margin:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListTile(
                leading: Icon(
                  Icons.event_note,
                  color: isCritical ? Colors.red : Colors.blue,
                ),
                title: Text(
                  "$timeText  -  $event",
                  style: TextStyle(
                    fontWeight:
                    isCritical ? FontWeight.bold : FontWeight.normal,
                    color: isCritical ? Colors.red : Colors.black,
                  ),
                ),

                // ✅ Show subtitle only if data exists
                subtitle: logData.isNotEmpty
                    ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _formatLogData(logData),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                  ),
                )
                    : null,
              ),
            );
          },
        );
      },
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class UserLogsScreen extends StatefulWidget {
  const UserLogsScreen({super.key});

  @override
  State<UserLogsScreen> createState() => _UserLogsScreenState();
}

class _UserLogsScreenState extends State<UserLogsScreen> {
  String? selectedUid;
  bool showLogs = false;

  DateTime? startDate;
  DateTime? endDate;
  bool _isDeleting = false;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          if (_isDeleting)
            Container(
              color: Colors.black.withOpacity(0.4),
              child: const Center(
                child: Card(
                  elevation: 8,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 20),
                        Text(
                          "Deleting logs...",
                          style: TextStyle(
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
    );
  }

  // ---------------- FILTER UI ----------------
  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
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
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .orderBy('name')
          .snapshots(),
      builder:  (context, snapshot) {
        if (!snapshot.hasData) {
          return const LinearProgressIndicator();
        }

        final docs = snapshot.data!.docs.toList();

        // ✅ Sort alphabetically ignoring case
        docs.sort((a, b) {
          final nameA =
              (a.data() as Map<String, dynamic>)['name']
                  ?.toString()
                  .toLowerCase() ?? '';
          final nameB =
              (b.data() as Map<String, dynamic>)['name']
                  ?.toString()
                  .toLowerCase() ?? '';
          return nameA.compareTo(nameB);
        });

        return DropdownButtonFormField<String>(
          value: selectedUid,
          decoration: const InputDecoration(
            labelText: "Select User",
            border: OutlineInputBorder(),
          ),
          items: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return DropdownMenuItem<String>(
              value: data['uid'],
              child: Text(
                "${data['name']} (${data['email']})",
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              selectedUid = value;
              showLogs = false;
            });
          },
        );
      }
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

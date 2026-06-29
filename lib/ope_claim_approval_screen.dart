import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'employee_utils.dart';
import 'searchable_employee_dropdown.dart';

class OpeClaimApprovalScreen extends StatefulWidget {
  const OpeClaimApprovalScreen({super.key});

  @override
  State<OpeClaimApprovalScreen> createState() => _OpeClaimApprovalScreenState();
}

class _OpeClaimApprovalScreenState extends State<OpeClaimApprovalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, String> employees = {};
  String? selectedEmployee;
  DateTime? startDate;
  DateTime? endDate;

  final NumberFormat _currency =
      NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  DateTimeRange _currentMonthRange([DateTime? reference]) {
    final now = reference ?? DateTime.now();
    return DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0),
    );
  }

  void _applyCurrentMonthRange() {
    final range = _currentMonthRange();
    startDate = range.start;
    endDate = range.end;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _applyCurrentMonthRange();
    _fetchEmployees();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchEmployees() async {
    final active = await fetchActiveEmployeeNameMap();
    if (!mounted) return;
    setState(() => employees = active);
  }

  Stream<QuerySnapshot> _getClaimStream(String status) {
    // Filter by status only — sort by date client-side to avoid a composite index.
    return FirebaseFirestore.instance
        .collection('ope_claims')
        .where('status', isEqualTo: status.toLowerCase())
        .snapshots();
  }

  int _compareClaimsByDate(QueryDocumentSnapshot a, QueryDocumentSnapshot b) {
    final aDate = (a.data() as Map<String, dynamic>)['date']?.toString() ?? '';
    final bDate = (b.data() as Map<String, dynamic>)['date']?.toString() ?? '';
    return bDate.compareTo(aDate);
  }

  bool _matchesFilters(Map<String, dynamic> data) {
    if (selectedEmployee != null &&
        selectedEmployee!.isNotEmpty &&
        data['employeeId'] != selectedEmployee) {
      return false;
    }

    final dateStr = data['date']?.toString();
    if (dateStr == null || dateStr.isEmpty) return false;

    final claimDate = DateTime.tryParse(dateStr);
    if (claimDate == null) return false;

    final normalized =
        DateTime(claimDate.year, claimDate.month, claimDate.day);

    if (startDate != null) {
      final start =
          DateTime(startDate!.year, startDate!.month, startDate!.day);
      if (normalized.isBefore(start)) return false;
    }

    if (endDate != null) {
      final end = DateTime(endDate!.year, endDate!.month, endDate!.day);
      if (normalized.isAfter(end)) return false;
    }

    return true;
  }

  String get _dateRangeLabel {
    if (startDate == null || endDate == null) return 'Select Date Range';
    return '${DateFormat('dd MMM').format(startDate!)} - ${DateFormat('dd MMM yyyy').format(endDate!)}';
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: startDate != null && endDate != null
          ? DateTimeRange(start: startDate!, end: endDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        startDate = picked.start;
        endDate = picked.end;
      });
    }
  }

  Future<String?> _promptRemark({required bool isReject}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isReject ? 'Reject claim' : 'Approve claim'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: isReject ? 'Reason (optional)' : 'Remark (optional)',
            border: const OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isReject ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(isReject ? 'Reject' : 'Approve'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _updateClaimStatus(
    String docId,
    String status, {
    String remark = '',
  }) async {
    await FirebaseFirestore.instance.collection('ope_claims').doc(docId).update({
      'status': status.toLowerCase(),
      'adminRemark': remark,
      'reviewedAt': FieldValue.serverTimestamp(),
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Claim marked as ${status.toLowerCase()}')),
      );
    }
  }

  Future<void> _handleApprove(String docId) async {
    final remark = await _promptRemark(isReject: false);
    if (remark == null) return;
    await _updateClaimStatus(docId, 'approved', remark: remark);
  }

  Future<void> _handleReject(String docId) async {
    final remark = await _promptRemark(isReject: true);
    if (remark == null) return;
    await _updateClaimStatus(docId, 'rejected', remark: remark);
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  void _showFullImage(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.image_not_supported, size: 48),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openProof(String url) async {
    if (url.isEmpty) return;

    final lower = url.toLowerCase();
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp')) {
      _showFullImage(url);
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open proof file')),
      );
    }
  }

  void _showTextDialog(String title, String text) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 280,
                child: SearchableEmployeeDropdown(
                  value: selectedEmployee,
                  employees: employees,
                  onChanged: (value) {
                    setState(() => selectedEmployee = value);
                  },
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.date_range),
                label: Text(_dateRangeLabel),
                onPressed: () => _selectDateRange(context),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  setState(() {
                    selectedEmployee = null;
                    _applyCurrentMonthRange();
                  });
                },
                label: const Text('Clear Filters'),
              ),
            ],
          ),
          if (startDate != null && endDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Showing claims for $_dateRangeLabel',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildClaimList(String status) {
    return StreamBuilder<QuerySnapshot>(
      stream: _getClaimStream(status),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading claims: ${snapshot.error}'),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text('No $status claims found'));
        }

        final docs = snapshot.data!.docs
            .where((doc) => _matchesFilters(doc.data() as Map<String, dynamic>))
            .toList()
          ..sort(_compareClaimsByDate);

        if (docs.isEmpty) {
          return Center(
            child: Text('No $status claims found for $_dateRangeLabel'),
          );
        }

        final totalAmount = docs.fold<double>(0, (sum, doc) {
          final data = doc.data() as Map<String, dynamic>;
          return sum + ((data['amount'] as num?)?.toDouble() ?? 0);
        });

        return LayoutBuilder(
          builder: (context, constraints) {
            final tableWidth = math.min(constraints.maxWidth, 1400.0);

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${docs.length} claim(s) • ${_currency.format(totalAmount)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: Center(
                      child: SizedBox(
                        width: tableWidth,
                        child: DataTable(
                          columnSpacing: 16,
                          headingRowHeight: 45,
                          dataRowMinHeight: 55,
                          dataRowMaxHeight: 80,
                          headingRowColor:
                              MaterialStateProperty.all(Colors.grey.shade200),
                          columns: const [
                            DataColumn(label: Text('Employee')),
                            DataColumn(label: Text('Date')),
                            DataColumn(label: Text('Client')),
                            DataColumn(label: Text('Amount')),
                            DataColumn(label: Text('Description')),
                            DataColumn(label: Text('Source')),
                            DataColumn(label: Text('Proof')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Admin Remark')),
                            DataColumn(label: Text('Action')),
                          ],
                          rows: docs.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final employeeId =
                                data['employeeId']?.toString() ?? '';
                            final name = data['employeeName']?.toString() ??
                                employees[employeeId] ??
                                'Unknown';
                            final dateStr = data['date']?.toString() ?? '-';
                            final claimDate = DateTime.tryParse(dateStr);
                            final client =
                                data['clientName']?.toString() ?? '-';
                            final amount =
                                (data['amount'] as num?)?.toDouble() ?? 0;
                            final description =
                                data['description']?.toString() ?? '-';
                            final claimStatus =
                                (data['status'] ?? 'pending').toString();
                            final adminRemark =
                                data['adminRemark']?.toString() ?? '';
                            final proofUrl =
                                data['proofUrl']?.toString() ?? '';
                            final source =
                                data['source']?.toString() ?? 'manual';
                            final isPending =
                                claimStatus.toLowerCase() == 'pending';

                            return DataRow(
                              cells: [
                                DataCell(Text(name)),
                                DataCell(
                                  Text(
                                    claimDate != null
                                        ? DateFormat('dd MMM yyyy')
                                            .format(claimDate)
                                        : dateStr,
                                  ),
                                ),
                                DataCell(Text(client)),
                                DataCell(Text(_currency.format(amount))),
                                DataCell(
                                  InkWell(
                                    onTap: () => _showTextDialog(
                                      'Description',
                                      description,
                                    ),
                                    child: SizedBox(
                                      width: 160,
                                      child: Text(
                                        description,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    source == 'excel' ? 'Excel' : 'Manual',
                                  ),
                                ),
                                DataCell(
                                  proofUrl.isNotEmpty
                                      ? TextButton.icon(
                                          onPressed: () => _openProof(proofUrl),
                                          icon: const Icon(Icons.attachment,
                                              size: 18),
                                          label: const Text('View'),
                                        )
                                      : const Text('-'),
                                ),
                                DataCell(
                                  Text(
                                    formatStatusLabel(claimStatus),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: _statusColor(claimStatus),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  InkWell(
                                    onTap: adminRemark.isNotEmpty
                                        ? () => _showTextDialog(
                                              'Admin Remark',
                                              adminRemark,
                                            )
                                        : null,
                                    child: SizedBox(
                                      width: 140,
                                      child: Text(
                                        adminRemark.isNotEmpty
                                            ? adminRemark
                                            : '-',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  isPending
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                Icons.check,
                                                color: Colors.green,
                                              ),
                                              tooltip: 'Approve',
                                              onPressed: () =>
                                                  _handleApprove(doc.id),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.close,
                                                color: Colors.red,
                                              ),
                                              tooltip: 'Reject',
                                              onPressed: () =>
                                                  _handleReject(doc.id),
                                            ),
                                          ],
                                        )
                                      : const Text('-'),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OPE Claims'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Approved'),
            Tab(text: 'Rejected'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildClaimList('pending'),
                _buildClaimList('approved'),
                _buildClaimList('rejected'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

class SearchableEmployeeDropdown extends StatelessWidget {
  final String? value;
  final Map<String, String> employees;
  final ValueChanged<String?> onChanged;
  final String hint;
  final String? labelText;
  final bool showClearOption;
  final String clearOptionLabel;
  final String? fixedOptionValue;
  final String? fixedOptionLabel;

  const SearchableEmployeeDropdown({
    super.key,
    required this.value,
    required this.employees,
    required this.onChanged,
    this.hint = 'Select Employee',
    this.labelText,
    this.showClearOption = true,
    this.clearOptionLabel = 'All Employees',
    this.fixedOptionValue,
    this.fixedOptionLabel,
  });

  Future<void> _openSearchDialog(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _EmployeeSearchDialog(
        employees: employees,
        selectedId: value,
        showClearOption: showClearOption,
        clearOptionLabel: clearOptionLabel,
        fixedOptionValue: fixedOptionValue,
        fixedOptionLabel: fixedOptionLabel,
      ),
    );

    if (result == null) return;
    onChanged(result.isEmpty ? null : result);
  }

  @override
  Widget build(BuildContext context) {
    final selectedName = value != null
        ? (value == fixedOptionValue
            ? fixedOptionLabel
            : employees[value])
        : null;

    return InkWell(
      onTap: () => _openSearchDialog(context),
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: labelText,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          selectedName ?? hint,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selectedName != null ? Colors.black : Colors.black54,
          ),
        ),
      ),
    );
  }
}

class _EmployeeSearchDialog extends StatefulWidget {
  final Map<String, String> employees;
  final String? selectedId;
  final bool showClearOption;
  final String clearOptionLabel;
  final String? fixedOptionValue;
  final String? fixedOptionLabel;

  const _EmployeeSearchDialog({
    required this.employees,
    required this.selectedId,
    required this.showClearOption,
    required this.clearOptionLabel,
    this.fixedOptionValue,
    this.fixedOptionLabel,
  });

  @override
  State<_EmployeeSearchDialog> createState() => _EmployeeSearchDialogState();
}

class _EmployeeSearchDialogState extends State<_EmployeeSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MapEntry<String, String>> get _filteredEmployees {
    final query = _query.trim().toLowerCase();
    final entries = widget.employees.entries.toList();
    if (query.isEmpty) return entries;
    return entries
        .where((entry) => entry.value.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEmployees;

    return AlertDialog(
      title: const Text('Select Employee'),
      content: SizedBox(
        width: 420,
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search employee...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty && !widget.showClearOption
                  ? const Center(child: Text('No employees found'))
                  : ListView(
                      children: [
                        if (widget.fixedOptionValue != null &&
                            widget.fixedOptionLabel != null)
                          ListTile(
                            title: Text(widget.fixedOptionLabel!),
                            leading: const Icon(Icons.groups_outlined),
                            selected: widget.selectedId == widget.fixedOptionValue,
                            onTap: () =>
                                Navigator.pop(context, widget.fixedOptionValue!),
                          ),
                        if (widget.showClearOption)
                          ListTile(
                            title: Text(widget.clearOptionLabel),
                            leading: const Icon(Icons.people_outline),
                            selected: widget.selectedId == null,
                            onTap: () => Navigator.pop(context, ''),
                          ),
                        ...filtered.map(
                          (entry) => ListTile(
                            title: Text(entry.value),
                            selected: entry.key == widget.selectedId,
                            onTap: () => Navigator.pop(context, entry.key),
                          ),
                        ),
                        if (filtered.isEmpty && widget.showClearOption)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: Text('No employees found')),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

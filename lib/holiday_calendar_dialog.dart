import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

class HolidayCalendarDialog extends StatefulWidget {
  const HolidayCalendarDialog({Key? key}) : super(key: key);

  @override
  _HolidayCalendarDialogState createState() => _HolidayCalendarDialogState();
}

class _HolidayCalendarDialogState extends State<HolidayCalendarDialog> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final TextEditingController _holidayNameController = TextEditingController();
  Map<DateTime, String> _holidays = {};
  bool _dataChanged = false;
  Map<DateTime, List<Map<String, dynamic>>> _leavesByDay = {};
  Map<String, String> _userNames = {};

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _loadHolidays();
    _loadLeaves();
  }
  Future<void> _loadUsers() async {
    final snapshot =
    await FirebaseFirestore.instance.collection('users').get();

    final Map<String, String> temp = {};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      temp[doc.id] = data['name'] ?? 'Unknown';
    }

    setState(() => _userNames = temp);
  }
  Future<void> _loadLeaves() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('leaves')
        .where('status', isEqualTo: 'Approved')
        .get();

    final Map<DateTime, List<Map<String, dynamic>>> temp = {};

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;

      final startTs = data['startDate'] as Timestamp;
      final endTs = data['endDate'] as Timestamp;

      DateTime start = DateTime(
        startTs.toDate().year,
        startTs.toDate().month,
        startTs.toDate().day,
      );

      DateTime end = DateTime(
        endTs.toDate().year,
        endTs.toDate().month,
        endTs.toDate().day,
      );

      DateTime current = start;

      while (!current.isAfter(end)) {
        temp.putIfAbsent(current, () => []);
        temp[current]!.add(data);
        current = current.add(const Duration(days: 1));
      }
    }
    setState(() => _leavesByDay = temp);
  }


  Future<void> _loadHolidays() async {
    final snapshot = await FirebaseFirestore.instance.collection('holidays').get();
    final loadedHolidays = <DateTime, String>{};
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final date = (data['date'] as Timestamp).toDate();
      loadedHolidays[DateTime(date.year, date.month, date.day)] = data['name'];
    }
    setState(() => _holidays = loadedHolidays);
  }

  Future<bool> _addHoliday(DateTime date, String name) async {
    final normalizedDate = DateTime(date.year, date.month, date.day);

    // Check if already exists
    final existing = await FirebaseFirestore.instance
        .collection('holidays')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(normalizedDate))
        .where('date', isLessThan: Timestamp.fromDate(normalizedDate.add(const Duration(days: 1))))
        .get();

    if (existing.docs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ This date is already marked as a holiday!"),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }

    await FirebaseFirestore.instance.collection('holidays').add({
      'date': normalizedDate,
      'name': name,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _loadHolidays();
    _dataChanged = true;
    return true; // ✅ Added successfully
  }



  Future<void> _deleteHoliday(DateTime date) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('holidays')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(date))
        .where('date', isLessThan: Timestamp.fromDate(date.add(const Duration(days: 1))))
        .get();

    for (var doc in snapshot.docs) {
      await doc.reference.delete();
    }
    await _loadHolidays();
    _dataChanged = true;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                  const Spacer(),
                  const Text(
                    "📅 Manage Holidays",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black54),
                    onPressed: () => Navigator.pop(context, _dataChanged),
                    tooltip: "Close",
                  ),
                  ],
                ),
                const Divider(thickness: 1, height: 20),

                const SizedBox(height: 10),
                TableCalendar(
                  firstDay: DateTime.utc(2020),
                  lastDay: DateTime.utc(2030),
                  focusedDay: _focusedDay,

                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),

                  holidayPredicate: (day) =>
                      _holidays.keys.any((h) => isSameDay(h, day)),

                  eventLoader: (day) {
                    final key = DateTime(day.year, day.month, day.day);
                    return _leavesByDay[key] ?? [];
                  },

                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                      _holidayNameController.text =
                          _holidays[selectedDay] ?? '';
                    });
                  },

                  calendarBuilders: CalendarBuilders(
                    markerBuilder: (context, day, events) {
                      if (events.isEmpty) return null;

                      return Tooltip(
                        message: events.map((e) {
                          final leave = e as Map<String, dynamic>;
                          final uid = leave['userId'];
                          final name = _userNames[uid] ?? 'Unknown';
                          final type = leave['type'] ?? 'Leave';

                          return "👤 $name\n📝 $type";
                        }).join("\n\n"),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            events.length.clamp(1, 3),
                                (_) => Container(
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: Colors.yellow[900],
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  calendarStyle: CalendarStyle(
                    isTodayHighlighted: true,
                    holidayTextStyle: const TextStyle(color: Colors.green),
                    holidayDecoration: const BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: const BoxDecoration(
                      color: Colors.blueAccent,
                      shape: BoxShape.circle,
                    ),
                  ),

                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                  ),
                ),

                const SizedBox(height: 15),
                if (_selectedDay != null) ...[
                  Text(
                    "Selected: ${DateFormat('dd MMM yyyy').format(_selectedDay!)}",
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _holidayNameController,
                    decoration: const InputDecoration(
                      labelText: "Holiday Name",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          if (_holidayNameController.text.trim().isEmpty) return;

                          bool added = await _addHoliday(
                            _selectedDay!,
                            _holidayNameController.text.trim(),
                          );

                          if (added) {
                            _holidayNameController.clear();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("✅ Holiday added successfully!")),
                            );
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text("Add"),
                      ),
                      /*ElevatedButton.icon(
                        onPressed: () async {
                          await _deleteHoliday(_selectedDay!);
                          _holidayNameController.clear();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("🗑️ Holiday removed")),
                          );
                        },
                        icon: const Icon(Icons.delete),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                        ),
                        label: const Text("Delete"),
                      ),*/
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                const Divider(),
                const Text(
                  "Existing Holidays",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 5),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _holidays.length,
                  itemBuilder: (context, index) {
                    final entry = _holidays.entries.elementAt(index);
                    final date = entry.key;
                    final name = entry.value;
                    return ListTile(
                      dense: true,
                      title: Text(name),
                      subtitle: Text(DateFormat('dd MMM yyyy').format(date)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () async {
                          await _deleteHoliday(date);
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),

              ],
            ),
          ),
        ),
      ),
    );
  }
}

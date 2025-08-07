import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'advanced_report_screen.dart';

class AttendanceReportScreen extends StatefulWidget {
  final Map<String, String> userInfo;
  final String role;

  const AttendanceReportScreen({
    Key? key,
    required this.userInfo,
    required this.role,
  }) : super(key: key);

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  String? _selectedClassId;
  DateTime? _selectedDate;
  List<QueryDocumentSnapshot>? _classes;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _fetchClasses();
  }

  Future<void> _fetchClasses() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('classes')
        .where('school_id', isEqualTo: widget.userInfo['school_id'])
        .get();
    setState(() {
      _classes = snapshot.docs;
    });
  }

  Future<List<QueryDocumentSnapshot>> _fetchAttendanceRecords() async {
    Query query = FirebaseFirestore.instance.collection('attendances');
    if (_selectedClassId != null && _selectedClassId!.isNotEmpty) {
      query = query.where('class_id', isEqualTo: _selectedClassId);
    }
    if (_selectedDate != null) {
      final start = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
      final end = start.add(const Duration(days: 1));
      query = query.where('date', isGreaterThanOrEqualTo: start).where('date', isLessThan: end);
    }
    final snapshot = await query.get();
    return snapshot.docs;
  }

  Future<void> _exportToCSV(List<QueryDocumentSnapshot> records) async {
    setState(() => _isExporting = true);
    List<List<String>> rows = [
      ['Tanggal', 'Kelas', 'Guru', 'Nama Siswa', 'Status'],
    ];
    for (final doc in records) {
      final data = doc.data() as Map<String, dynamic>;
      final date = (data['date'] as Timestamp?)?.toDate();
      final dateStr = date != null ? '${date.day}/${date.month}/${date.year}' : '-';
      final classId = data['class_id'] ?? '-';
      final teacherId = data['teacher_id'] ?? '-';
      final attendance = data['attendance'] as Map?;
      // Fetch class and teacher info
      final classDoc = await FirebaseFirestore.instance.collection('classes').doc(classId).get();
      final kelas = classDoc.exists ? '${classDoc['grade'] ?? ''}${classDoc['class_name'] ?? ''}' : classId;
      final teacherQuery = await FirebaseFirestore.instance.collection('teachers').where('nuptk', isEqualTo: teacherId).limit(1).get();
      final guru = teacherQuery.docs.isNotEmpty ? teacherQuery.docs.first['name'] ?? teacherId : teacherId;
      if (attendance != null) {
        for (final entry in attendance.entries) {
          final studentId = entry.key;
          final status = entry.value;
          // Fetch student name
          final studentDoc = await FirebaseFirestore.instance.collection('students').doc(studentId).get();
          final studentName = studentDoc.exists ? studentDoc['name'] ?? studentId : studentId;
          rows.add([dateStr, kelas, guru, studentName, status]);
        }
      }
    }
    String csv = const ListToCsvConverter().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/laporan_presensi.csv');
    await file.writeAsString(csv);
    setState(() => _isExporting = false);
    await Share.shareXFiles([XFile(file.path)], text: 'Laporan Presensi');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Presensi'),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AdvancedReportScreen(
                    userInfo: widget.userInfo,
                    role: widget.role,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.analytics, color: Colors.white),
            label: const Text('Laporan Lanjutan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _selectedClassId,
                    items: [const DropdownMenuItem(value: '', child: Text('Semua Kelas'))] +
                        (_classes ?? []).map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final label = '${data['grade'] ?? ''}${data['class_name'] ?? ''}';
                          return DropdownMenuItem(value: doc.id, child: Text(label));
                        }).toList(),
                    onChanged: (v) => setState(() => _selectedClassId = v == '' ? null : v),
                    decoration: const InputDecoration(labelText: 'Kelas'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => _selectedDate = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Tanggal'),
                      child: Row(
                        children: [
                          Text(_selectedDate == null
                              ? 'Semua Tanggal'
                              : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'),
                          const Spacer(),
                          const Icon(Icons.calendar_today, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Reset',
                  onPressed: () => setState(() {
                    _selectedClassId = null;
                    _selectedDate = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<QueryDocumentSnapshot>>(
                future: _fetchAttendanceRecords(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text('Tidak ada data presensi.'));
                  }
                  final records = snapshot.data!;
                  // Simple analytics: count hadir, sakit, izin, alfa
                  int hadir = 0, sakit = 0, izin = 0, alfa = 0;
                  for (final doc in records) {
                    final data = doc.data() as Map<String, dynamic>;
                    final attendance = data['attendance'] as Map?;
                    if (attendance != null) {
                      for (final status in attendance.values) {
                        if (status == 'hadir') hadir++;
                        if (status == 'sakit') sakit++;
                        if (status == 'izin') izin++;
                        if (status == 'alfa') alfa++;
                      }
                    }
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildSummary('Hadir', hadir, Colors.green),
                              _buildSummary('Sakit', sakit, Colors.orange),
                              _buildSummary('Izin', izin, Colors.blue),
                              _buildSummary('Alfa', alfa, Colors.red),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: records.length,
                          itemBuilder: (context, index) {
                            final data = records[index].data() as Map<String, dynamic>;
                            final date = (data['date'] as Timestamp?)?.toDate();
                            final dateStr = date != null ? '${date.day}/${date.month}/${date.year}' : '-';
                            final classId = data['class_id'] ?? '-';
                            final teacherId = data['teacher_id'] ?? '-';
                            return ListTile(
                              title: Text('Tanggal: $dateStr'),
                              subtitle: Text('Kelas: $classId\nGuru: $teacherId'),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: _isExporting ? null : () async {
                            final records = await _fetchAttendanceRecords();
                            await _exportToCSV(records);
                          },
                          icon: _isExporting
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.download),
                          label: const Text('Export ke CSV'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(String label, int count, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text('$count', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
} 
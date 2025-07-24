import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'attendance_detail_screen.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  final Map<String, String> userInfo;
  final String role;
  const AttendanceHistoryScreen({Key? key, required this.userInfo, required this.role}) : super(key: key);

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  String _search = '';
  Set<String> _statusFilter = {};

  void _showFilterDialog() async {
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) {
        final tempFilter = Set<String>.from(_statusFilter);
        return AlertDialog(
          title: const Text('Filter Status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                value: tempFilter.contains('hadir'),
                onChanged: (v) => setState(() => v! ? tempFilter.add('hadir') : tempFilter.remove('hadir')),
                title: const Text('Hadir'),
              ),
              CheckboxListTile(
                value: tempFilter.contains('sakit'),
                onChanged: (v) => setState(() => v! ? tempFilter.add('sakit') : tempFilter.remove('sakit')),
                title: const Text('Sakit'),
              ),
              CheckboxListTile(
                value: tempFilter.contains('izin'),
                onChanged: (v) => setState(() => v! ? tempFilter.add('izin') : tempFilter.remove('izin')),
                title: const Text('Izin'),
              ),
              CheckboxListTile(
                value: tempFilter.contains('alfa'),
                onChanged: (v) => setState(() => v! ? tempFilter.add('alfa') : tempFilter.remove('alfa')),
                title: const Text('Alfa'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, _statusFilter), child: const Text('Batal')),
            TextButton(onPressed: () => Navigator.pop(context, tempFilter), child: const Text('Terapkan')),
          ],
        );
      },
    );
    if (result != null) {
      setState(() => _statusFilter = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    Query attendanceQuery = FirebaseFirestore.instance.collection('attendances').orderBy('date', descending: true);
    if (widget.role != 'admin') {
      attendanceQuery = attendanceQuery.where('teacher_id', isEqualTo: widget.userInfo['nuptk']);
      print(attendanceQuery);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Presensi'),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Cari kelas, guru, atau tanggal...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    onChanged: (value) => setState(() => _search = value.trim().toLowerCase()),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  tooltip: 'Filter',
                  onPressed: _showFilterDialog,
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: attendanceQuery.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('Tidak ada data presensi.'));
                }
                final attendances = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: attendances.length,
                  itemBuilder: (context, index) {
                    final doc = attendances[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final classId = data['class_id'] ?? '-';
                    final teacherId = data['teacher_id'] ?? '-';
                    final date = (data['date'] as Timestamp?)?.toDate();
                    final dateStr = date != null ? '${date.day}/${date.month}/${date.year}' : '-';
                    final summary = _attendanceSummary(data['attendance'] as Map?);
                    return FutureBuilder<Map<String, String>>(
                      future: _getClassAndTeacherInfo(classId, teacherId),
                      builder: (context, snapshot) {
                        final kelas = snapshot.data?['kelas'] ?? classId;
                        final guru = snapshot.data?['guru'] ?? teacherId;
                        // Search filter
                        final searchText = '$kelas $guru $dateStr $summary'.toLowerCase();
                        if (_search.isNotEmpty && !searchText.contains(_search)) return const SizedBox.shrink();
                        // Status filter
                        if (_statusFilter.isNotEmpty) {
                          final attendance = data['attendance'] as Map?;
                          if (attendance == null || !_statusFilter.any((status) => attendance.values.contains(status))) {
                            return const SizedBox.shrink();
                          }
                        }
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: ListTile(
                            title: Text('Kelas: $kelas'),
                            subtitle: Text('Tanggal: $dateStr\nGuru: $guru\n$summary'),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AttendanceDetailScreen(
                                    attendanceData: data,
                                    attendanceId: doc.id,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
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

  String _attendanceSummary(Map? attendance) {
    if (attendance == null) return '';
    final counts = <String, int>{'hadir': 0, 'sakit': 0, 'izin': 0, 'alfa': 0};
    attendance.forEach((_, status) {
      if (counts.containsKey(status)) counts[status] = counts[status]! + 1;
    });
    return 'Hadir: ${counts['hadir']}, Sakit: ${counts['sakit']}, Izin: ${counts['izin']}, Alfa: ${counts['alfa']}';
  }

  Future<Map<String, String>> _getClassAndTeacherInfo(String classId, String teacherId) async {
    String kelas = classId;
    String guru = teacherId;
    try {
      // Get class info
      final classDoc = await FirebaseFirestore.instance.collection('classes').doc(classId).get();
      if (classDoc.exists) {
        final classData = classDoc.data() as Map<String, dynamic>;
        final grade = classData['grade'] ?? '';
        final className = classData['class_name'] ?? '';
        kelas = '$grade$className';
      }
      // Get teacher info
      final teacherQuery = await FirebaseFirestore.instance.collection('teachers').where('nuptk', isEqualTo: teacherId).limit(1).get();
      if (teacherQuery.docs.isNotEmpty) {
        final teacherData = teacherQuery.docs.first.data() as Map<String, dynamic>;
        guru = teacherData['name'] ?? teacherId;
      }
    } catch (_) {}
    return {'kelas': kelas, 'guru': guru};
  }
} 
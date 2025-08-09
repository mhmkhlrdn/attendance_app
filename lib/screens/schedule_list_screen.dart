import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'create_schedule_screen.dart';

class ScheduleListScreen extends StatefulWidget {
  final String role;
  final Map<String, String> userInfo;
  const ScheduleListScreen({Key? key, required this.role, required this.userInfo}) : super(key: key);

  @override
  State<ScheduleListScreen> createState() => _ScheduleListScreenState();
}

class _ScheduleListScreenState extends State<ScheduleListScreen> {
  String _search = '';
  String? _dayFilter;
  String? _typeFilter;

  Future<String> _resolveClassName(String? classId) async {
    if (classId == null || classId.isEmpty) return '-';
    try {
      final doc = await FirebaseFirestore.instance.collection('classes').doc(classId).get();
      if (!doc.exists) return classId;
      final data = doc.data() as Map<String, dynamic>;
      final grade = (data['grade'] ?? '').toString();
      final className = (data['class_name'] ?? '').toString();
      if (grade.isEmpty && className.isEmpty) return classId;
      return [grade, className].where((p) => p.isNotEmpty).join(' ');
    } catch (_) {
      return classId;
    }
  }

  void _showFilterDialog() async {
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) {
        String? tempDayFilter = _dayFilter;
        String? tempTypeFilter = _typeFilter;
        return AlertDialog(
          title: const Text('Filter Jadwal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: tempTypeFilter,
                items: const [
                  DropdownMenuItem(value: null, child: Text('Semua Jenis')),
                  DropdownMenuItem(value: 'daily_morning', child: Text('Presensi Pagi Harian')),
                  DropdownMenuItem(value: 'subject_specific', child: Text('Mata Pelajaran Spesifik')),
                ],
                onChanged: (v) => tempTypeFilter = v,
                decoration: const InputDecoration(labelText: 'Jenis Jadwal'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: tempDayFilter,
                items: const [
                  DropdownMenuItem(value: null, child: Text('Semua Hari')),
                  DropdownMenuItem(value: 'Senin', child: Text('Senin')),
                  DropdownMenuItem(value: 'Selasa', child: Text('Selasa')),
                  DropdownMenuItem(value: 'Rabu', child: Text('Rabu')),
                  DropdownMenuItem(value: 'Kamis', child: Text('Kamis')),
                  DropdownMenuItem(value: 'Jumat', child: Text('Jumat')),
                  DropdownMenuItem(value: 'Sabtu', child: Text('Sabtu')),
                  DropdownMenuItem(value: 'Minggu', child: Text('Minggu')),
                ],
                onChanged: (v) => tempDayFilter = v,
                decoration: const InputDecoration(labelText: 'Hari'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, {'day': _dayFilter, 'type': _typeFilter}),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, {'day': tempDayFilter, 'type': tempTypeFilter}),
              child: const Text('Terapkan'),
            ),
          ],
        );
      },
    );
    if (result != null) {
      setState(() {
        _dayFilter = result['day'];
        _typeFilter = result['type'];
      });
    }
  }

  Future<void> _deleteSchedule(String scheduleId) async {
    try {
      await FirebaseFirestore.instance.collection('schedules').doc(scheduleId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Jadwal berhasil dihapus')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus jadwal: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance.collection('schedules');
    if (widget.role == 'guru') {
      query = query.where('teacher_id', isEqualTo: widget.userInfo['nuptk']);
    } else if (widget.role == 'admin') {
      query = query.where('school_id', isEqualTo: widget.userInfo['school_id']);
    }
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Jadwal'),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Cari mata pelajaran, kelas, atau waktu...',
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
              stream: query.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('Tidak ada data jadwal.'));
                }
                final schedules = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final matchesSearch = _search.isEmpty ||
                    (data['subject'] ?? '').toString().toLowerCase().contains(_search) ||
                    (data['class_id'] ?? '').toString().toLowerCase().contains(_search) ||
                    (data['time'] ?? '').toString().toLowerCase().contains(_search);
                  
                  // Filter by schedule type
                  final scheduleType = data['schedule_type'] ?? 'subject_specific';
                  final matchesTypeFilter = _typeFilter == null || scheduleType == _typeFilter;
                  
                  // Filter by day (only for subject-specific schedules)
                  bool matchesDayFilter = true;
                  if (_dayFilter != null && scheduleType == 'subject_specific') {
                    final dayOfWeek = data['day_of_week'];
                    matchesDayFilter = dayOfWeek == _dayFilter;
                  }
                  
                  return matchesSearch && matchesTypeFilter && matchesDayFilter;
                }).toList();
                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: schedules.length,
                  itemBuilder: (context, index) {
                    final scheduleDoc = schedules[index];
                    final data = scheduleDoc.data() as Map<String, dynamic>;
                    final scheduleType = data['schedule_type'] ?? 'subject_specific';
                    
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        leading: CircleAvatar(
                          backgroundColor: scheduleType == 'daily_morning' 
                            ? Colors.green[100] 
                            : Colors.amber[100],
                          child: Icon(
                            scheduleType == 'daily_morning' 
                              ? Icons.wb_sunny 
                              : Icons.schedule_outlined,
                            color: scheduleType == 'daily_morning' 
                              ? Colors.green[800] 
                              : Colors.amber[800],
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                data['subject'] ?? '',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: scheduleType == 'daily_morning' 
                                  ? Colors.green[100] 
                                  : Colors.blue[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                scheduleType == 'daily_morning' 
                                  ? 'Pagi Harian' 
                                  : 'Mata Pelajaran',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheduleType == 'daily_morning' 
                                    ? Colors.green[800] 
                                    : Colors.blue[800],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FutureBuilder<String>(
                              future: _resolveClassName(data['class_id'] as String?),
                              builder: (context, snapshot) {
                                final display = snapshot.connectionState == ConnectionState.done
                                    ? (snapshot.data ?? '-')
                                    : 'Memuat...';
                                return Text('Kelas: $display');
                              },
                            ),
                            Text('Jadwal: ${data['time'] ?? ''}'),
                            if (scheduleType == 'subject_specific' && data['day_of_week'] != null)
                              Text('Hari: ${data['day_of_week']}'),
                          ],
                        ),
                        trailing: widget.role == 'admin' ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => CreateScheduleScreen(
                                      schedule: {
                                        'id': scheduleDoc.id,
                                        ...data,
                                      },
                                      userInfo: widget.userInfo,
                                    ),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Konfirmasi Hapus'),
                                    content: Text('Yakin ingin menghapus jadwal "${data['subject']}"?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Batal'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _deleteSchedule(scheduleDoc.id);
                                        },
                                        child: const Text('Hapus', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ) : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: widget.role == 'admin'
          ? Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CreateScheduleScreen(userInfo: widget.userInfo),
                      ),
                    );
                  },
                  child: const Icon(Icons.add),
                  tooltip: 'Tambah Jadwal',
                ),
                const SizedBox(height: 8),
              ],
            )
          : null,
    );
  }
}

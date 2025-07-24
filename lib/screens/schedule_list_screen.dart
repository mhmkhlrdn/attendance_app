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

  void _showFilterDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        String? tempFilter = _dayFilter;
        return AlertDialog(
          title: const Text('Filter Hari'),
          content: DropdownButtonFormField<String>(
            isExpanded: true,
            value: tempFilter,
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
            onChanged: (v) => tempFilter = v,
            decoration: const InputDecoration(labelText: 'Hari'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, _dayFilter), child: const Text('Batal')),
            TextButton(onPressed: () => Navigator.pop(context, tempFilter), child: const Text('Terapkan')),
          ],
        );
      },
    );
    if (result != null) setState(() => _dayFilter = result);
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
                  final day = (data['time'] ?? '').toString().split(' ').first;
                  final matchesFilter = _dayFilter == null || _dayFilter == '' || day == _dayFilter;
                  return matchesSearch && matchesFilter;
                }).toList();
                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: schedules.length,
                  itemBuilder: (context, index) {
                    final scheduleDoc = schedules[index];
                    final data = scheduleDoc.data() as Map<String, dynamic>;
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        leading: CircleAvatar(
                          backgroundColor: Colors.amber[100],
                          child: Icon(Icons.schedule_outlined, color: Colors.amber[800]),
                        ),
                        title: Text(data['subject'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Kelas: ${data['class_id'] ?? ''}\nJadwal: ${data['time'] ?? ''}'),
                        trailing: widget.role == 'admin' ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => CreateScheduleScreen(schedule: {
                                      'id': scheduleDoc.id,
                                      ...data,
                                    }),
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
          ? FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CreateScheduleScreen(),
            ),
          );
        },
        child: const Icon(Icons.add),
        tooltip: 'Tambah Jadwal',
      )
          : null,
    );
  }
}

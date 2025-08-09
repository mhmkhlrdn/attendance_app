import 'package:cloud_firestore/cloud_firestore.dart';
 
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'class_students_screen.dart';
import 'create_class_screen.dart';

class ClassListScreen extends StatefulWidget {
  final String role;
  final Map<String, String>? userInfo;
  const ClassListScreen({Key? key, required this.role, this.userInfo}) : super(key: key);

  @override
  State<ClassListScreen> createState() => _ClassListScreenState();
}

class _ClassListScreenState extends State<ClassListScreen> {
  String _search = '';
  String? _yearFilter;
  String? _latestYearId;
  bool _loadingYear = true;

  @override
  void initState() {
    super.initState();
    _loadLatestYear();
  }

  Future<void> _loadLatestYear() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('school_years')
          .orderBy('start_date', descending: true)
          .limit(1)
          .get();
      setState(() {
        _latestYearId = snapshot.docs.isNotEmpty ? snapshot.docs.first.id : null;
        _loadingYear = false;
      });
    } catch (e) {
      setState(() {
        _latestYearId = null;
        _loadingYear = false;
      });
    }
  }
  

  void _showFilterDialog(List<String> yearOptions) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        String? tempFilter = _yearFilter;
        return AlertDialog(
          title: const Text('Filter Tahun'),
          content: DropdownButtonFormField<String>(
            isExpanded: true,
            value: tempFilter ?? '',
            items: [const DropdownMenuItem(value: '', child: Text('Semua Tahun'))] +
                yearOptions.map((year) => DropdownMenuItem(value: year, child: Text(year))).toList()
                  ..sort((a, b) {
                    if (a.value == '') return -1;
                    if (b.value == '') return 1;
                    return ((a.child as Text).data ?? '').compareTo((b.child as Text).data ?? '');
                  }),
            onChanged: (v) => tempFilter = v,
            decoration: const InputDecoration(labelText: 'Tahun'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, _yearFilter), child: const Text('Batal')),
            TextButton(onPressed: () => Navigator.pop(context, tempFilter), child: const Text('Terapkan')),
          ],
        );
      },
    );
    if (result != null) setState(() => _yearFilter = result);
  }

  Future<void> _deleteClass(String classId) async {
    try {
      await FirebaseFirestore.instance.collection('classes').doc(classId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kelas berhasil dihapus')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus kelas: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Kelas'),
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
                      hintText: 'Cari kelas, tingkat, atau tahun...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    onChanged: (value) => setState(() => _search = value.trim().toLowerCase()),
                  ),
                ),
                const SizedBox(width: 8),
                Builder(
                  builder: (context) {
                    if (_loadingYear) {
                      return const SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      );
                    }
                    Query classesQuery = FirebaseFirestore.instance.collection('classes');
                    if (widget.userInfo != null) {
                      classesQuery = classesQuery.where('school_id', isEqualTo: widget.userInfo!['school_id']);
                    }
                    if (_latestYearId != null) {
                      classesQuery = classesQuery.where('year_id', isEqualTo: _latestYearId);
                    }
                    final classes = classesQuery.snapshots();
            return StreamBuilder<QuerySnapshot>(
              stream: classes,
              builder: (context, snapshot) {
                final yearSet = <String>{};
                if (snapshot.hasData) {
                  for (var doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final year = data['year']?.toString() ?? data['year_id']?.toString() ?? '';
                    if (year.isNotEmpty) yearSet.add(year);
                  }
                }
                return IconButton(
                  icon: const Icon(Icons.filter_list),
                  tooltip: 'Filter',
                  onPressed: () => _showFilterDialog(yearSet.toList()),
                );
              },
            );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _loadingYear
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<QuerySnapshot>(
              stream: (() {
                Query query = FirebaseFirestore.instance.collection('classes');
                if (widget.userInfo != null) {
                  query = query.where('school_id', isEqualTo: widget.userInfo!['school_id']);
                }
                if (_latestYearId != null) {
                  query = query.where('year_id', isEqualTo: _latestYearId);
                }
                return query.snapshots();
              })(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox, size: 64, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('Tidak ada data kelas.', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }
                final classes = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final matchesSearch = _search.isEmpty ||
                    (data['grade'] ?? '').toString().toLowerCase().contains(_search) ||
                    (data['class_name'] ?? '').toString().toLowerCase().contains(_search) ||
                    (data['year']?.toString() ?? '').toLowerCase().contains(_search);
                  final year = data['year']?.toString() ?? data['year_id']?.toString() ?? '';
                  final matchesFilter = _yearFilter == null || _yearFilter == '' || year == _yearFilter;
                  return matchesSearch && matchesFilter;
                }).toList();
                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: classes.length,
                  itemBuilder: (context, index) {
                    final classDoc = classes[index];
                    final data = classDoc.data() as Map<String, dynamic>;
                    final className = data['class_name'] ?? '';
                    final grade = data['grade'] ?? '';
                    final year = data['year_id']?.toString() ?? '';
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        leading: CircleAvatar(
                          backgroundColor: Colors.purple[100],
                          child: Icon(Icons.class_outlined, color: Colors.purple[800]),
                        ),
                        title: Text('Kelas $grade$className ($year)', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Siswa: ${(data['students'] as List?)?.length ?? 0}'),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ClassStudentsScreen(
                                className: className,
                                grade: grade,
                                year: data['year_id'],
                                studentIds: List<String>.from(data['students'] ?? []),
                              ),
                            ),
                          );
                        },
                        trailing: widget.role == 'admin' ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => CreateClassScreen(
                                      classData: {
                                        'id': classDoc.id,
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
                                    content: Text('Yakin ingin menghapus kelas $grade$className?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Batal'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _deleteClass(classDoc.id);
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
              builder: (context) => CreateClassScreen(userInfo: widget.userInfo),
            ),
          );
        },
        child: const Icon(Icons.add),
        tooltip: 'Tambah Kelas',
      )
          : null,
    );
  }
}

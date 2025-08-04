import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'create_teacher_screen.dart';

class TeacherListScreen extends StatefulWidget {
  final String role;
  final Map<String, String>? userInfo;
  const TeacherListScreen({Key? key, required this.role, this.userInfo}) : super(key: key);

  @override
  State<TeacherListScreen> createState() => _TeacherListScreenState();
}

class _TeacherListScreenState extends State<TeacherListScreen> {
  String _search = '';
  String? _roleFilter;

  Future<void> _deleteTeacher(String teacherId) async {
    try {
      await FirebaseFirestore.instance.collection('teachers').doc(teacherId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Guru berhasil dihapus')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus guru: $e')),
        );
      }
    }
  }

  void _showFilterDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        String? tempFilter = _roleFilter;
        return AlertDialog(
          title: const Text('Filter Peran'),
          content: DropdownButtonFormField<String>(
            isExpanded: true,
            value: tempFilter,
            items: const [
              DropdownMenuItem(value: null, child: Text('Semua Peran')),
              DropdownMenuItem(value: 'guru', child: Text('Guru')),
              DropdownMenuItem(value: 'admin', child: Text('Admin')),
            ],
            onChanged: (v) => tempFilter = v,
            decoration: const InputDecoration(labelText: 'Peran'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, _roleFilter), child: const Text('Batal')),
            TextButton(onPressed: () => Navigator.pop(context, tempFilter), child: const Text('Terapkan')),
          ],
        );
      },
    );
    if (result != null) setState(() => _roleFilter = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Guru'),
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
                      hintText: 'Cari nama guru...',
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
              stream: widget.userInfo != null 
                ? FirebaseFirestore.instance
                    .collection('teachers')
                    .where('school_id', isEqualTo: widget.userInfo!['school_id'])
                    .snapshots()
                : FirebaseFirestore.instance.collection('teachers').snapshots(),
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
                        Text('Tidak ada data guru.', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }
                final teachers = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final matchesSearch = _search.isEmpty || (data['name'] ?? '').toString().toLowerCase().contains(_search);
                  final matchesFilter = _roleFilter == null || _roleFilter == '' || data['role'] == _roleFilter;
                  return matchesSearch && matchesFilter;
                }).toList();
                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: teachers.length,
                  itemBuilder: (context, index) {
                    final teacherDoc = teachers[index];
                    final data = teacherDoc.data() as Map<String, dynamic>;
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        leading: CircleAvatar(
                          backgroundColor: Colors.teal[100],
                          child: Icon(Icons.person_outline, color: Colors.teal[800]),
                        ),
                        title: Text(data['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('NUPTK: ${data['nuptk'] ?? ''}\nPeran: ${data['role'] ?? ''}'),
                        trailing: widget.role == 'admin' ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => CreateTeacherScreen(
                                      teacher: {
                                        'id': teacherDoc.id,
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
                                    content: Text('Yakin ingin menghapus guru "${data['name']}"?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Batal'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _deleteTeacher(teacherDoc.id);
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
              builder: (context) => CreateTeacherScreen(userInfo: widget.userInfo),
            ),
          );
        },
        child: const Icon(Icons.add),
        tooltip: 'Tambah Guru',
      )
          : null,
    );
  }
}

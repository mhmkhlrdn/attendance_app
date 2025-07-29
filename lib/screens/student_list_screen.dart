import 'package:attendance_app/screens/student_form_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'student_detail_screen.dart';
import '../services/student_helper_service.dart';

class StudentListScreen extends StatefulWidget {
  final String role;
  const StudentListScreen({Key? key, required this.role}) : super(key: key);

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  String _search = '';
  String? _classFilter;

  void _showFilterDialog(List<String> classOptions) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        String? tempFilter = _classFilter;
        return AlertDialog(
          title: const Text('Filter Kelas'),
          content: DropdownButtonFormField<String>(
            isExpanded: true,
            value: tempFilter ?? '',
            items: [const DropdownMenuItem(value: '', child: Text('Semua Kelas'))] +
                classOptions.map((kelas) => DropdownMenuItem(value: kelas, child: Text(kelas))).toList(),
            onChanged: (v) => tempFilter = v,
            decoration: const InputDecoration(labelText: 'Kelas'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, _classFilter), child: const Text('Batal')),
            TextButton(onPressed: () => Navigator.pop(context, tempFilter), child: const Text('Terapkan')),
          ],
        );
      },
    );
    if (result != null) setState(() => _classFilter = result);
  }

  Future<void> _deleteStudentAndRemoveFromClasses(String studentId) async {
    final firestore = FirebaseFirestore.instance;
    // 1. Find all classes containing this student
    final classesQuery = await firestore
        .collection('classes')
        .where('students', arrayContains: studentId)
        .get();
    // 2. Remove student from each class
    for (final doc in classesQuery.docs) {
      await doc.reference.update({
        'students': FieldValue.arrayRemove([studentId])
      });
    }
    // 3. Delete the student
    await firestore.collection('students').doc(studentId).delete();
  }

  String _getClassDisplay(Map<String, dynamic> studentData) {
    return StudentHelperService.getCurrentClassDisplay(studentData);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Siswa'),
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
                      hintText: 'Cari nama siswa...',
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
                    // Collect all class options from students
                    final students = FirebaseFirestore.instance.collection('students').snapshots();
                    return StreamBuilder<QuerySnapshot>(
                      stream: students,
                      builder: (context, snapshot) {
                        final kelasSet = <String>{};
                        if (snapshot.hasData) {
                          for (var doc in snapshot.data!.docs) {
                            final data = doc.data() as Map<String, dynamic>;
                            final enrollments = data['enrollments'] as List?;
                            if (enrollments != null && enrollments.isNotEmpty) {
                              final enrollment = enrollments.first as Map<String, dynamic>;
                              final grade = enrollment['grade'] ?? '';
                              final className = enrollment['class'] ?? '';
                              if (grade.isNotEmpty && className.isNotEmpty) {
                                kelasSet.add('$grade$className');
                              }
                            }
                          }
                        }
                        return IconButton(
                          icon: const Icon(Icons.filter_list),
                          tooltip: 'Filter',
                          onPressed: () => _showFilterDialog(kelasSet.toList()),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('students').snapshots(),
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
                        Text('Tidak ada data siswa.', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }
                final students = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final matchesSearch = _search.isEmpty || (data['name'] ?? '').toString().toLowerCase().contains(_search);
                  final enrollments = data['enrollments'] as List?;
                  String kelas = '';
                  if (enrollments != null && enrollments.isNotEmpty) {
                    final enrollment = enrollments.first as Map<String, dynamic>;
                    final grade = enrollment['grade'] ?? '';
                    final className = enrollment['class'] ?? '';
                    if (grade.isNotEmpty && className.isNotEmpty) {
                      kelas = '$grade$className';
                    }
                  }
                  final matchesFilter = _classFilter == null || _classFilter == '' || kelas == _classFilter;
                  return matchesSearch && matchesFilter;
                }).toList();
                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: students.length,
                  itemBuilder: (context, index) {
                    final student = students[index];
                    final data = student.data() as Map<String, dynamic>;
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue[100],
                          child: Icon(Icons.face_outlined, color: Colors.blue[800]),
                        ),
                        title: Text(data['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(_getClassDisplay(data)),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => StudentDetailScreen(studentId: student.id),
                            ),
                          );
                        },
                        trailing: widget.role == 'admin'
                            ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blueGrey),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => StudentFormScreen(
                                      student: {...data, 'id': student.id},
                                    ),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              onPressed: () async {
                                await _deleteStudentAndRemoveFromClasses(student.id);
                              },
                            ),
                          ],
                        )
                            : null,
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
              builder: (context) => const StudentFormScreen(),
            ),
          );
        },
        child: const Icon(Icons.add),
        tooltip: 'Tambah Siswa',
      )
          : null,
    );
  }
}

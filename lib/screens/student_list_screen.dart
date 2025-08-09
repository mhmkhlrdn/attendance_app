import 'package:attendance_app/screens/student_form_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'student_details_screen.dart';
import '../services/student_helper_service.dart';

class StudentListScreen extends StatefulWidget {
  final String role;
  final Map<String, String>? userInfo;
  const StudentListScreen({Key? key, required this.role, this.userInfo}) : super(key: key);

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
                classOptions.map((kelas) => DropdownMenuItem(value: kelas, child: Text(kelas))).toList()
                  ..sort((a, b) {
                    if (a.value == '') return -1;
                    if (b.value == '') return 1;
                    return ((a.child as Text).data ?? '').compareTo((b.child as Text).data ?? '');
                  }),
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

  Future<String> _getCurrentYear() async {
    try {
      final years = await FirebaseFirestore.instance
          .collection('school_years')
          .orderBy('start_date', descending: true)
          .limit(1)
          .get();
      
      if (years.docs.isNotEmpty) {
        final doc = years.docs.first;
        final data = doc.data();
        return (data['name'] ?? doc.id).toString();
      }
    } catch (e) {
      print('Error loading current year: $e');
    }
    return 'Tahun Ajaran Aktif';
  }

  IconData _getGenderIcon(String? gender) {
    switch (gender) {
      case 'Laki-laki':
        return Icons.male;
      case 'Perempuan':
        return Icons.female;
      default:
        return Icons.person_outline;
    }
  }

  Color _getGenderColor(String? gender) {
    switch (gender) {
      case 'Laki-laki':
        return Colors.blue[100]!;
      case 'Perempuan':
        return Colors.pink[100]!;
      default:
        return Colors.grey[100]!;
    }
  }

  Color _getGenderIconColor(String? gender) {
    switch (gender) {
      case 'Laki-laki':
        return Colors.blue[800]!;
      case 'Perempuan':
        return Colors.pink[800]!;
      default:
        return Colors.grey[600]!;
    }
  }

  String _getClassKey(Map<String, dynamic> studentData) {
    final currentEnrollment = StudentHelperService.getCurrentEnrollment(studentData);
    if (currentEnrollment != null) {
      final grade = currentEnrollment['grade'] ?? '';
      final className = currentEnrollment['class'] ?? '';
      if (grade.toString().isNotEmpty) {
        return '$grade$className';
      }
    }
    return '';
  }

  String _getClassDisplayName(String classKey) {
    return classKey.isEmpty ? 'Tanpa Kelas' : 'Kelas $classKey';
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
                    final students = FirebaseFirestore.instance
                        .collection('students')
                        .where('status', isEqualTo: 'active')
                        .snapshots();
                    return StreamBuilder<QuerySnapshot>(
                      stream: students,
                      builder: (context, snapshot) {
                        final kelasSet = <String>{};
                        if (snapshot.hasData) {
                          for (var doc in snapshot.data!.docs) {
                            final data = doc.data() as Map<String, dynamic>;
                            final classKey = _getClassKey(data);
                            kelasSet.add(classKey);
                          }
                        }
                        final kelasList = kelasSet.toList()..sort((a, b) => _getClassDisplayName(a).compareTo(_getClassDisplayName(b)));
                        return IconButton(
                          icon: const Icon(Icons.filter_list),
                          tooltip: 'Filter',
                          onPressed: () => _showFilterDialog(kelasList),
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
              stream: widget.userInfo != null 
                ? FirebaseFirestore.instance
                    .collection('students')
                    .where('school_id', isEqualTo: widget.userInfo!['school_id'])
                    .where('status', isEqualTo: 'active')
                    .snapshots()
                : FirebaseFirestore.instance
                    .collection('students')
                    .where('status', isEqualTo: 'active')
                    .snapshots(),
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
                // Group students by class
                final Map<String, List<QueryDocumentSnapshot>> classGroups = {};
                for (var doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  if (_search.isNotEmpty && !name.contains(_search)) continue;
                  final classKey = _getClassKey(data);
                  if (_classFilter != null && _classFilter != '' && classKey != _classFilter) continue;
                  if (!classGroups.containsKey(classKey)) classGroups[classKey] = [];
                  classGroups[classKey]!.add(doc);
                }
                final sortedClasses = classGroups.keys.toList()
                  ..sort((a, b) => _getClassDisplayName(a).compareTo(_getClassDisplayName(b)));
                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: sortedClasses.fold(0, (prev, k) => prev! + classGroups[k]!.length + 1),
                  itemBuilder: (context, index) {
                    int runningIndex = 0;
                    for (final classKey in sortedClasses) {
                      // Class header
                      if (index == runningIndex) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                          child: Text(
                            _getClassDisplayName(classKey),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal),
                          ),
                        );
                      }
                      runningIndex++;
                      // Students in this class, sorted alphabetically
                      final students = classGroups[classKey]!..sort((a, b) {
                        final nameA = ((a.data() as Map<String, dynamic>)['name'] ?? '').toString().toLowerCase();
                        final nameB = ((b.data() as Map<String, dynamic>)['name'] ?? '').toString().toLowerCase();
                        return nameA.compareTo(nameB);
                      });
                      for (var s = 0; s < students.length; s++) {
                        if (index == runningIndex) {
                          final student = students[s];
                          final data = student.data() as Map<String, dynamic>;
                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              leading: CircleAvatar(
                                backgroundColor: _getGenderColor(data['gender']),
                                child: Icon(_getGenderIcon(data['gender']), color: _getGenderIconColor(data['gender'])),
                              ),
                              title: Text(data['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(_getClassDisplay(data)),
                              onTap: () async {
                                final currentYear = await _getCurrentYear();
                                if (mounted) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => StudentDetailsScreen(
                                        studentId: student.id,
                                        userInfo: widget.userInfo ?? {},
                                        selectedYear: currentYear,
                                      ),
                                    ),
                                  );
                                }
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
                                            userInfo: widget.userInfo,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text('Konfirmasi Hapus'),
                                          content: Text('Yakin ingin menghapus siswa "${data['name'] ?? ''}"? Tindakan ini tidak dapat dibatalkan.'),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, false),
                                              child: const Text('Batal'),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, true),
                                              child: const Text('Hapus', style: TextStyle(color: Colors.red)),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await _deleteStudentAndRemoveFromClasses(student.id);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Siswa berhasil dihapus')),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                ],
                              )
                                  : null,
                            ),
                          );
                        }
                        runningIndex++;
                      }
                    }
                    return const SizedBox.shrink();
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
              builder: (context) => StudentFormScreen(userInfo: widget.userInfo),
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

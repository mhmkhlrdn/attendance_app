import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StudentFormScreen extends StatefulWidget {
  final Map<String, dynamic>? student; // Pass null for add, or student data for edit

  const StudentFormScreen({Key? key, this.student}) : super(key: key);

  @override
  State<StudentFormScreen> createState() => _StudentFormScreenState();
}

class _StudentFormScreenState extends State<StudentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _classController;
  String? _selectedYearId;
  String? _selectedGender;
  late TextEditingController _parentPhoneController;
  bool _isSaving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.student?['name'] ?? '');
    _classController = TextEditingController(
      text: widget.student != null && widget.student?['enrollments'] != null && (widget.student!['enrollments'] as List).isNotEmpty
        ? '${(widget.student!['enrollments'] as List).first['grade']}${(widget.student!['enrollments'] as List).first['class']}'
        : '',
    );
    _selectedYearId = widget.student != null && widget.student?['enrollments'] != null && (widget.student!['enrollments'] as List).isNotEmpty
        ? (widget.student!['enrollments'] as List).first['year_id']
        : null;
    _selectedGender = widget.student?['gender'];
    _parentPhoneController = TextEditingController(text: widget.student?['parent_phone'] ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _classController.dispose();
    // _yearController.dispose();
    _parentPhoneController.dispose();
    super.dispose();
  }

  Future<void> _saveStudent() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    String? selectedGrade;
    String? selectedClass;
    if (_classController.text.isNotEmpty) {
      // Parse format like "1B", "2A", "10A", etc.
      final text = _classController.text.trim();
      // Find the first non-digit character to separate grade and class
      int splitIndex = 0;
      for (int i = 0; i < text.length; i++) {
        if (!RegExp(r'[0-9]').hasMatch(text[i])) {
          splitIndex = i;
          break;
        }
      }
      if (splitIndex > 0) {
        selectedGrade = text.substring(0, splitIndex);
        selectedClass = text.substring(splitIndex);
      }
    }
    final studentData = {
      'name': _nameController.text.trim(),
      'gender': _selectedGender,
      'parent_phone': _parentPhoneController.text.trim(),
      'status': 'active',
      'enrollments': [
        {
          'grade': selectedGrade ?? '',
          'class': selectedClass ?? '',
          'year_id': _selectedYearId,
        }
      ],
    };
    try {
      // Duplicate check: name + phone
      final existing = await FirebaseFirestore.instance
        .collection('students')
        .where('name', isEqualTo: _nameController.text.trim())
        .where('parent_phone', isEqualTo: _parentPhoneController.text.trim())
        .get();
      if (existing.docs.isNotEmpty && (widget.student == null || widget.student!['id'] != existing.docs.first.id)) {
        setState(() {
          _isSaving = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Siswa dengan nama dan nomor HP ini sudah terdaftar!'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      String studentId;
      if (widget.student != null && widget.student!['id'] != null) {
        // Update existing student
        studentId = widget.student!['id'];
        await FirebaseFirestore.instance
            .collection('students')
            .doc(studentId)
            .update(studentData);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Siswa berhasil diperbarui!')),
          );
        }
      } else {
        // Create new student
        final docRef = await FirebaseFirestore.instance
            .collection('students')
            .add(studentData);
        studentId = docRef.id;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Siswa berhasil ditambahkan!')),
          );
        }
      }

      // Handle class enrollment changes
      if (selectedGrade != null && selectedClass != null && _selectedYearId != null) {
        // For editing: remove from old class if class changed
        if (widget.student != null && widget.student!['enrollments'] != null && (widget.student!['enrollments'] as List).isNotEmpty) {
          final oldEnrollment = (widget.student!['enrollments'] as List).first;
          final oldGrade = oldEnrollment['grade'];
          final oldClass = oldEnrollment['class'];
          final oldYearId = oldEnrollment['year_id'];
          
          // If class/grade/year changed, remove from old class
          if (oldGrade != selectedGrade || oldClass != selectedClass || oldYearId != _selectedYearId) {
            final oldClassQuery = await FirebaseFirestore.instance
                .collection('classes')
                .where('grade', isEqualTo: oldGrade)
                .where('class_name', isEqualTo: oldClass)
                .where('year_id', isEqualTo: oldYearId)
                .limit(1)
                .get();

            if (oldClassQuery.docs.isNotEmpty) {
              final oldClassDoc = oldClassQuery.docs.first;
              await oldClassDoc.reference.update({
                'students': FieldValue.arrayRemove([studentId])
              });
            }
          }
        }

        // Add to new class
        final classQuery = await FirebaseFirestore.instance
            .collection('classes')
            .where('grade', isEqualTo: selectedGrade)
            .where('class_name', isEqualTo: selectedClass)
            .where('year_id', isEqualTo: _selectedYearId)
            .limit(1)
            .get();

        if (classQuery.docs.isNotEmpty) {
          final classDoc = classQuery.docs.first;
          await classDoc.reference.update({
            'students': FieldValue.arrayUnion([studentId])
          });
        }
      }

      Navigator.pop(context);
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.student != null;
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Siswa' : 'Tambah Siswa'),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Nama Lengkap Siswa *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                    validator: (value) => value!.isEmpty ? 'Masukkan nama' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _selectedGender,
                    items: const [
                      DropdownMenuItem(value: 'Laki-laki', child: Text('Laki-laki')),
                      DropdownMenuItem(value: 'Perempuan', child: Text('Perempuan')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedGender = value;
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Jenis Kelamin *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.wc),
                    ),
                    validator: (value) => value == null || value.isEmpty ? 'Pilih jenis kelamin' : null,
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('classes').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final classes = snapshot.data!.docs;
                      final classOptions = classes.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final label = '${data['grade']}${data['class_name']}';
                        return DropdownMenuItem<String>(
                          value: label,
                          child: Text(label),
                        );
                      }).toList();
                      return DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _classController.text.isNotEmpty ? _classController.text : null,
                        items: classOptions,
                        onChanged: (value) {
                          setState(() {
                            _classController.text = value ?? '';
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Kelas *',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          prefixIcon: const Icon(Icons.class_outlined),
                        ),
                        validator: (value) => value == null || value.isEmpty ? 'Pilih kelas' : null,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('school_years').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final years = snapshot.data!.docs;
                      return DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _selectedYearId,
                        items: years.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return DropdownMenuItem<String>(
                            value: doc.id,
                            child: Text(data['name'] ?? doc.id),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedYearId = value;
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Tahun Ajaran *',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          prefixIcon: const Icon(Icons.calendar_today_outlined),
                        ),
                        validator: (value) => value == null ? 'Pilih tahun ajaran' : null,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _parentPhoneController,
                    decoration: InputDecoration(
                      labelText: 'No. HP Orang Tua *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.phone_outlined),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (value) => value!.isEmpty ? 'Masukkan no. HP' : null,
                  ),
                  const SizedBox(height: 24),
                  _isSaving
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveStudent,
                    icon: _isSaving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: Text(isEdit ? 'Perbarui Siswa' : 'Simpan Siswa'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      backgroundColor: Colors.teal,
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _message!.startsWith('Gagal') ? Colors.red : Colors.green,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> populateClassWithStudents({
  required String classDocId,
  required String className,
  required int year,
  required String grade,
}) async {
  final firestore = FirebaseFirestore.instance;

  // 1. Query students matching class and year
  final querySnapshot = await firestore
      .collection('students')
      .where('class', isEqualTo: className)
      .where('year', isEqualTo: year)
      .where('grade', isEqualTo: grade)
      .get();

  // 2. Extract student IDs
  final studentIds = querySnapshot.docs.map((doc) => doc.id).toList();

  // 3. Create or update the class document with the students array
  await firestore.collection('classes').doc(classDocId).set({
    'class_name': className,
    'year': year,
    'grade': grade,
    'students': studentIds,
  });
} 
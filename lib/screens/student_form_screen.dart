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
  late TextEditingController _yearController;
  late TextEditingController _fatherNameController;
  late TextEditingController _motherNameController;
  late TextEditingController _parentPhoneController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.student?['name'] ?? '');
    _classController = TextEditingController(
      text: widget.student != null && widget.student?['grade'] != null && widget.student?['class'] != null
        ? '${widget.student?['grade']} ${widget.student?['class']}'
        : '',
    );
    _yearController = TextEditingController(text: widget.student?['year']?.toString() ?? '');
    _fatherNameController = TextEditingController(text: widget.student?['father_name'] ?? '');
    _motherNameController = TextEditingController(text: widget.student?['mother_name'] ?? '');
    _parentPhoneController = TextEditingController(text: widget.student?['parent_phone'] ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _classController.dispose();
    _yearController.dispose();
    _fatherNameController.dispose();
    _motherNameController.dispose();
    _parentPhoneController.dispose();
    super.dispose();
  }

  Future<void> _saveStudent() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    String? selectedGrade;
    String? selectedClass;
    if (_classController.text.contains(' ')) {
      final parts = _classController.text.split(' ');
      selectedGrade = parts[0];
      selectedClass = parts.sublist(1).join(' ');
    }
    final studentData = {
      'name': _nameController.text.trim(),
      'grade': selectedGrade ?? '',
      'class': selectedClass ?? '',
      'year': _yearController.text.trim(),
      'father_name': _fatherNameController.text.trim(),
      'mother_name': _motherNameController.text.trim(),
      'parent_phone': _parentPhoneController.text.trim(),
    };
    try {
      if (widget.student != null && widget.student!['id'] != null) {
        // Update existing student
        final oldClass = widget.student!['class'];
        final oldGrade = widget.student!['grade'];
        final oldYear = widget.student!['year'];
        final newClass = studentData['class'];
        final newGrade = studentData['grade'];
        final newYear = studentData['year'];
        final studentId = widget.student!['id'];
        await FirebaseFirestore.instance
            .collection('students')
            .doc(studentId)
            .update(studentData);
        // If class, grade, or year changed, update class documents
        if (oldClass != newClass || oldGrade != newGrade || oldYear != newYear) {
          // Remove from old class
          final oldClassQuery = await FirebaseFirestore.instance
              .collection('classes')
              .where('class', isEqualTo: oldClass)
              .where('grade', isEqualTo: oldGrade)
              .where('year', isEqualTo: oldYear)
              .limit(1)
              .get();
          if (oldClassQuery.docs.isNotEmpty) {
            final oldClassDocId = oldClassQuery.docs.first.id;
            await FirebaseFirestore.instance
                .collection('classes')
                .doc(oldClassDocId)
                .update({
              'students': FieldValue.arrayRemove([studentId]),
            });
          }
          // Add to new class
          final newClassQuery = await FirebaseFirestore.instance
              .collection('classes')
              .where('class', isEqualTo: newClass)
              .where('grade', isEqualTo: newGrade)
              .where('year', isEqualTo: newYear)
              .limit(1)
              .get();
          if (newClassQuery.docs.isNotEmpty) {
            final newClassDocId = newClassQuery.docs.first.id;
            await FirebaseFirestore.instance
                .collection('classes')
                .doc(newClassDocId)
                .update({
              'students': FieldValue.arrayUnion([studentId]),
            });
          }
        }
      } else {
        // Add new student
        final docRef = await FirebaseFirestore.instance
            .collection('students')
            .add(studentData);
        // After adding, update the class document's students array
        final className = studentData['class'];
        final grade = studentData['grade'];
        final year = studentData['year'];
        // Find the class document
        final classQuery = await FirebaseFirestore.instance
            .collection('classes')
            .where('class', isEqualTo: className)
            .where('grade', isEqualTo: grade)
            .where('year', isEqualTo: year)
            .limit(1)
            .get();
        if (classQuery.docs.isNotEmpty) {
          final classDocId = classQuery.docs.first.id;
          await FirebaseFirestore.instance
              .collection('classes')
              .doc(classDocId)
              .update({
            'students': FieldValue.arrayUnion([docRef.id]),
          });
        }
      }
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan siswa: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.student != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Siswa' : 'Tambah Siswa'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nama'),
                validator: (value) => value!.isEmpty ? 'Masukkan nama' : null,
              ),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('classes').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }
                  final classes = snapshot.data!.docs;
                  final classOptions = classes.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final label = '${data['grade']} ${data['class']}';
                    return DropdownMenuItem<String>(
                      value: label,
                      child: Text(label),
                    );
                  }).toList();
                  return DropdownButtonFormField<String>(
                    value: _classController.text.isNotEmpty ? _classController.text : null,
                    items: classOptions,
                    onChanged: (value) {
                      setState(() {
                        _classController.text = value ?? '';
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Kelas'),
                    validator: (value) => value == null || value.isEmpty ? 'Pilih kelas' : null,
                  );
                },
              ),
              TextFormField(
                controller: _yearController,
                decoration: const InputDecoration(labelText: 'Tahun'),
                keyboardType: TextInputType.number,
                validator: (value) => value!.isEmpty ? 'Masukkan tahun' : null,
              ),
              TextFormField(
                controller: _fatherNameController,
                decoration: const InputDecoration(labelText: "Nama Ayah"),
                validator: (value) => value!.isEmpty ? "Masukkan nama ayah" : null,
              ),
              TextFormField(
                controller: _motherNameController,
                decoration: const InputDecoration(labelText: "Nama Ibu"),
                validator: (value) => value!.isEmpty ? "Masukkan nama ibu" : null,
              ),
              TextFormField(
                controller: _parentPhoneController,
                decoration: const InputDecoration(labelText: 'No. HP Orang Tua'),
                validator: (value) => value!.isEmpty ? 'Masukkan no. HP orang tua' : null,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 20),
              _isSaving
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _saveStudent,
                      child: Text(isEdit ? 'Perbarui' : 'Tambah'),
                    ),
            ],
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
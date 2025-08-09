import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

String toTitleCase(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed.toUpperCase();
}

class StudentFormScreen extends StatefulWidget {
  final Map<String, dynamic>?
      student; // Pass null for add, or student data for edit
  final Map<String, String>? userInfo; // For school_id

  const StudentFormScreen({Key? key, this.student, this.userInfo})
      : super(key: key);

  @override
  State<StudentFormScreen> createState() => _StudentFormScreenState();
}

class _StudentFormScreenState extends State<StudentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _classController;
  String? _selectedYearId;
  String? _selectedGender;
  bool _isSaving = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.student?['name'] ?? '');

    // Fix class text construction to handle empty class names
    String classText = '';
    if (widget.student != null &&
        widget.student?['enrollments'] != null &&
        (widget.student!['enrollments'] as List).isNotEmpty) {
      final enrollment = (widget.student!['enrollments'] as List).first;
      final grade = enrollment['grade'] ?? '';
      final className = enrollment['class'] ?? '';

      // Handle empty class name (stored as space)
      if (className.trim() == '' || className == ' ') {
        classText = grade; // Just show the grade
      } else {
        classText = '$grade$className';
      }
    }
    _classController = TextEditingController(text: classText);

    _selectedYearId = widget.student != null &&
            widget.student?['enrollments'] != null &&
            (widget.student!['enrollments'] as List).isNotEmpty
        ? (widget.student!['enrollments'] as List).first['year_id']
        : null;
    _selectedGender = widget.student?['gender'];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _classController.dispose();
    super.dispose();
  }

  Future<void> _saveStudent() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    String? selectedGrade;
    String? selectedClass;
    if (_classController.text.isNotEmpty &&
        _classController.text.trim() != ' ') {
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
      } else {
        // If no split found, treat the whole text as grade
        selectedGrade = text;
        selectedClass = '';
      }
    } else {
      // Handle empty class name case
      selectedGrade = '';
      selectedClass = '';
    }
    final studentData = {
      'name': toTitleCase(_nameController.text),
      'gender': _selectedGender,
      'status': 'active',
      'school_id': widget.userInfo?['school_id'] ??
          'school_1', // Default to school_1 if not provided
      'enrollments': [
        {
          'grade': selectedGrade ?? '',
          'class': selectedClass ?? '',
          'year_id': _selectedYearId,
        }
      ],
    };
    try {
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
      if (_selectedYearId != null) {
        // For editing: remove from old class if class changed
        if (widget.student != null &&
            widget.student!['enrollments'] != null &&
            (widget.student!['enrollments'] as List).isNotEmpty) {
          final oldEnrollment = (widget.student!['enrollments'] as List).first;
          final oldGrade = oldEnrollment['grade'];
          final oldClass = oldEnrollment['class'];
          final oldYearId = oldEnrollment['year_id'];

          // If class/grade/year changed, remove from old class
          if (oldGrade != selectedGrade ||
              oldClass != selectedClass ||
              oldYearId != _selectedYearId) {
            Query oldClassQuery;
            if (oldGrade != null && oldGrade.isNotEmpty) {
              if (oldClass != null && oldClass.isNotEmpty) {
                oldClassQuery = FirebaseFirestore.instance
                    .collection('classes')
                    .where('grade', isEqualTo: oldGrade)
                    .where('class_name', isEqualTo: oldClass)
                    .where('year_id', isEqualTo: oldYearId)
                    .where('school_id', isEqualTo: widget.userInfo?['school_id'] ?? 'school_1');
              } else {
                oldClassQuery = FirebaseFirestore.instance
                    .collection('classes')
                    .where('grade', isEqualTo: oldGrade)
                    .where('class_name', isEqualTo: ' ')
                    .where('year_id', isEqualTo: oldYearId)
                    .where('school_id', isEqualTo: widget.userInfo?['school_id'] ?? 'school_1');
              }

              final oldClassSnapshot = await oldClassQuery.limit(1).get();
              if (oldClassSnapshot.docs.isNotEmpty) {
                final oldClassDoc = oldClassSnapshot.docs.first;
                await oldClassDoc.reference.update({
                  'students': FieldValue.arrayRemove([studentId])
                });
              }
            }
          }
        }

        // Add to new class
        if (selectedGrade != null && selectedGrade!.isNotEmpty) {
          Query classQuery;
          if (selectedClass != null && selectedClass!.isNotEmpty) {
            // Both grade and class are provided
            classQuery = FirebaseFirestore.instance
                .collection('classes')
                .where('grade', isEqualTo: selectedGrade)
                .where('class_name', isEqualTo: selectedClass)
                .where('year_id', isEqualTo: _selectedYearId)
                .where('school_id', isEqualTo: widget.userInfo?['school_id'] ?? 'school_1');
          } else {
            // Only grade is provided, class_name is empty or space
            classQuery = FirebaseFirestore.instance
                .collection('classes')
                .where('grade', isEqualTo: selectedGrade)
                .where('class_name', isEqualTo: ' ')
                .where('year_id', isEqualTo: _selectedYearId)
                .where('school_id', isEqualTo: widget.userInfo?['school_id'] ?? 'school_1');
          }

          final classSnapshot = await classQuery.limit(1).get();
          if (classSnapshot.docs.isNotEmpty) {
            final classDoc = classSnapshot.docs.first;
            await classDoc.reference.update({
              'students': FieldValue.arrayUnion([studentId])
            });
          }
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

  void _showBulkCreationDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            BulkStudentCreationScreen(userInfo: widget.userInfo),
      ),
    );
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                    validator: (value) =>
                        value!.isEmpty ? 'Masukkan nama' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _selectedGender,
                    items: const [
                      DropdownMenuItem(
                          value: null,
                          child: Text('Pilih jenis kelamin (opsional)')),
                      DropdownMenuItem(
                          value: 'Laki-laki', child: Text('Laki-laki')),
                      DropdownMenuItem(
                          value: 'Perempuan', child: Text('Perempuan')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedGender = value;
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Jenis Kelamin',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.wc),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<QuerySnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('school_years')
                        .orderBy('start_date', descending: true)
                        .limit(1)
                        .get(),
                    builder: (context, yearSnap) {
                      if (!yearSnap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final latestYearId = yearSnap.data!.docs.isNotEmpty ? yearSnap.data!.docs.first.id : null;
                      if (latestYearId == null) {
                        return const SizedBox.shrink();
                      }
                      Query classesQuery = FirebaseFirestore.instance
                        .collection('classes')
                        .where('school_id', isEqualTo: widget.userInfo?['school_id'] ?? 'school_1')
                          .where('year_id', isEqualTo: latestYearId);
                      return StreamBuilder<QuerySnapshot>(
                        stream: classesQuery.snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final classes = snapshot.data!.docs;
                      final classOptions = classes.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final grade = data['grade'] ?? '';
                        final className = data['class_name'] ?? '';

                        String label;
                        if (className.trim() == '' || className == ' ') {
                              label = grade;
                        } else {
                          label = '$grade$className';
                        }

                        return DropdownMenuItem<String>(
                          value: label,
                          child: Text(label),
                        );
                      }).toList()
                        ..sort((a, b) => ((a.child as Text).data ?? '').compareTo((b.child as Text).data ?? ''));

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
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('school_years')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final years = snapshot.data!.docs;
                      final yearOptions = years.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return DropdownMenuItem<String>(
                          value: doc.id,
                          child: Text(data['name'] ?? doc.id),
                        );
                      }).toList()
                        ..sort((a, b) => ((a.child as Text).data ?? '').compareTo((b.child as Text).data ?? ''));
                      return DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _selectedYearId,
                        items: yearOptions,
                        onChanged: (value) {
                          setState(() {
                            _selectedYearId = value;
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Tahun Ajaran *',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          prefixIcon: const Icon(Icons.calendar_today_outlined),
                        ),
                        validator: (value) =>
                            value == null ? 'Pilih tahun ajaran' : null,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  if (!isEdit) ...[
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _showBulkCreationDialog,
                      icon: const Icon(Icons.group_add_outlined),
                      label: const Text('Tambah Siswa Secara Massal'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        backgroundColor: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _isSaving
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveStudent,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.save_outlined),
                          label:
                              Text(isEdit ? 'Perbarui Siswa' : 'Simpan Siswa'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            backgroundColor: Colors.teal,
                          ),
                        ),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _message!.startsWith('Gagal')
                            ? Colors.red
                            : Colors.green,
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

class BulkStudentCreationScreen extends StatefulWidget {
  final Map<String, String>? userInfo;

  const BulkStudentCreationScreen({Key? key, this.userInfo}) : super(key: key);

  @override
  State<BulkStudentCreationScreen> createState() =>
      _BulkStudentCreationScreenState();
}

class _BulkStudentCreationScreenState extends State<BulkStudentCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedGender;
  String? _selectedClass;
  String? _selectedYearId;
  int _numberOfStudents = 1;
  bool _isLoading = false;
  List<TextEditingController> _nameControllers = [];
  List<FocusNode> _nameFocusNodes = [];
  // Removed phone controllers

  @override
  void initState() {
    super.initState();
    _updateControllers();
  }

  void _updateControllers() {
    // Dispose old focus nodes to avoid leaks
    for (final node in _nameFocusNodes) {
      node.dispose();
    }
    _nameFocusNodes.clear();
    _nameControllers.clear();
    for (int i = 0; i < _numberOfStudents; i++) {
      _nameControllers.add(TextEditingController());
      _nameFocusNodes.add(FocusNode());
    }
  }

  @override
  void dispose() {
    for (var controller in _nameControllers) {
      controller.dispose();
    }
    for (final node in _nameFocusNodes) {
      node.dispose();
    }
    
    super.dispose();
  }

  Future<void> _saveBulkStudents() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedClass == null || _selectedYearId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Pilih kelas dan tahun ajaran terlebih dahulu!'),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Parse class format
      String? selectedGrade;
      String? selectedClass;
      if (_selectedClass!.isNotEmpty && _selectedClass!.trim() != ' ') {
        final text = _selectedClass!.trim();
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
        } else {
          // If no split found, treat the whole text as grade
          selectedGrade = text;
          selectedClass = '';
        }
      } else {
        // Handle empty class name case
        selectedGrade = '';
        selectedClass = '';
      }

      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();
      final studentIds = <String>[];

      // Create students
      for (int i = 0; i < _numberOfStudents; i++) {
        final name = toTitleCase(_nameControllers[i].text);

        if (name.isEmpty) continue; // Skip empty names

        final studentData = {
          'name': name,
          'gender': _selectedGender,
          'status': 'active',
          'school_id': widget.userInfo?['school_id'] ?? 'school_1',
          'enrollments': [
            {
              'grade': selectedGrade ?? '',
              'class': selectedClass ?? '',
              'year_id': _selectedYearId,
            }
          ],
        };

        final docRef = firestore.collection('students').doc();
        batch.set(docRef, studentData);
        studentIds.add(docRef.id);
      }

      // Commit the batch
      await batch.commit();

      // Add students to class
      if (_selectedYearId != null) {
        Query classQuery;
        if (selectedGrade != null && selectedGrade!.isNotEmpty) {
          if (selectedClass != null && selectedClass!.isNotEmpty) {
            // Both grade and class are provided
            classQuery = firestore
                .collection('classes')
                .where('grade', isEqualTo: selectedGrade)
                .where('class_name', isEqualTo: selectedClass)
                .where('year_id', isEqualTo: _selectedYearId)
                .where('school_id', isEqualTo: widget.userInfo?['school_id'] ?? 'school_1');
          } else {
            // Only grade is provided, class_name is empty or space
            classQuery = firestore
                .collection('classes')
                .where('grade', isEqualTo: selectedGrade)
                .where('class_name', isEqualTo: ' ')
                .where('year_id', isEqualTo: _selectedYearId)
                .where('school_id', isEqualTo: widget.userInfo?['school_id'] ?? 'school_1');
          }
        } else {
          // No grade provided, skip class enrollment
          return;
        }

        final classSnapshot = await classQuery.limit(1).get();
        if (classSnapshot.docs.isNotEmpty) {
          final classDoc = classSnapshot.docs.first;
          await classDoc.reference
              .update({'students': FieldValue.arrayUnion(studentIds)});
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Berhasil menambahkan $_numberOfStudents siswa!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Tambah Siswa Secara Massal'),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Pengaturan Umum',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _selectedGender,
                        items: const [
                          DropdownMenuItem(
                              value: null,
                              child: Text('Pilih jenis kelamin (opsional)')),
                          DropdownMenuItem(
                              value: 'Laki-laki', child: Text('Laki-laki')),
                          DropdownMenuItem(
                              value: 'Perempuan', child: Text('Perempuan')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedGender = value;
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Jenis Kelamin',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          prefixIcon: const Icon(Icons.wc),
                        ),
                      ),
                      const SizedBox(height: 16),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('classes')
                            .where('school_id', isEqualTo: widget.userInfo?['school_id'] ?? 'school_1')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          final classes = snapshot.data!.docs;
                          final classOptions = classes.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final grade = data['grade'] ?? '';
                            final className = data['class_name'] ?? '';

                            // Handle empty class name (stored as space)
                            String label;
                            if (className.trim() == '' || className == ' ') {
                              label = grade; // Just show the grade
                            } else {
                              label = '$grade$className';
                            }

                            return DropdownMenuItem<String>(
                              value: label,
                              child: Text(label),
                            );
                          }).toList()
                            ..sort((a, b) => ((a.child as Text).data ?? '').compareTo((b.child as Text).data ?? ''));
                          return DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: _selectedClass,
                            items: classOptions,
                            onChanged: (value) {
                              setState(() {
                                _selectedClass = value;
                              });
                            },
                            decoration: InputDecoration(
                              labelText: 'Kelas *',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              prefixIcon: const Icon(Icons.class_outlined),
                            ),
                            validator: (value) => value == null || value.isEmpty
                                ? 'Pilih kelas'
                                : null,
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('school_years')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          final years = snapshot.data!.docs;
                          final yearOptions = years.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            return DropdownMenuItem<String>(
                              value: doc.id,
                              child: Text(data['name'] ?? doc.id),
                            );
                          }).toList()
                            ..sort((a, b) => ((a.child as Text).data ?? '').compareTo((b.child as Text).data ?? ''));
                          return DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: _selectedYearId,
                            items: yearOptions,
                            onChanged: (value) {
                              setState(() {
                                _selectedYearId = value;
                              });
                            },
                            decoration: InputDecoration(
                              labelText: 'Tahun Ajaran *',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              prefixIcon:
                                  const Icon(Icons.calendar_today_outlined),
                            ),
                            validator: (value) =>
                                value == null ? 'Pilih tahun ajaran' : null,
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: '1',
                        decoration: InputDecoration(
                          labelText: 'Jumlah Siswa *',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          prefixIcon: const Icon(Icons.people_outline),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          final number = int.tryParse(value ?? '');
                          if (number == null || number < 1 || number > 50) {
                            return 'Masukkan angka antara 1-50';
                          }
                          return null;
                        },
                        onChanged: (value) {
                          final number = int.tryParse(value);
                          if (number != null && number >= 1 && number <= 50) {
                            setState(() {
                              _numberOfStudents = number;
                              _updateControllers();
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_selectedClass != null && _selectedYearId != null) ...[
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Data Siswa',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        ...List.generate(_numberOfStudents, (index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Siswa ${index + 1}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _nameControllers[index],
                                  focusNode: _nameFocusNodes[index],
                                  textInputAction: index < _numberOfStudents - 1
                                      ? TextInputAction.next
                                      : TextInputAction.done,
                                  onFieldSubmitted: (_) {
                                    if (index < _numberOfStudents - 1) {
                                      FocusScope.of(context)
                                          .requestFocus(_nameFocusNodes[index + 1]);
                                    } else {
                                      FocusScope.of(context).unfocus();
                                    }
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'Nama Lengkap *',
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    prefixIcon:
                                        const Icon(Icons.person_outline),
                                  ),
                                  validator: (value) =>
                                      value!.isEmpty ? 'Masukkan nama' : null,
                                ),
                                const SizedBox(height: 8),
                                // Parent phone removed
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                      onPressed: _isLoading ? null : _saveBulkStudents,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_outlined),
                      label: const Text('Simpan Semua Siswa'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        backgroundColor: Colors.teal,
                      ),
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

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CreateClassScreen extends StatefulWidget {
  final Map<String, dynamic>? classData; // For edit mode
  final Map<String, String>? userInfo; // For school_id
  const CreateClassScreen({Key? key, this.classData, this.userInfo}) : super(key: key);

  @override
  State<CreateClassScreen> createState() => _CreateClassScreenState();
}

class _CreateClassScreenState extends State<CreateClassScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _classNameController = TextEditingController();
  final TextEditingController _gradeController = TextEditingController();
  String? _selectedYearId;
  bool _isLoading = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (widget.classData != null) {
      // Edit mode - populate fields with existing data
      _classNameController.text = widget.classData!['class_name'] ?? '';
      _gradeController.text = widget.classData!['grade'] ?? '';
      _selectedYearId = widget.classData!['year_id'];
    }
  }

  Future<void> _createClass() async {
    setState(() => _isLoading = true);
    try {
      // Duplicate check: grade + class_name + year_id + school_id (only if class_name is provided)
      final className = _classNameController.text.trim();
      if (className.isNotEmpty) {
        final existing = await FirebaseFirestore.instance
          .collection('classes')
          .where('grade', isEqualTo: _gradeController.text.trim())
          .where('class_name', isEqualTo: className)
          .where('year_id', isEqualTo: _selectedYearId)
          .where('school_id', isEqualTo: widget.userInfo?['school_id'] ?? 'school_1')
          .get();
        if (existing.docs.isNotEmpty && (widget.classData == null || widget.classData!['id'] != existing.docs.first.id)) {
          setState(() {
            _isLoading = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Kelas dengan tingkat, nama, dan tahun ini sudah ada!'), backgroundColor: Colors.red),
            );
          }
          return;
        }
      }
      final classData = {
        'class_name': _classNameController.text.trim().isEmpty ? ' ' : _classNameController.text.trim(),
        'grade': _gradeController.text.trim(),
        'year_id': _selectedYearId,
        'students': widget.classData?['students'] ?? [], // Keep existing students if editing
        'school_id': widget.userInfo?['school_id'] ?? 'school_1', // Default to school_1 if not provided
      };
      
      if (widget.classData != null && widget.classData!['id'] != null) {
        // Edit mode
        await FirebaseFirestore.instance
            .collection('classes')
            .doc(widget.classData!['id'])
            .update(classData);
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Kelas berhasil diperbarui!'),
              backgroundColor: Colors.green,
            ),
          );
          // Navigate back after a short delay
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              Navigator.pop(context);
            }
          });
        }
      } else {
        // Create mode
        await FirebaseFirestore.instance.collection('classes').add(classData);
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Kelas berhasil dibuat!'),
              backgroundColor: Colors.green,
            ),
          );
          // Navigate back after a short delay
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              Navigator.pop(context);
            }
          });
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Buat Kelas Baru'),
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
                    controller: _gradeController,
                    decoration: InputDecoration(
                      labelText: 'Tingkat (contoh: 4) *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.school_outlined),
                    ),
                    validator: (value) => value == null || value.isEmpty ? 'Masukkan tingkat' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _classNameController,
                    decoration: InputDecoration(
                      labelText: 'Nama Kelas (contoh: A)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.class_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('school_years').snapshots(),
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
                        value: _selectedYearId,
                        items: yearOptions,
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
                  const SizedBox(height: 24),
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton.icon(
                    onPressed: _isLoading ? null : () {
                      if (_formKey.currentState!.validate()) {
                        _createClass();
                      }
                    },
                    icon: _isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: const Text('Simpan Kelas'),
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
                        color: _message!.startsWith('Kelas berhasil') ? Colors.green : Colors.red,
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
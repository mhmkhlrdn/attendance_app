import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CreateTeacherScreen extends StatefulWidget {
  final Map<String, dynamic>? teacher; // For edit mode
  final Map<String, String>? userInfo; // For school_id
  const CreateTeacherScreen({Key? key, this.teacher, this.userInfo}) : super(key: key);

  @override
  State<CreateTeacherScreen> createState() => _CreateTeacherScreenState();
}

class _CreateTeacherScreenState extends State<CreateTeacherScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _nuptkController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _role = 'guru';
  bool _isSaving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (widget.teacher != null) {
      // Edit mode - populate fields with existing data
      _nameController.text = widget.teacher!['name'] ?? '';
      _nuptkController.text = widget.teacher!['nuptk'] ?? '';
      _passwordController.text = widget.teacher!['password'] ?? '';
      _role = widget.teacher!['role'] ?? 'guru';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(widget.teacher != null ? 'Edit Data Guru' : 'Buat Data Guru Baru'),
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
                      labelText: 'Nama Guru *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                    validator: (value) => value == null || value.isEmpty ? 'Nama guru harus diisi' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nuptkController,
                    decoration: InputDecoration(
                      labelText: 'NUPTK *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.badge_outlined),
                    ),
                    validator: (value) => value == null || value.isEmpty ? 'NUPTK harus diisi' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Kata Sandi *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                    obscureText: true,
                    validator: (value) => value == null || value.isEmpty ? 'Kata sandi harus diisi' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _role,
                    items: const [
                      DropdownMenuItem(value: 'guru', child: Text('Guru')),
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _role = value ?? 'guru';
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Peran *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.shield_outlined),
                    ),
                    validator: (value) => value == null || value.isEmpty ? 'Pilih peran' : null,
                  ),
                  const SizedBox(height: 24),
                  _isSaving
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton.icon(
                    onPressed: _isSaving ? null : () async {
                      if (_formKey.currentState!.validate()) {
                        setState(() => _isSaving = true);
                        try {
                          // Duplicate NUPTK check
                          final existing = await FirebaseFirestore.instance
                            .collection('teachers')
                            .where('nuptk', isEqualTo: _nuptkController.text.trim())
                            .get();
                          if (existing.docs.isNotEmpty && (widget.teacher == null || widget.teacher!['id'] != existing.docs.first.id)) {
                            setState(() {
                              _isSaving = false;
                              _message = 'NUPTK sudah terdaftar!';
                            });
                            return;
                          }
                          final teacherData = {
                            'name': _nameController.text.trim().toUpperCase(),
                            'nuptk': _nuptkController.text.trim(),
                            'password': _passwordController.text.trim(),
                            'role': _role,
                            'school_id': widget.userInfo?['school_id'] ?? 'school_1', // Default to school_1 if not provided
                          };
                          
                          if (widget.teacher != null && widget.teacher!['id'] != null) {
                            // Edit mode
                            await FirebaseFirestore.instance
                                .collection('teachers')
                                .doc(widget.teacher!['id'])
                                .update(teacherData);
                            setState(() {
                              _isSaving = false;
                              _message = 'Guru berhasil diperbarui!';
                            });
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Guru berhasil diperbarui!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              setState(() => _message = null);
                              // Navigate back after a short delay
                              Future.delayed(const Duration(seconds: 1), () {
                                if (mounted) {
                                  Navigator.pop(context);
                                }
                              });
                            }
                          } else {
                            // Create mode
                            await FirebaseFirestore.instance.collection('teachers').add(teacherData);
                            setState(() {
                              _isSaving = false;
                              _message = 'Guru berhasil ditambahkan!';
                            });
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Guru berhasil ditambahkan!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              setState(() => _message = null);
                              // Navigate back after a short delay
                              Future.delayed(const Duration(seconds: 1), () {
                                if (mounted) {
                                  Navigator.pop(context);
                                }
                              });
                            }
                          }
                        } catch (e) {
                          setState(() {
                            _isSaving = false;
                            _message = 'Gagal: $e';
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
                            );
                            setState(() => _message = null);
                          }
                        }
                      }
                    },
                    icon: _isSaving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: Text(widget.teacher != null ? 'Perbarui Guru' : 'Simpan Guru'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _message!.startsWith('Guru berhasil') ? Colors.green : Colors.red,
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
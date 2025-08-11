import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/local_storage_service.dart';
import 'admin_students_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nuptkController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _selectedSchoolId;
  List<Map<String, dynamic>> _schools = [];
  bool _isLoadingSchools = true;
  List<Map<String, String>> _savedAccounts = [];

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    await _loadSchools();
    await _loadSavedAccounts();
  }

  Future<void> _loadSchools() async {
    try {
      final schoolsQuery = await FirebaseFirestore.instance.collection('schools').get();
      final schools = schoolsQuery.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? 'Unknown School',
          'address': data['address'] ?? '',
        };
      }).toList();
      
      setState(() {
        _schools = schools;
        _isLoadingSchools = false;
      });
    } catch (e) {
      print('Error loading schools: $e');
      setState(() => _isLoadingSchools = false);
    }
  }

  Future<void> _loadSavedAccounts() async {
    final accounts = await LocalStorageService.getSavedAccounts();
    if (mounted) {
      setState(() {
        _savedAccounts = accounts;
      });
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSchoolId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silakan pilih sekolah terlebih dahulu')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final nuptk = _nuptkController.text.trim();
      final password = _passwordController.text.trim();

      // Query teacher by NUPTK and school_id
      final teacherQuery = await FirebaseFirestore.instance
          .collection('teachers')
          .where('nuptk', isEqualTo: nuptk)
          .where('school_id', isEqualTo: _selectedSchoolId)
          .limit(1)
          .get();

      if (teacherQuery.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('NUPTK tidak ditemukan atau tidak terdaftar di sekolah ini'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final teacherData = teacherQuery.docs.first.data();
      final storedPassword = teacherData['password'] ?? '';

      if (password != storedPassword) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password salah'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Save user info with school_id
      final userInfo = <String, String>{
        'nuptk': nuptk,
        'name': teacherData['name'] ?? '',
        'role': teacherData['role'] ?? 'guru',
        'school_id': _selectedSchoolId!,
        'school_name': _schools.firstWhere((s) => s['id'] == _selectedSchoolId)['name'],
      };

      await LocalStorageService.saveUserInfo(userInfo);
      await LocalStorageService.addSavedAccount(userInfo);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => AdminStudentsScreen(
              userInfo: userInfo,
              role: userInfo['role']!,
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.teal.shade50,
              Colors.teal.shade100,
              Colors.teal.shade200,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_savedAccounts.isNotEmpty) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                'Akun tersimpan',
                                style: TextStyle(
                                  color: Colors.teal.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _savedAccounts.map((acc) {
                                final name = acc['name'] ?? '-';
                                final nuptk = acc['nuptk'] ?? '';
                                final role = acc['role'] ?? '';
                                final school = acc['school_name'] ?? (acc['school_id'] ?? '');
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8.0, bottom: 12.0),
                                  child: InputChip(
                                    avatar: const Icon(Icons.account_circle, color: Colors.white),
                                    backgroundColor: Colors.teal,
                                    label: Text(
                                      '$name\n$role • $school',
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                    onSelected: (_) {
                                      // Quick switch: prefill NUPTK and school, then focus password
                                      setState(() {
                                        _nuptkController.text = nuptk;
                                        _selectedSchoolId = acc['school_id'];
                                      });
                                    },
                                    onDeleted: () async {
                                      await LocalStorageService.removeSavedAccount(
                                        nuptk: nuptk,
                                        schoolId: acc['school_id'] ?? '',
                                        role: role,
                                      );
                                      await _loadSavedAccounts();
                                    },
                                    deleteIcon: const Icon(Icons.close, size: 18, color: Colors.white),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                        // Logo/Icon
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.teal.shade100,
                            borderRadius: BorderRadius.circular(40),
                          ),
                          child: Icon(
                            Icons.school,
                            size: 40,
                            color: Colors.teal.shade700,
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // Title
                        const Text(
                          'SADESA',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                        const Text(
                          'Sistem Absensi Digital Siswa Tanjungkarang',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,

                          ),
                        ),
                        const SizedBox(height: 32),

                        // School Selection
                        if (_isLoadingSchools)
                          const CircularProgressIndicator()
                        else
                          DropdownButtonFormField<String>(
                            value: _selectedSchoolId,
                            decoration: const InputDecoration(
                              labelText: 'Pilih Sekolah',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.school),
                            ),
                            items: _schools.map((school) {
                              return DropdownMenuItem(
                                value: school['id'] as String,
                                child: Text(school['name'] as String),
                              );
                            }).toList()
                              ..sort((a, b) => ((a.child as Text).data ?? '').compareTo((b.child as Text).data ?? '')),
                            onChanged: (value) {
                              setState(() {
                                _selectedSchoolId = value;
                              });
                            },
                            validator: (value) {
                              if (value == null) {
                                return 'Silakan pilih sekolah';
                              }
                              return null;
                            },
                          ),
                        
                        const SizedBox(height: 16),

                        // NUPTK Field
                        TextFormField(
                          controller: _nuptkController,
                          decoration: const InputDecoration(
                            labelText: 'NUPTK',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'NUPTK tidak boleh kosong';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Password Field
                        TextFormField(
                          controller: _passwordController,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lock),
                          ),
                          obscureText: true,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Password tidak boleh kosong';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),

                        // Login Button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text(
                                    'Masuk',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nuptkController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}



class TeacherHomeScreen extends StatelessWidget {
  const TeacherHomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Beranda Guru')),
      body: const Center(child: Text('Selamat datang, Guru!')),
    );
  }
}


class TeacherClassesScreen extends StatelessWidget {
  final Map<String, String> userInfo;
  const TeacherClassesScreen({Key? key, required this.userInfo}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kelas & Jadwal Saya')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('schedules')
            .where('teacher_id', isEqualTo: userInfo['nuptk'])
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Tidak ada kelas atau jadwal.'));
          }
          final schedules = snapshot.data!.docs;
          return ListView.builder(
            itemCount: schedules.length,
            itemBuilder: (context, index) {
              final data = schedules[index].data() as Map<String, dynamic>;
              return ListTile(
                title: Text('Kelas: ${data['class_id'] ?? '-'}'),
                subtitle: Text('Mata Pelajaran: ${data['subject'] ?? '-'}\nJadwal: ${data['time'] ?? '-'}'),
              );
            },
          );
        },
      ),
    );
  }
} 
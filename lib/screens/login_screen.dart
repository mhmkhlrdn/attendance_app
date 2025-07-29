import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_students_screen.dart';
import '../services/local_storage_service.dart';
import '../services/offline_sync_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nuptkController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final nuptk = _nuptkController.text.trim();
      final password = _passwordController.text.trim();
      final query = await FirebaseFirestore.instance
          .collection('teachers')
          .where('nuptk', isEqualTo: nuptk)
          .limit(1)
          .get();
      if (query.docs.isEmpty) {
        setState(() {
          _errorMessage = 'NUPTK tidak ditemukan.';
        });
      } else {
        final teacher = query.docs.first.data();
        if (teacher['password'] == password) {
          final userInfo = <String, String>{
            'name': (teacher['name'] ?? '').toString(),
            'nuptk': (teacher['nuptk'] ?? '').toString(),
            'role': (teacher['role'] ?? '').toString(),
          };
          
          // Save user info locally
          await LocalStorageService.saveUserInfo(userInfo);
          
          // Sync teacher data in background
          OfflineSyncService.syncTeacherData(teacher['nuptk']?.toString() ?? '');
          
          // Redirect based on role
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => AdminStudentsScreen(
                userInfo: userInfo,
                role: teacher['role']?.toString() ?? 'guru',
              ),
            ),
          );
        } else {
          setState(() {
            _errorMessage = 'Kata sandi salah.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Gagal login: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.fingerprint,
                  size: 80,
                  color: Colors.teal,
                ),
                const SizedBox(height: 16),
                Text(
                  'Selamat Datang',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Masuk untuk melanjutkan ke aplikasi presensi',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 40),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nuptkController,
                        decoration: InputDecoration(
                          labelText: 'NUPTK',
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        validator: (value) => value == null || value.isEmpty ? 'Masukkan NUPTK' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: 'Kata Sandi',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        obscureText: true,
                        validator: (value) => value == null || value.isEmpty ? 'Masukkan kata sandi' : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: () {
                          if (_formKey.currentState!.validate()) {
                            _login();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          backgroundColor: Colors.teal,
                        ),
                        child: const Text('Masuk'),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
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
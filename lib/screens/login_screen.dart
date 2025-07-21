import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_students_screen.dart';

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
          // Redirect based on role
          if (teacher['role'] == 'admin') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => AdminStudentsScreen(userInfo: {
                'name': teacher['name'] ?? '',
                'nuptk': teacher['nuptk'] ?? '',
                'role': teacher['role'] ?? '',
              }, role: 'admin')),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => AdminStudentsScreen(userInfo: {
                  'name': teacher['name'] ?? '',
                  'nuptk': teacher['nuptk'] ?? '',
                  'role': teacher['role'] ?? '',
                }, role: 'guru'),
              ),
            );
          }
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
      appBar: AppBar(title: const Text('Login Guru')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextFormField(
                controller: _nuptkController,
                decoration: const InputDecoration(labelText: 'NUPTK'),
                validator: (value) => value == null || value.isEmpty ? 'Masukkan NUPTK' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Kata Sandi'),
                obscureText: true,
                validator: (value) => value == null || value.isEmpty ? 'Masukkan kata sandi' : null,
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                const CircularProgressIndicator()
              else
                ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      _login();
                    }
                  },
                  child: const Text('Masuk'),
                ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Beranda Admin')),
      body: const Center(child: Text('Selamat datang, Admin!')),
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

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({Key? key, this.userInfo, this.showBackButton = false}) : super(key: key);
  final Map<String, String>? userInfo;
  final bool showBackButton;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _nuptkController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _classIdController = TextEditingController();
  final TextEditingController _attendanceController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _submitAttendance() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final date = _dateController.text.trim();
      final nuptk = _nuptkController.text.trim();
      final subject = _subjectController.text.trim();
      final time = _timeController.text.trim();
      final classId = _classIdController.text.trim();
      final attendance = _attendanceController.text.trim();

      if (date.isEmpty || nuptk.isEmpty || subject.isEmpty || time.isEmpty || classId.isEmpty || attendance.isEmpty) {
        setState(() {
          _errorMessage = 'Semua field harus diisi.';
        });
        return;
      }

      await FirebaseFirestore.instance.collection('attendances').add({
        'date': date,
        'teacher_id': nuptk,
        'subject': subject,
        'time': time,
        'class_id': classId,
        'attendance': attendance,
        'created_at': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Presensi berhasil disimpan.')));
      Navigator.pop(context); // Kembali ke TeacherClassesScreen
    } catch (e) {
      setState(() {
        _errorMessage = 'Gagal menyimpan presensi: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final userInfo = widget.userInfo ?? {};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Presensi'),
        automaticallyImplyLeading: widget.showBackButton,
        leading: widget.showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TeacherClassesScreen(userInfo: userInfo),
                    ),
                  );
                },
              )
            : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextFormField(
                controller: _dateController,
                decoration: const InputDecoration(labelText: 'Tanggal'),
                validator: (value) => value == null || value.isEmpty ? 'Masukkan tanggal' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nuptkController,
                decoration: const InputDecoration(labelText: 'NUPTK'),
                validator: (value) => value == null || value.isEmpty ? 'Masukkan NUPTK' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _subjectController,
                decoration: const InputDecoration(labelText: 'Mata Pelajaran'),
                validator: (value) => value == null || value.isEmpty ? 'Masukkan mata pelajaran' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _timeController,
                decoration: const InputDecoration(labelText: 'Waktu'),
                validator: (value) => value == null || value.isEmpty ? 'Masukkan waktu' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _classIdController,
                decoration: const InputDecoration(labelText: 'ID Kelas'),
                validator: (value) => value == null || value.isEmpty ? 'Masukkan ID kelas' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _attendanceController,
                decoration: const InputDecoration(labelText: 'Presensi'),
                validator: (value) => value == null || value.isEmpty ? 'Masukkan presensi' : null,
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                const CircularProgressIndicator()
              else
                ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      _submitAttendance();
                    }
                  },
                  child: const Text('Simpan Presensi'),
                ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
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
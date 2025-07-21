
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';
import 'student_form_screen.dart';
import 'create_class_screen.dart';

class AdminStudentsScreen extends StatefulWidget {
  final Map<String, String> userInfo;
  final String role;
  const AdminStudentsScreen({Key? key, required this.userInfo, this.role = 'admin'}) : super(key: key);

  @override
  State<AdminStudentsScreen> createState() => _AdminStudentsScreenState();
}

class _AdminStudentsScreenState extends State<AdminStudentsScreen> {
  int _selectedIndex = 0;

  List<Widget> _getScreens() {
    return [
      _StudentListScreen(role: widget.role),
      _TeacherListScreen(role: widget.role),
      _ClassListScreen(role: widget.role),
      _ScheduleListScreen(role: widget.role),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _onAttendancePressed() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AttendanceScreen(userInfo: widget.userInfo)),
    );
  }

  void _logout() {
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          drawer: Drawer(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                UserAccountsDrawerHeader(
                  accountName: Text(widget.userInfo['name'] ?? '-'),
                  accountEmail: Text('NUPTK: ${widget.userInfo['nuptk'] ?? '-'}'),
                  currentAccountPicture: const CircleAvatar(
                    child: Icon(Icons.person, size: 40),
                  ),
                  otherAccountsPictures: [
                    Chip(
                      label: Text(
                        widget.userInfo['role'] == 'admin' ? 'Admin' : 'Guru',
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: widget.userInfo['role'] == 'admin' ? Colors.blue : Colors.green,
                    ),
                  ],
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Keluar'),
                  onTap: _logout,
                ),
              ],
            ),
          ),
          body: _getScreens()[_selectedIndex],
          bottomNavigationBar: BottomNavigationBar(
            items: <BottomNavigationBarItem>[
              const BottomNavigationBarItem(
                icon: Icon(Icons.people),
                label: 'Siswa',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: 'Guru',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.class_),
                label: 'Kelas',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.schedule),
                label: 'Jadwal',
              ),
            ],
            currentIndex: _selectedIndex,
            onTap: _onItemTapped,
            selectedItemColor: Colors.blue,
            unselectedItemColor: Colors.grey,
            backgroundColor: Colors.white,
            type: BottomNavigationBarType.fixed,
          ),
          floatingActionButton: widget.role == 'admin'
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 24.0),
                  child: FloatingActionButton(
                    onPressed: _onAttendancePressed,
                    backgroundColor: Colors.orange,
                    elevation: 8,
                    shape: const CircleBorder(),
                    child: const Icon(Icons.fingerprint, size: 36, color: Colors.white),
                    tooltip: 'Presensi',
                  ),
                )
              : null,
          floatingActionButtonLocation: widget.role == 'admin'
              ? FloatingActionButtonLocation.centerDocked
              : null,
        ),
        // Sidebar indicator
        Positioned(
          top: 16,
          left: 8,
          child: GestureDetector(
            onTap: () => Scaffold.of(context).openDrawer(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.menu, size: 24, color: Colors.black54),
            ),
          ),
        ),
      ],
    );
  }
}

class _TeacherListScreen extends StatelessWidget {
  final String role;
  const _TeacherListScreen({Key? key, required this.role}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guru'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('teachers').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Tidak ada guru.'));
          }
          final teachers = snapshot.data!.docs;
          return ListView.builder(
            itemCount: teachers.length,
            itemBuilder: (context, index) {
              final data = teachers[index].data() as Map<String, dynamic>;
              return ListTile(
                title: Text(data['name'] ?? ''),
                subtitle: Text('NUPTK: ${data['nuptk'] ?? ''}\nRole: ${data['role'] ?? ''}'),
              );
            },
          );
        },
      ),
      floatingActionButton: role == 'admin'
          ? FloatingActionButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CreateTeacherScreen(),
                  ),
                );
              },
              child: const Icon(Icons.add),
              tooltip: 'Tambah Guru',
            )
          : null,
    );
  }
}

class CreateTeacherScreen extends StatefulWidget {
  const CreateTeacherScreen({Key? key}) : super(key: key);

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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buat Data Guru Baru')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nama Guru'),
                validator: (value) => value == null || value.isEmpty ? 'Nama guru harus diisi' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nuptkController,
                decoration: const InputDecoration(labelText: 'NUPTK'),
                validator: (value) => value == null || value.isEmpty ? 'NUPTK harus diisi' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Kata Sandi'),
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
                decoration: const InputDecoration(labelText: 'Peran'),
                validator: (value) => value == null || value.isEmpty ? 'Pilih peran' : null,
              ),
              const SizedBox(height: 24),
              _isSaving
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          setState(() => _isSaving = true);
                          try {
                            await FirebaseFirestore.instance.collection('teachers').add({
                              'name': _nameController.text.trim(),
                              'nuptk': _nuptkController.text.trim(),
                              'password': _passwordController.text.trim(),
                              'role': _role,
                            });
                            setState(() {
                              _isSaving = false;
                              _message = 'Guru berhasil ditambahkan!';
                            });
                          } catch (e) {
                            setState(() {
                              _isSaving = false;
                              _message = 'Gagal: $e';
                            });
                          }
                        }
                      },
                      child: const Text('Tambah Guru'),
                    ),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(
                  _message!,
                  style: TextStyle(
                    color: _message!.startsWith('Guru berhasil') ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
class _StudentListScreen extends StatelessWidget {
  final String role;
  const _StudentListScreen({Key? key, required this.role}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Siswa'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('students').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Tidak ada siswa.'));
          }
          final students = snapshot.data!.docs;
          return ListView.builder(
            itemCount: students.length,
            itemBuilder: (context, index) {
              final student = students[index];
              final data = student.data() as Map<String, dynamic>;
              return ListTile(
                title: Text(data['name'] ?? ''),
                subtitle: Text('Kelas: ${data['grade']} ${data['class']}'),
                trailing: role == 'admin'
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
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
                            icon: const Icon(Icons.delete),
                            onPressed: () async {
                              await FirebaseFirestore.instance.collection('students').doc(student.id).delete();
                            },
                          ),
                        ],
                      )
                    : null,
                onTap: role == 'admin'
                    ? () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => StudentFormScreen(
                              student: {...data, 'id': student.id},
                            ),
                          ),
                        );
                      }
                    : null,
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
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
      ),
    );
  }
}

class _ClassListScreen extends StatelessWidget {
  final String role;
  const _ClassListScreen({Key? key, required this.role}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelas'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('classes').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Tidak ada kelas.'));
          }
          final classes = snapshot.data!.docs;
          return ListView.builder(
            itemCount: classes.length,
            itemBuilder: (context, index) {
              final classDoc = classes[index];
              final data = classDoc.data() as Map<String, dynamic>;
              final className = data['class'] ?? '';
              final grade = data['grade'] ?? '';
              final year = data['year'] ?? '';
              return ListTile(
                title: Text('Kelas $grade$className ($year)'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => _ClassStudentsScreen(
                        className: className,
                        grade: grade,
                        year: data['year'],
                        studentIds: List<String>.from(data['students'] ?? []),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: role == 'admin'
          ? FloatingActionButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CreateClassScreen(),
                  ),
                );
              },
              child: const Icon(Icons.add),
              tooltip: 'Tambah Kelas',
            )
          : null,
    );
  }
}

class _ClassStudentsScreen extends StatelessWidget {
  final String className;
  final String grade;
  final String year;
  final List<String> studentIds;

  const _ClassStudentsScreen({
    Key? key,
    required this.className,
    required this.grade,
    required this.year,
    required this.studentIds,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Siswa di Kelas $grade$className ($year)'),
      ),
      body: studentIds.isEmpty
          ? const Center(child: Text('Tidak ada siswa di kelas ini.'))
          : FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance
                  .collection('students')
                  .where(FieldPath.documentId, whereIn: studentIds)
                  .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('Tidak ada siswa ditemukan.'));
                }
                final students = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: students.length,
                  itemBuilder: (context, index) {
                    final data = students[index].data() as Map<String, dynamic>;
                    return ListTile(
                      title: Text(data['name'] ?? ''),
                      subtitle: Text('NISN: ${data['nisn'] ?? ''}'),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _ScheduleListScreen extends StatelessWidget {
  final String role;
  const _ScheduleListScreen({Key? key, required this.role}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jadwal'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('schedules').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Tidak ada jadwal.'));
          }
          final schedules = snapshot.data!.docs;
          return ListView.builder(
            itemCount: schedules.length,
            itemBuilder: (context, index) {
              final data = schedules[index].data() as Map<String, dynamic>;
              return ListTile(
                title: Text(data['subject'] ?? ''),
                subtitle: Text('Kelas: ${data['class_id'] ?? ''}\nGuru: ${data['teacher_id'] ?? ''}\nWaktu: ${data['time'] ?? ''}'),
              );
            },
          );
        },
      ),
      floatingActionButton: role == 'admin'
          ? FloatingActionButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CreateScheduleScreen(),
                  ),
                );
              },
              child: const Icon(Icons.add),
              tooltip: 'Tambah Jadwal',
            )
          : null,
    );
  }
}

class CreateScheduleScreen extends StatefulWidget {
  const CreateScheduleScreen({Key? key}) : super(key: key);

  @override
  State<CreateScheduleScreen> createState() => _CreateScheduleScreenState();
}

class _CreateScheduleScreenState extends State<CreateScheduleScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedClassId;
  String? _selectedTeacherId;
  final TextEditingController _subjectController = TextEditingController();
  String? _selectedDay;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isSaving = false;
  String? _message;

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buat Jadwal')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Class dropdown
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('classes').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }
                  final classes = snapshot.data!.docs;
                  return DropdownButtonFormField<String>(
                    value: _selectedClassId,
                    items: classes.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final label = 'Kelas ${data['grade']} ${data['class']} (${data['year']})';
                      return DropdownMenuItem<String>(
                        value: doc.id,
                        child: Text(label),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedClassId = value;
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Kelas'),
                    validator: (value) => value == null ? 'Pilih kelas' : null,
                  );
                },
              ),
              const SizedBox(height: 16),
              // Teacher dropdown
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('teachers').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }
                  final teachers = snapshot.data!.docs;
                  return DropdownButtonFormField<String>(
                    value: _selectedTeacherId,
                    items: teachers.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final label = '${data['name']} (${data['nuptk']})';
                      return DropdownMenuItem<String>(
                        value: doc['nuptk'],
                        child: Text(label),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedTeacherId = value;
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Guru'),
                    validator: (value) => value == null ? 'Pilih guru' : null,
                  );
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _subjectController,
                decoration: const InputDecoration(labelText: 'Mata Pelajaran'),
                validator: (value) => value == null || value.isEmpty ? 'Masukkan mata pelajaran' : null,
              ),
              const SizedBox(height: 16),
             DropdownButtonFormField<String>(
               value: _selectedDay,
               items: const [
                 DropdownMenuItem(value: 'Senin', child: Text('Senin')),
                 DropdownMenuItem(value: 'Selasa', child: Text('Selasa')),
                 DropdownMenuItem(value: 'Rabu', child: Text('Rabu')),
                 DropdownMenuItem(value: 'Kamis', child: Text('Kamis')),
                 DropdownMenuItem(value: 'Jumat', child: Text('Jumat')),
                 DropdownMenuItem(value: 'Sabtu', child: Text('Sabtu')),
                 DropdownMenuItem(value: 'Minggu', child: Text('Minggu')),
               ],
               onChanged: (value) {
                 setState(() {
                   _selectedDay = value;
                 });
               },
               decoration: const InputDecoration(labelText: 'Hari'),
               validator: (value) => value == null ? 'Pilih hari' : null,
             ),
             const SizedBox(height: 16),
             Row(
               children: [
                 Expanded(
                   child: InkWell(
                     onTap: () => _pickTime(isStart: true),
                     child: InputDecorator(
                       decoration: const InputDecoration(labelText: 'Jam Mulai'),
                       child: Text(_startTime != null ? _startTime!.format(context) : 'Pilih jam mulai'),
                     ),
                   ),
                 ),
                 const SizedBox(width: 16),
                 Expanded(
                   child: InkWell(
                     onTap: () => _pickTime(isStart: false),
                     child: InputDecorator(
                       decoration: const InputDecoration(labelText: 'Jam Selesai'),
                       child: Text(_endTime != null ? _endTime!.format(context) : 'Pilih jam selesai'),
                     ),
                   ),
                 ),
               ],
             ),
             const SizedBox(height: 24),
              _isSaving
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: () async {
                        if (_formKey.currentState!.validate()
                           && _selectedDay != null
                           && _startTime != null
                           && _endTime != null) {
                          setState(() => _isSaving = true);
                          try {
                            final timeString = '$_selectedDay ${_startTime!.format(context)}-${_endTime!.format(context)}';
                            await FirebaseFirestore.instance.collection('schedules').add({
                              'teacher_id': _selectedTeacherId,
                              'subject': _subjectController.text.trim(),
                              'class_id': _selectedClassId,
                              'time': timeString,
                            });
                            setState(() {
                              _isSaving = false;
                              _message = 'Jadwal berhasil dibuat!';
                            });
                          } catch (e) {
                            setState(() {
                              _isSaving = false;
                              _message = 'Gagal: $e';
                            });
                          }
                        }
                      },
                      child: const Text('Buat Jadwal'),
                    ),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(
                  _message!,
                  style: TextStyle(
                    color: _message!.startsWith('Jadwal berhasil') ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
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
  List<Map<String, dynamic>> students = [];
  String? className;
  String? classId;
  String? scheduleId;
  bool isLoading = true;
  Map<String, String> attendance = {};
  String? errorMsg;

  @override
  void initState() {
    super.initState();
    _loadScheduleAndStudents();
  }

  Future<void> _loadScheduleAndStudents() async {
    setState(() { isLoading = true; errorMsg = null; });
    try {
      final now = DateTime.now();
      final weekday = _weekdayToIndo(now.weekday);
      final nuptk = widget.userInfo?['nuptk'] ?? '';
      // Cari jadwal yang cocok
      final scheduleQuery = await FirebaseFirestore.instance
        .collection('schedules')
        .where('teacher_id', isEqualTo: nuptk)
        .get();
      Map<String, dynamic>? foundSchedule;
      String? foundScheduleId;
      DateTime? nearestTime;
      Map<String, dynamic>? nearestSchedule;
      for (var doc in scheduleQuery.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['time'] != null && data['time'].toString().toLowerCase().contains(weekday.toLowerCase())) {
          // Ekstrak jam mulai dan selesai
          final timeString = data['time'].toString();
          final regex = RegExp(r'(\d{2}:\d{2})-(\d{2}:\d{2})');
          final match = regex.firstMatch(timeString);
          if (match != null) {
            final start = match.group(1)!;
            final end = match.group(2)!;
            final nowMinutes = now.hour * 60 + now.minute;
            final startParts = start.split(':').map(int.parse).toList();
            final endParts = end.split(':').map(int.parse).toList();
            final startMinutes = startParts[0] * 60 + startParts[1];
            final endMinutes = endParts[0] * 60 + endParts[1];
            if (nowMinutes >= startMinutes && nowMinutes <= endMinutes) {
              foundSchedule = data;
              foundScheduleId = doc.id;
              break;
            } else if (startMinutes > nowMinutes) {
              // Cek jadwal terdekat berikutnya
              final scheduleDateTime = DateTime(now.year, now.month, now.day, startParts[0], startParts[1]);
              if (nearestTime == null || scheduleDateTime.isBefore(nearestTime)) {
                nearestTime = scheduleDateTime;
                nearestSchedule = data;
              }
            }
          }
        } else if (data['time'] != null) {
          // Cek jadwal hari lain dalam minggu ini
          final timeString = data['time'].toString();
          final regex = RegExp(r'([A-Za-z]+) (\d{2}:\d{2})-(\d{2}:\d{2})');
          final match = regex.firstMatch(timeString);
          if (match != null) {
            final dayStr = match.group(1)!;
            final start = match.group(2)!;
            final startParts = start.split(':').map(int.parse).toList();
            // Hitung selisih hari
            final targetWeekday = _indoToWeekday(dayStr);
            int daysDiff = (targetWeekday - now.weekday) % 7;
            if (daysDiff < 0) daysDiff += 7;
            final scheduleDateTime = DateTime(now.year, now.month, now.day + daysDiff, startParts[0], startParts[1]);
            if (scheduleDateTime.isAfter(now)) {
              if (nearestTime == null || scheduleDateTime.isBefore(nearestTime)) {
                nearestTime = scheduleDateTime;
                nearestSchedule = data;
              }
            }
          }
        }
      }
      if (foundSchedule == null) {
        setState(() {
          isLoading = false;
          errorMsg = 'Tidak ada jadwal mengajar untuk waktu ini.';
        });
        // Tampilkan jadwal terdekat jika ada
        if (nearestSchedule != null && nearestTime != null) {
          Future.delayed(Duration.zero, () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Jadwal Terdekat'),
                content: Text('Jadwal berikutnya: ${nearestSchedule?['time']}\nKelas: ${nearestSchedule?['class_id']}'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Tutup'),
                  ),
                ],
              ),
            );
          });
        }
        return;
      }
      classId = foundSchedule['class_id'];
      scheduleId = foundScheduleId;
      // Ambil data kelas
      final classDoc = await FirebaseFirestore.instance.collection('classes').doc(classId).get();
      final classData = classDoc.data();
      className = classData!['grade'].toString() + ' ' + (classData?['class'] ?? '');
      final studentIds = List<String>.from(classData?['students'] ?? []);
      if (studentIds.isEmpty) {
        setState(() {
          isLoading = false;
          errorMsg = 'Tidak ada siswa di kelas ini.';
        });
        return;
      }
      // Ambil data siswa
      final studentsQuery = await FirebaseFirestore.instance
        .collection('students')
        .where(FieldPath.documentId, whereIn: studentIds)
        .get();
      students = studentsQuery.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'name': data['name'] ?? '',
        };
      }).toList();
      // Inisialisasi status presensi default
      attendance = { for (var s in students) s['id']: 'hadir' };
      setState(() { isLoading = false; });
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMsg = 'Gagal memuat data: $e';
      });
    }
  }

  void _setAllHadir() {
    setState(() {
      for (var s in students) {
        attendance[s['id']] = 'hadir';
      }
    });
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
      body: isLoading
        ? const Center(child: CircularProgressIndicator())
        : errorMsg != null
          ? Center(child: Text(errorMsg!, style: const TextStyle(color: Colors.red)))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (className != null)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('Kelas: $className', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: ElevatedButton.icon(
                    onPressed: _setAllHadir,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Hadir Semua'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: students.length,
                    itemBuilder: (context, index) {
                      final s = students[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: ListTile(
                          title: Text(s['name']),
                          trailing: DropdownButton<String>(
                            value: attendance[s['id']],
                            items: const [
                              DropdownMenuItem(value: 'hadir', child: Text('Hadir')),
                              DropdownMenuItem(value: 'sakit', child: Text('Sakit')),
                              DropdownMenuItem(value: 'izin', child: Text('Izin')),
                              DropdownMenuItem(value: 'alfa', child: Text('Alfa')),
                            ],
                            onChanged: (value) {
                              setState(() {
                                attendance[s['id']] = value!;
                              });
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

String _weekdayToIndo(int weekday) {
  switch (weekday) {
    case 1: return 'Senin';
    case 2: return 'Selasa';
    case 3: return 'Rabu';
    case 4: return 'Kamis';
    case 5: return 'Jumat';
    case 6: return 'Sabtu';
    case 7: return 'Minggu';
    default: return '';
  }
}

int _indoToWeekday(String hari) {
  switch (hari.toLowerCase()) {
    case 'senin': return 1;
    case 'selasa': return 2;
    case 'rabu': return 3;
    case 'kamis': return 4;
    case 'jumat': return 5;
    case 'sabtu': return 6;
    case 'minggu': return 7;
    default: return 1;
  }
} 


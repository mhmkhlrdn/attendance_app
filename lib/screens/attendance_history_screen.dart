import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'attendance_detail_screen.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  final Map<String, String> userInfo;
  final String role;
  const AttendanceHistoryScreen({Key? key, required this.userInfo, required this.role}) : super(key: key);

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  String _selectedMonth = '';
  List<String> _availableMonths = [];
  Map<String, List<Map<String, dynamic>>> _monthlyData = {};
  Map<String, String> _studentNames = {}; // studentId -> studentName
  bool _isLoading = true;
  
  // Admin-specific filtering
  String? _selectedClassId;
  List<Map<String, dynamic>> _availableClasses = [];
  bool _isLoadingClasses = false;

  @override
  void initState() {
    super.initState();
    if (widget.role == 'admin') {
      _loadClasses();
    }
    _loadAttendanceData();
  }

  Future<void> _loadAttendanceData() async {
    print('\n=== LOADING ATTENDANCE DATA ===');
    setState(() => _isLoading = true);
    
    try {
      Query attendanceQuery = FirebaseFirestore.instance.collection('attendances').orderBy('date', descending: true);
      
      if (widget.role == 'admin') {
        print('Loading all attendance data (admin mode)');
        if (_selectedClassId != null) {
          attendanceQuery = attendanceQuery.where('class_id', isEqualTo: _selectedClassId);
          print('Filtering by class ID: $_selectedClassId');
        }
      } else {
        attendanceQuery = attendanceQuery.where('teacher_id', isEqualTo: widget.userInfo['nuptk']);
        print('Filtering by teacher NUPTK: ${widget.userInfo['nuptk']}');
      }

      print('Executing Firestore query...');
      final snapshot = await attendanceQuery.get();
      print('Query completed. Found ${snapshot.docs.length} attendance records');
      
      final attendances = snapshot.docs;
      
      if (attendances.isEmpty) {
        print('WARNING: No attendance records found!');
        setState(() {
          _monthlyData = {};
          _availableMonths = [];
          _selectedMonth = '';
          _isLoading = false;
        });
        return;
      }

      // Group attendance by month
      final monthlyGroups = <String, List<Map<String, dynamic>>>{};
      final months = <String>[];

      print('\n--- Processing attendance records ---');
      for (var i = 0; i < attendances.length; i++) {
        final doc = attendances[i];
        final data = doc.data() as Map<String, dynamic>;
        print('Record ${i + 1}: ${doc.id}');
        print('  Data: $data');
        
        DateTime? date;
        final dateField = data['date'];
        print('  Date field type: ${dateField.runtimeType}');
        print('  Date field value: $dateField');
        
        if (dateField is Timestamp) {
          date = dateField.toDate();
        } else if (dateField is String) {
          try {
            date = DateTime.parse(dateField);
          } catch (e) {
            print('  ✗ ERROR parsing date string: $e');
          }
        } else if (dateField is DateTime) {
          date = dateField;
        }
        
        print('  Parsed date: $date');
        
        if (date != null) {
          final monthKey = '${date.year}-${date.month.toString().padLeft(2, '0')}';
          final monthDisplay = _getMonthDisplay(date);
          
          print('  Month key: $monthKey');
          print('  Month display: $monthDisplay');
          
          if (!monthlyGroups.containsKey(monthKey)) {
            monthlyGroups[monthKey] = [];
            months.add(monthKey);
            print('  → Created new month group: $monthKey');
          }
          
          monthlyGroups[monthKey]!.add({
            'id': doc.id,
            'data': data,
            'date': date,
            'monthDisplay': monthDisplay,
          });
          print('  → Added to month group: $monthKey');
        } else {
          print('  ✗ WARNING: Date is null for record ${doc.id}');
        }
      }

      // Sort months in descending order
      months.sort((a, b) => b.compareTo(a));
      print('\n--- Month groups created ---');
      print('Available months: $months');
      print('Monthly groups: ${monthlyGroups.keys.toList()}');
      
      for (var month in monthlyGroups.keys) {
        print('  Month $month: ${monthlyGroups[month]!.length} records');
      }

      // Load all student names
      print('\n--- Loading student names ---');
      final studentNames = <String, String>{};
      final allStudentIds = <String>{};
      
      for (var monthData in monthlyGroups.values) {
        for (var attendance in monthData) {
          final data = attendance['data'] as Map<String, dynamic>;
          final studentIds = List<String>.from(data['student_ids'] ?? []);
          allStudentIds.addAll(studentIds);
        }
      }
      
      print('Found ${allStudentIds.length} unique student IDs: ${allStudentIds.toList()}');
      
      // Load all student names in parallel
      final nameFutures = allStudentIds.map((studentId) async {
        final name = await _loadStudentName(studentId);
        return MapEntry(studentId, name);
      });
      
      final nameResults = await Future.wait(nameFutures);
      for (var entry in nameResults) {
        studentNames[entry.key] = entry.value;
      }
      
      print('Loaded ${studentNames.length} student names');

      setState(() {
        _monthlyData = monthlyGroups;
        _availableMonths = months;
        _selectedMonth = months.isNotEmpty ? months.first : '';
        _studentNames = studentNames;
        _isLoading = false;
      });
      
      print('\n=== STATE UPDATED ===');
      print('Selected month: $_selectedMonth');
      print('Available months count: ${_availableMonths.length}');
      print('Monthly data keys: ${_monthlyData.keys.toList()}');
      print('=== END LOADING ATTENDANCE DATA ===\n');
      
    } catch (e) {
      print('✗ ERROR in _loadAttendanceData: $e');
      print('Stack trace: ${StackTrace.current}');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadClasses() async {
    setState(() => _isLoadingClasses = true);
    
    try {
      final classesQuery = await FirebaseFirestore.instance.collection('classes').get();
      final classes = classesQuery.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'name': '${data['grade'] ?? ''} ${data['class_name'] ?? ''}'.trim(),
          'data': data,
        };
      }).toList();
      
      // Sort classes by name
      classes.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      
      setState(() {
        _availableClasses = classes;
        _isLoadingClasses = false;
      });
      
      print('Loaded ${classes.length} classes for admin filtering');
    } catch (e) {
      print('Error loading classes: $e');
      setState(() => _isLoadingClasses = false);
    }
  }

  String _getMonthDisplay(DateTime date) {
    final months = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    print('\n=== BUILD METHOD ===');
    print('Is loading: $_isLoading');
    print('Available months: ${_availableMonths.length}');
    print('Selected month: $_selectedMonth');
    print('Monthly data keys: ${_monthlyData.keys.toList()}');
    print('=== END BUILD METHOD ===\n');
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Presensi'),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: _buildTimetableView(),
    );
  }

  Widget _buildTimetableView() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_availableMonths.isEmpty) {
      return const Center(child: Text('Tidak ada data presensi.'));
    }

    return Column(
      children: [
        // Class filter (admin only)
        if (widget.role == 'admin')
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text('Kelas: ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String?>(
                    value: _selectedClassId,
                    isExpanded: true,
                    hint: const Text('Semua Kelas'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Semua Kelas'),
                      ),
                      ..._availableClasses.map((classData) => DropdownMenuItem<String?>(
                        value: classData['id'] as String,
                        child: Text(classData['name'] as String),
                      )).toList(),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedClassId = value;
                      });
                      _loadAttendanceData(); // Reload data with new filter
                    },
                  ),
                ),
              ],
            ),
          ),
        
        // Month selector
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text('Bulan: ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  value: _selectedMonth,
                  isExpanded: true,
                  items: _availableMonths.map((month) {
                    final date = DateTime.parse('$month-01');
                    return DropdownMenuItem(
                      value: month,
                      child: Text(_getMonthDisplay(date)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedMonth = value!;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
        
        // Timetable
        Expanded(
          child: _buildTimetable(),
        ),
      ],
    );
  }

  Widget _buildTimetable() {
    print('\n=== BUILDING TIMETABLE ===');
    print('Selected month: $_selectedMonth');
    print('Monthly data keys: ${_monthlyData.keys.toList()}');
    
    if (_selectedMonth.isEmpty || !_monthlyData.containsKey(_selectedMonth)) {
      print('✗ No data for selected month');
      return const Center(child: Text('Tidak ada data untuk bulan ini.'));
    }

    final monthData = _monthlyData[_selectedMonth]!;
    print('Month data count: ${monthData.length}');
    
    // Get all unique dates in this month
    final dates = <DateTime>[];
    final dateAttendanceMap = <DateTime, Map<String, dynamic>>{};
    
    print('\n--- Processing dates ---');
    for (var attendance in monthData) {
      final date = attendance['date'] as DateTime;
      final dayStart = DateTime(date.year, date.month, date.day);
      if (!dates.contains(dayStart)) {
        dates.add(dayStart);
        print('  Added date: $dayStart');
      }
      dateAttendanceMap[dayStart] = attendance;
    }
    
    dates.sort();
    print('Unique dates found: ${dates.length}');
    print('Dates: ${dates.map((d) => '${d.day}').toList()}');
    
    // Get all unique students
    final students = <String, String>{}; // studentId -> studentName
    print('\n--- Processing students ---');
    for (var attendance in monthData) {
      final data = attendance['data'] as Map<String, dynamic>;
      final studentIds = List<String>.from(data['student_ids'] ?? []);
      print('  Attendance ${attendance['id']}: ${studentIds.length} students');
      
      for (var studentId in studentIds) {
        if (!students.containsKey(studentId)) {
          print('    New student: $studentId');
          // Use stored student name
          final studentName = _studentNames[studentId] ?? 'Unknown';
          students[studentId] = studentName;
          print('    Student name: $studentName');
        }
      }
    }
    
    print('Total unique students: ${students.length}');
    print('Student IDs: ${students.keys.toList()}');
    print('=== END BUILDING TIMETABLE ===\n');

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 8,
          dataRowHeight: 50,
          headingRowHeight: 60,
          columns: [
            const DataColumn(
              label: Expanded(
                child: Text(
                  'Nama Siswa',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            ...dates.map((date) => DataColumn(
              label: Expanded(
                child: Text(
                  '${date.day}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            )).toList(),
            const DataColumn(
              label: Expanded(
                child: Text(
                  'S',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const DataColumn(
              label: Expanded(
                child: Text(
                  'I',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const DataColumn(
              label: Expanded(
                child: Text(
                  'A',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const DataColumn(
              label: Expanded(
                child: Text(
                  'H',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
          rows: students.entries.map((studentEntry) {
            final studentId = studentEntry.key;
            final studentName = studentEntry.value;
            
            // Calculate totals for this student
            int sakitCount = 0, izinCount = 0, alfaCount = 0, hadirCount = 0;
            
            return DataRow(
              cells: [
                DataCell(
                  Text(
                    studentName,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                ...dates.map((date) {
                  final attendance = dateAttendanceMap[date];
                  String status = '';
                  Color statusColor = Colors.transparent;
                  
                  if (attendance != null) {
                    final attendanceMap = Map<String, String>.from(attendance['data']['attendance'] ?? {});
                    status = attendanceMap[studentId] ?? '';
                    
                    switch (status) {
                      case 'hadir':
                        statusColor = Colors.green.shade100;
                        hadirCount++;
                        break;
                      case 'sakit':
                        statusColor = Colors.orange.shade100;
                        sakitCount++;
                        break;
                      case 'izin':
                        statusColor = Colors.blue.shade100;
                        izinCount++;
                        break;
                      case 'alfa':
                        statusColor = Colors.red.shade100;
                        alfaCount++;
                        break;
                    }
                  }
                  
                  return DataCell(
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: Text(
                          _getStatusInitial(status),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _getStatusColor(status),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
                DataCell(
                  Text(
                    sakitCount.toString(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                DataCell(
                  Text(
                    izinCount.toString(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                DataCell(
                  Text(
                    alfaCount.toString(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                DataCell(
                  Text(
                    hadirCount.toString(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  String _getStatusInitial(String status) {
    switch (status) {
      case 'hadir': return 'H';
      case 'sakit': return 'S';
      case 'izin': return 'I';
      case 'alfa': return 'A';
      default: return '';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'hadir': return Colors.green;
      case 'sakit': return Colors.orange;
      case 'izin': return Colors.blue;
      case 'alfa': return Colors.red;
      default: return Colors.grey;
    }
  }

  Future<String> _loadStudentName(String studentId) async {
    print('Loading student name for ID: $studentId');
    try {
      final doc = await FirebaseFirestore.instance.collection('students').doc(studentId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final name = data['name'] ?? 'Unknown';
        print('  Found student: $name');
        return name;
      } else {
        print('  Student document not found: $studentId');
      }
    } catch (e) {
      print('  Error loading student name: $e');
    }
    print('  Returning: Unknown');
    return 'Unknown';
  }

  Widget _buildListView() {
    Query attendanceQuery = FirebaseFirestore.instance.collection('attendances').orderBy('date', descending: true);
    if (widget.role != 'admin') {
      attendanceQuery = attendanceQuery.where('teacher_id', isEqualTo: widget.userInfo['nuptk']);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: attendanceQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('Tidak ada data presensi.'));
        }
        
        final attendances = snapshot.data!.docs;
        return ListView.builder(
          itemCount: attendances.length,
          itemBuilder: (context, index) {
            final doc = attendances[index];
            final data = doc.data() as Map<String, dynamic>;
            final classId = data['class_id'] ?? '-';
            final teacherId = data['teacher_id'] ?? '-';
            final date = (data['date'] as Timestamp?)?.toDate();
            final dateStr = date != null ? '${date.day}/${date.month}/${date.year}' : '-';
            final summary = _attendanceSummary(data['attendance'] as Map?);
            
            return FutureBuilder<Map<String, String>>(
              future: _getClassAndTeacherInfo(classId, teacherId),
              builder: (context, snapshot) {
                final kelas = snapshot.data?['kelas'] ?? classId;
                final guru = snapshot.data?['guru'] ?? teacherId;
                
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    title: Text('Kelas: $kelas'),
                    subtitle: Text('Tanggal: $dateStr\nGuru: $guru\n$summary'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AttendanceDetailScreen(
                            attendanceData: data,
                            attendanceId: doc.id,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _attendanceSummary(Map? attendance) {
    if (attendance == null) return '';
    final counts = <String, int>{'hadir': 0, 'sakit': 0, 'izin': 0, 'alfa': 0};
    attendance.forEach((_, status) {
      if (counts.containsKey(status)) counts[status] = counts[status]! + 1;
    });
    return 'Hadir: ${counts['hadir']}, Sakit: ${counts['sakit']}, Izin: ${counts['izin']}, Alfa: ${counts['alfa']}';
  }

  Future<Map<String, String>> _getClassAndTeacherInfo(String classId, String teacherId) async {
    String kelas = classId;
    String guru = teacherId;
    try {
      // Get class info
      final classDoc = await FirebaseFirestore.instance.collection('classes').doc(classId).get();
      if (classDoc.exists) {
        final classData = classDoc.data() as Map<String, dynamic>;
        final grade = classData['grade'] ?? '';
        final className = classData['class_name'] ?? '';
        kelas = '$grade$className';
      }
      // Get teacher info
      final teacherQuery = await FirebaseFirestore.instance.collection('teachers').where('nuptk', isEqualTo: teacherId).limit(1).get();
      if (teacherQuery.docs.isNotEmpty) {
        final teacherData = teacherQuery.docs.first.data() as Map<String, dynamic>;
        guru = teacherData['name'] ?? teacherId;
      }
    } catch (_) {}
    return {'kelas': kelas, 'guru': guru};
  }
} 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'attendance_detail_screen.dart';
import 'package:excel/excel.dart';

// Helper class for timetable columns
class _TimetableColumn {
  final DateTime date;
  final String? teacherName;
  final Map<String, dynamic>? attendance;
  final String? type;
  _TimetableColumn({required this.date, this.teacherName, this.attendance, this.type});
}

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
  
  // Attendance type filtering (admin only)
  String? _selectedAttendanceType; // 'morning', 'subject', or null for all
  Map<String, String> _teacherNames = {}; // teacherId -> teacherName

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
      // First, let's check what attendance records exist without any filters
      print('=== DEBUGGING: Checking all attendance records ===');
      final allAttendanceQuery = FirebaseFirestore.instance.collection('attendances');
      final allSnapshot = await allAttendanceQuery.get();
      print('Total attendance records in database: ${allSnapshot.docs.length}');
      
      for (var i = 0; i < allSnapshot.docs.length; i++) {
        final doc = allSnapshot.docs[i];
        final data = doc.data() as Map<String, dynamic>;
        print('Record ${i + 1}: ${doc.id}');
        print('  school_id: ${data['school_id']}');
        print('  teacher_id: ${data['teacher_id']}');
        print('  class_id: ${data['class_id']}');
        print('  date: ${data['date']}');
      }
      
      Query attendanceQuery = FirebaseFirestore.instance.collection('attendances').orderBy('date', descending: true);
      
      if (widget.role == 'admin') {
        print('Loading all attendance data (admin mode)');
        print('Admin school_id: ${widget.userInfo['school_id']}');
        
        // For admin, get all records and filter manually to avoid index issues
        attendanceQuery = FirebaseFirestore.instance.collection('attendances');
        print('Getting all attendance records for manual filtering');
      } else {
        // For teachers, filter by teacher_id (which already includes school_id from login)
        attendanceQuery = attendanceQuery.where('teacher_id', isEqualTo: widget.userInfo['nuptk']);
        print('Filtering by teacher NUPTK: ${widget.userInfo['nuptk']}');
      }

      print('Executing Firestore query...');
      final snapshot = await attendanceQuery.get();
      print('Query completed. Found ${snapshot.docs.length} attendance records');
      
      final attendances = snapshot.docs;
      
      // For admin users, filter old records that don't have school_id by checking teacher's school_id
      List<QueryDocumentSnapshot> filteredAttendances = attendances;
      if (widget.role == 'admin') {
        print('=== FILTERING OLD RECORDS BY TEACHER SCHOOL_ID ===');
        print('Admin school_id: ${widget.userInfo['school_id']}');
        print('Selected class_id: $_selectedClassId');
        print('Total records to filter: ${attendances.length}');
        filteredAttendances = [];
        
        for (var doc in attendances) {
          final data = doc.data() as Map<String, dynamic>;
          final schoolId = data['school_id'];
          final classId = data['class_id'];
          final teacherId = data['teacher_id'];
          
          print('\n--- Processing record ${doc.id} ---');
          print('  school_id: $schoolId');
          print('  class_id: $classId');
          print('  teacher_id: $teacherId');
          
          // If class filter is applied, check if this record matches the selected class
          if (_selectedClassId != null && classId != _selectedClassId) {
            print('✗ Record ${doc.id}: class_id mismatch (${classId} vs ${_selectedClassId})');
            continue;
          }
          
          // Check attendance type filter
          if (_selectedAttendanceType != null) {
            final scheduleId = data['schedule_id'] as String?;
            if (scheduleId != null) {
              try {
                final scheduleDoc = await FirebaseFirestore.instance
                    .collection('schedules')
                    .doc(scheduleId)
                    .get();
                
                if (scheduleDoc.exists) {
                  final scheduleData = scheduleDoc.data() as Map<String, dynamic>;
                  final scheduleType = scheduleData['schedule_type'] as String? ?? 'subject_specific';
                  
                  if (_selectedAttendanceType == 'morning' && scheduleType != 'daily_morning') {
                    print('✗ Record ${doc.id}: not morning attendance (${scheduleType})');
                    continue;
                  } else if (_selectedAttendanceType == 'subject' && scheduleType != 'subject_specific') {
                    print('✗ Record ${doc.id}: not subject attendance (${scheduleType})');
                    continue;
                  }
                } else {
                  print('✗ Record ${doc.id}: schedule not found (${scheduleId})');
                  continue;
                }
              } catch (e) {
                print('✗ Record ${doc.id}: error checking schedule type: $e');
                continue;
              }
            } else {
              print('✗ Record ${doc.id}: no schedule_id found');
              continue;
            }
          }
          
          if (schoolId != null) {
            // Record has school_id, check if it matches admin's school
            if (schoolId == widget.userInfo['school_id']) {
              filteredAttendances.add(doc);
              print('✓ Record ${doc.id}: school_id matches (${schoolId})');
            } else {
              print('✗ Record ${doc.id}: school_id mismatch (${schoolId} vs ${widget.userInfo['school_id']})');
            }
          } else {
            // Record doesn't have school_id, check teacher's school_id
            if (teacherId != null) {
              try {
                print('  Checking teacher school_id for teacher: $teacherId');
                final teacherDoc = await FirebaseFirestore.instance
                    .collection('teachers')
                    .where('nuptk', isEqualTo: teacherId)
                    .get();
                
                print('  Teacher query found ${teacherDoc.docs.length} documents');
                
                if (teacherDoc.docs.isNotEmpty) {
                  final teacherData = teacherDoc.docs.first.data();
                  final teacherSchoolId = teacherData['school_id'];
                  final teacherName = teacherData['name'];
                  
                  print('  Teacher name: $teacherName');
                  print('  Teacher school_id: $teacherSchoolId');
                  
                  if (teacherSchoolId == widget.userInfo['school_id']) {
                    filteredAttendances.add(doc);
                    print('✓ Record ${doc.id}: teacher school_id matches (${teacherSchoolId})');
                  } else {
                    print('✗ Record ${doc.id}: teacher school_id mismatch (${teacherSchoolId} vs ${widget.userInfo['school_id']})');
                  }
                } else {
                  print('✗ Record ${doc.id}: teacher not found (${teacherId})');
                }
              } catch (e) {
                print('✗ Record ${doc.id}: error checking teacher school_id: $e');
              }
            } else {
              print('✗ Record ${doc.id}: no teacher_id found');
            }
          }
        }
        
        print('\n=== FILTERING SUMMARY ===');
        print('Original records: ${attendances.length}');
        print('Filtered records: ${filteredAttendances.length}');
        print('Records excluded: ${attendances.length - filteredAttendances.length}');
      }
      
      if (filteredAttendances.isEmpty) {
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
      for (var i = 0; i < filteredAttendances.length; i++) {
        final doc = filteredAttendances[i];
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

      // Load all teacher names
      print('\n--- Loading teacher names ---');
      final teacherNames = <String, String>{};
      final allTeacherIds = <String>{};
      
      for (var monthData in monthlyGroups.values) {
        for (var attendance in monthData) {
          final data = attendance['data'] as Map<String, dynamic>;
          final teacherId = data['teacher_id'] as String?;
          if (teacherId != null) {
            allTeacherIds.add(teacherId);
          }
        }
      }
      
      print('Found ${allTeacherIds.length} unique teacher IDs: ${allTeacherIds.toList()}');
      
      // Load all teacher names in parallel
      final teacherNameFutures = allTeacherIds.map((teacherId) async {
        final name = await _loadTeacherName(teacherId);
        return MapEntry(teacherId, name);
      });
      
      final teacherNameResults = await Future.wait(teacherNameFutures);
      for (var entry in teacherNameResults) {
        teacherNames[entry.key] = entry.value;
      }
      
      print('Loaded ${teacherNames.length} teacher names');

      setState(() {
        _monthlyData = monthlyGroups;
        _availableMonths = months;
        _selectedMonth = months.isNotEmpty ? months.first : '';
        _studentNames = studentNames;
        _teacherNames = teacherNames;
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
      final classesQuery = await FirebaseFirestore.instance
          .collection('classes')
          .where('school_id', isEqualTo: widget.userInfo['school_id'])
          .get();
      
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
      
      print('Loaded ${classes.length} classes for school: ${widget.userInfo['school_id']}');
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Presensi'),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              color: Colors.grey[100],
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Filters Section
                  if (widget.role == 'admin') ...[
                    Card(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Filter', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.class_, size: 20, color: Colors.teal),
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
                                      _loadAttendanceData();
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.event_note, size: 20, color: Colors.teal),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButton<String?>(
                                    value: _selectedAttendanceType,
                                    isExpanded: true,
                                    hint: const Text('Semua Jenis'),
                                    items: [
                                      const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text('Semua Jenis'),
                                      ),
                                      const DropdownMenuItem<String>(
                                        value: 'morning',
                                        child: Text('Presensi Pagi'),
                                      ),
                                      const DropdownMenuItem<String>(
                                        value: 'subject',
                                        child: Text('Presensi Mata Pelajaran'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedAttendanceType = value;
                                      });
                                      _loadAttendanceData();
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  // Month Selector & Export
                  Card(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 20, color: Colors.teal),
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
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            onPressed: _exportToExcel,
                            icon: const Icon(Icons.download),
                            label: const Text('Export Excel'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Legend (admin only)
                  if (widget.role == 'admin' && _selectedAttendanceType != 'subject')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          const Text('Keterangan:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Pagi',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text('= Presensi Pagi', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Mata Pelajaran',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text('= Presensi Mata Pelajaran', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  // Timetable Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: SizedBox(
                          height: 500,
                          child: FutureBuilder<Widget>(
                            future: _buildTimetable(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: CircularProgressIndicator());
                              }
                              return snapshot.data ?? const Center(child: Text('Tidak ada data untuk bulan ini.'));
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
        
        // Attendance type filter (admin only)
        if (widget.role == 'admin')
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text('Jenis Presensi: ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String?>(
                    value: _selectedAttendanceType,
                    isExpanded: true,
                    hint: const Text('Semua Jenis'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Semua Jenis'),
                      ),
                      const DropdownMenuItem<String>(
                        value: 'morning',
                        child: Text('Presensi Pagi'),
                      ),
                      const DropdownMenuItem<String>(
                        value: 'subject',
                        child: Text('Presensi Mata Pelajaran'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedAttendanceType = value;
                      });
                      _loadAttendanceData(); // Reload data with new filter
                    },
                  ),
                ),
              ],
            ),
          ),
        
        // Month selector and export button
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
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _exportToExcel,
                icon: const Icon(Icons.download),
                label: const Text('Export Excel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        
        // Legend (admin only) - only show when subject filter is not applied
        if (widget.role == 'admin' && _selectedAttendanceType != 'subject')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                const Text('Keterangan: ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Pagi',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('= Presensi Pagi', style: TextStyle(fontSize: 12)),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Mata Pelajaran',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('= Presensi Mata Pelajaran', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        
        // Timetable
        Expanded(
          child: FutureBuilder<Widget>(
            future: _buildTimetable(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              return snapshot.data ?? const Center(child: Text('Tidak ada data untuk bulan ini.'));
            },
          ),
        ),
      ],
    );
  }

  Future<Widget> _buildTimetable() async {
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
    final dateTeacherMap = <DateTime, String>{}; // date -> teacher name
    final dateTypeMap = <DateTime, String>{}; // date -> attendance type
    
    print('\n--- Processing dates ---');
    for (var attendance in monthData) {
      final date = attendance['date'] as DateTime;
      final dayStart = DateTime(date.year, date.month, date.day);
      if (!dates.contains(dayStart)) {
        dates.add(dayStart);
        print('  Added date: $dayStart');
      }
      dateAttendanceMap[dayStart] = attendance;
      
      // Get teacher name for this attendance
      final data = attendance['data'] as Map<String, dynamic>;
      final teacherId = data['teacher_id'] as String?;
      if (teacherId != null) {
        final teacherName = _teacherNames[teacherId] ?? 'Unknown';
        dateTeacherMap[dayStart] = teacherName;
        print('  Teacher for ${dayStart}: $teacherName');
      }
      
      // Get attendance type for this attendance
      final scheduleId = data['schedule_id'] as String?;
      if (scheduleId != null) {
        try {
          final scheduleDoc = await FirebaseFirestore.instance
              .collection('schedules')
              .doc(scheduleId)
              .get();
          
          if (scheduleDoc.exists) {
            final scheduleData = scheduleDoc.data() as Map<String, dynamic>;
            final scheduleType = scheduleData['schedule_type'] as String? ?? 'subject_specific';
            final attendanceType = scheduleType == 'daily_morning' ? 'Pagi' : 'Mata Pelajaran';
            dateTypeMap[dayStart] = attendanceType;
            print('  Attendance type for ${dayStart}: $attendanceType');
          }
        } catch (e) {
          print('  Error getting attendance type for ${dayStart}: $e');
          dateTypeMap[dayStart] = 'Unknown';
        }
      }
    }
    
    dates.sort();
    print('Unique dates found: ${dates.length}');
    print('Dates: ${dates.map((d) => '${d.day}').toList()}');
    
    // --- Build a map: date -> list of attendance records (for multi-teacher per date) ---
    final Map<DateTime, List<Map<String, dynamic>>> dateToAttendances = {};
    for (var attendance in monthData) {
      final date = attendance['date'] as DateTime;
      final dayStart = DateTime(date.year, date.month, date.day);
      dateToAttendances.putIfAbsent(dayStart, () => []).add(attendance);
    }
    final datesForTimetable = dateToAttendances.keys.toList()..sort();
    // --- Build columns: for each date, one column per teacher (if admin) ---
    List<_TimetableColumn> timetableColumns = [];
    for (final date in datesForTimetable) {
      final attendances = dateToAttendances[date]!;
      if (widget.role == 'admin' && attendances.length > 1) {
        // Multiple teachers: one column per teacher
        attendances.sort((a, b) {
          final tA = _teacherNames[(a['data'] as Map<String, dynamic>)['teacher_id']] ?? '';
          final tB = _teacherNames[(b['data'] as Map<String, dynamic>)['teacher_id']] ?? '';
          return tA.compareTo(tB);
        });
        for (var att in attendances) {
          final teacherId = (att['data'] as Map<String, dynamic>)['teacher_id'] as String?;
          final teacherName = teacherId != null ? _teacherNames[teacherId] ?? 'Unknown' : 'Unknown';
          final type = (() {
            final scheduleId = (att['data'] as Map<String, dynamic>)['schedule_id'] as String?;
            if (scheduleId != null) {
              final scheduleType = dateTypeMap[date] ?? '';
              return scheduleType;
            }
            return '';
          })();
          timetableColumns.add(_TimetableColumn(date: date, teacherName: teacherName, attendance: att, type: type));
        }
      } else {
        // Single teacher or not admin: one column per date
        final att = attendances.first;
        final teacherId = (att['data'] as Map<String, dynamic>)['teacher_id'] as String?;
        final teacherName = teacherId != null ? _teacherNames[teacherId] ?? 'Unknown' : 'Unknown';
        final type = (() {
          final scheduleId = (att['data'] as Map<String, dynamic>)['schedule_id'] as String?;
          if (scheduleId != null) {
            final scheduleType = dateTypeMap[date] ?? '';
            return scheduleType;
          }
          return '';
        })();
        timetableColumns.add(_TimetableColumn(date: date, teacherName: teacherName, attendance: att, type: type));
      }
    }
    // --- Build students list as before ---
    final students = <String, String>{};
    for (var attendance in monthData) {
      final data = attendance['data'] as Map<String, dynamic>;
      final studentIds = List<String>.from(data['student_ids'] ?? []);
      final classId = data['class_id'];
      if (_selectedClassId != null && classId != _selectedClassId) continue;
      for (var studentId in studentIds) {
        if (!students.containsKey(studentId)) {
          final studentName = _studentNames[studentId] ?? 'Unknown';
          students[studentId] = studentName;
        }
      }
    }
    // --- Build DataTable ---
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
            ...timetableColumns.map((col) => DataColumn(
              label: Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${col.date.day}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    if (widget.role == 'admin')
                      Text(
                        col.teacherName ?? '',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.normal,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (widget.role == 'admin' && col.type != null && col.type!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: col.type == 'Pagi' ? Colors.blue.shade100 : Colors.green.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          col.type ?? '',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: col.type == 'Pagi' ? Colors.blue.shade800 : Colors.green.shade800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            )),
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
            int sakitCount = 0, izinCount = 0, alfaCount = 0, hadirCount = 0;
            return DataRow(
              cells: [
                DataCell(
                  Text(
                    studentName,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                ...timetableColumns.map((col) {
                  final attendance = col.attendance;
                  String status = '';
                  Color statusColor = Colors.transparent;
                  if (attendance != null) {
                    final attendanceMap = Map<String, String>.from((attendance['data'] as Map<String, dynamic>)['attendance'] ?? {});
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
                      alignment: Alignment.center, // Ensure centering
                      child: Center(
                        child: Text(
                          _getStatusInitial(status),
                          textAlign: TextAlign.center, // Center text horizontally
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
    try {
      final doc = await FirebaseFirestore.instance.collection('students').doc(studentId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        return data['name'] as String? ?? 'Unknown';
      }
    } catch (e) {
      print('Error loading student name for $studentId: $e');
    }
    return 'Unknown';
  }

  Future<String> _loadTeacherName(String teacherId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('teachers')
          .where('nuptk', isEqualTo: teacherId)
          .get();
      if (doc.docs.isNotEmpty) {
        final data = doc.docs.first.data();
        return data['name'] as String? ?? 'Unknown';
      }
    } catch (e) {
      print('Error loading teacher name for $teacherId: $e');
    }
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

  Future<void> _exportToExcel() async {
    if (_selectedMonth.isEmpty || !_monthlyData.containsKey(_selectedMonth)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada data untuk diekspor'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      final monthData = _monthlyData[_selectedMonth]!;
      final dates = <DateTime>[];
      final dateAttendanceMap = <DateTime, Map<String, dynamic>>{};
      for (var attendance in monthData) {
        final date = attendance['date'] as DateTime;
        final dayStart = DateTime(date.year, date.month, date.day);
        if (!dates.contains(dayStart)) {
          dates.add(dayStart);
        }
        dateAttendanceMap[dayStart] = attendance;
      }
      dates.sort();
      final students = <String, String>{};
      for (var attendance in monthData) {
        final data = attendance['data'] as Map<String, dynamic>;
        final studentIds = List<String>.from(data['student_ids'] ?? []);
        final classId = data['class_id'];
        if (_selectedClassId != null && classId != _selectedClassId) {
          continue;
        }
        for (var studentId in studentIds) {
          if (!students.containsKey(studentId)) {
            final studentName = _studentNames[studentId] ?? 'Unknown';
            students[studentId] = studentName;
          }
        }
      }
      final excel = Excel.createExcel();
      final sheet = excel['Presensi'];
      List<String> headerRow = ['Nama Siswa'];
      for (var date in dates) {
        headerRow.add('${date.day}/${date.month}/${date.year}');
      }
      headerRow.addAll(['Sakit', 'Izin', 'Alfa', 'Hadir']);
      final headerStyle = CellStyle(
        backgroundColorHex: '#1976D2', // Blue
        fontColorHex: '#FFFFFF',
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
        fontFamily: getFontFamily(FontFamily.Arial),
      );
      // Row styles
      final rowStyle1 = CellStyle(
        backgroundColorHex: '#E3F2FD', // Light blue
        horizontalAlign: HorizontalAlign.Center,
        fontFamily: getFontFamily(FontFamily.Arial),
      );
      final rowStyle2 = CellStyle(
        backgroundColorHex: '#FFFFFF', // White
        horizontalAlign: HorizontalAlign.Center,
        fontFamily: getFontFamily(FontFamily.Arial),
      );
      // Write header
      for (int col = 0; col < headerRow.length; col++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
        cell.value = headerRow[col];

      }
      // Data rows
      int rowIdx = 1;
      for (var studentEntry in students.entries) {
        final studentId = studentEntry.key;
        final studentName = studentEntry.value;
        int sakitCount = 0, izinCount = 0, alfaCount = 0, hadirCount = 0;
        final style = rowIdx % 2 == 0 ? rowStyle1 : rowStyle2;
        // Student name (left aligned)
        var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx));
        cell.value = studentName;
        // Attendance per date
        for (int d = 0; d < dates.length; d++) {
          final date = dates[d];
          final attendance = dateAttendanceMap[date];
          String status = '';
          if (attendance != null) {
            final attendanceMap = Map<String, String>.from(attendance['data']['attendance'] ?? {});
            status = attendanceMap[studentId] ?? '';
            switch (status) {
              case 'hadir': hadirCount++; break;
              case 'sakit': sakitCount++; break;
              case 'izin': izinCount++; break;
              case 'alfa': alfaCount++; break;
            }
          }
          var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: d + 1, rowIndex: rowIdx));
          cell.value = status.isEmpty ? '' : status.toUpperCase();
          cell.cellStyle = style;
        }
        // Totals
        final totals = [sakitCount, izinCount, alfaCount, hadirCount];
        for (int t = 0; t < totals.length; t++) {
          var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: dates.length + 1 + t, rowIndex: rowIdx));
          cell.value = totals[t];
          cell.cellStyle = style;
        }
        rowIdx++;
      }
      for (int col = 0; col < headerRow.length; col++) {
        sheet.setColAutoFit(col);
      }
      final directory = await getTemporaryDirectory();
      final fileName = 'presensi_${_selectedMonth.replaceAll('-', '_')}.xlsx';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(excel.encode()!);
      Navigator.of(context).pop();
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Data Presensi ${_getMonthDisplay(DateTime.parse('$_selectedMonth-01'))}',
      );
    } catch (e) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengekspor Excel: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
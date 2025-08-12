import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'login_screen.dart';
import '../services/local_storage_service.dart';
import '../services/offline_sync_service.dart';
import '../services/connectivity_service.dart';
import 'admin_students_screen.dart'; // Added import for AdminStudentsScreen

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
  String? scheduleType;
  String? scheduleSubject;
  String? scheduleTime;
  bool isLoading = true;
  Map<String, String> attendance = {};
  String? errorMsg;
  bool attendanceExistsToday = false;
  String? attendanceDocId;
  String? currentYearId;
  bool canEdit = false;
  DateTime? _scheduleEndTime;
  List<Map<String, dynamic>> _currentSchedules = [];
  List<String> _currentScheduleIds = [];
  int _activeScheduleIndex = 0;
  Map<String, String> _classDisplayById = {};

  @override
  void initState() {
    super.initState();
    _loadScheduleAndStudents();
  }

  Future<void> _loadScheduleAndStudents() async {
    setState(() { isLoading = true; errorMsg = null; });
    try {
      final now = DateTime.now();
      final nuptk = widget.userInfo?['nuptk'] ?? '';
      
      print('=== ATTENDANCE SCREEN DEBUG ===');
      print('Current time: ${now.toString()}');
      print('Current weekday: ${now.weekday} (${_weekdayToIndo(now.weekday)})');
      print('Teacher NUPTK: $nuptk');
      print('Complete userInfo: ${widget.userInfo}');

      // Get current school year (latest by start_date)
      final yearQuery = await FirebaseFirestore.instance
          .collection('school_years')
          .orderBy('start_date', descending: true)
          .limit(1)
          .get();
      if (yearQuery.docs.isNotEmpty) {
        currentYearId = yearQuery.docs.first.id;
        print('Current year ID: $currentYearId');
      } else {
        print('WARNING: No school year found!');
      }
      if (currentYearId == null) {
        setState(() {
          isLoading = false;
          errorMsg = 'Tahun ajaran belum diatur.';
        });
        return;
      }

      // First, try to find the teacher document by NUPTK
      String? teacherDocId;
      if (nuptk.isNotEmpty) {
        final teacherQuery = await FirebaseFirestore.instance
            .collection('teachers')
            .where('nuptk', isEqualTo: nuptk)
            .limit(1)
            .get();
        
        if (teacherQuery.docs.isNotEmpty) {
          teacherDocId = teacherQuery.docs.first.id;
          print('Found teacher document ID: $teacherDocId for NUPTK: $nuptk');
        } else {
          print('WARNING: No teacher found with NUPTK: $nuptk');
        }
      }

      // Get all schedules for this teacher (try both NUPTK and document ID)
      Query scheduleQuery;
      if (teacherDocId != null) {
        scheduleQuery = FirebaseFirestore.instance
            .collection('schedules')
            .where('teacher_id', isEqualTo: teacherDocId);
        print('Searching schedules by teacher document ID: $teacherDocId');
      } else {
        scheduleQuery = FirebaseFirestore.instance
            .collection('schedules')
            .where('teacher_id', isEqualTo: nuptk);
        print('Searching schedules by NUPTK: $nuptk');
      }

      final scheduleSnapshot = await scheduleQuery.get();
      print('Found ${scheduleSnapshot.docs.length} schedules for teacher');

      Map<String, dynamic>? foundSchedule;
      String? foundScheduleId;
      DateTime? nearestTime;
      Map<String, dynamic>? nearestSchedule;

      // New: collect all schedules that are currently active
      _currentSchedules = [];
      _currentScheduleIds = [];

      for (var doc in scheduleSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final scheduleType = data['schedule_type'] ?? 'subject_specific';
        
        if (scheduleType == 'daily_morning') {
          final currentTime = now.hour * 60 + now.minute;
          final morningTime = 6 * 60 + 30;
          final morningEndTime = 12 * 60 + 30;
          
          if (currentTime >= morningTime && currentTime <= morningEndTime) {
            _currentSchedules.add(data);
            _currentScheduleIds.add(doc.id);
            foundSchedule ??= data;
            foundScheduleId ??= doc.id;
                _scheduleEndTime = DateTime(now.year, now.month, now.day, 12, 30);
          }
        } else if (scheduleType == 'subject_specific') {
          if (data['time'] != null) {
            final timeString = data['time'].toString();
            print('Subject-specific check:');
            print('  Time string: $timeString');
            
            final regex = RegExp(r'([A-Za-z]+) (\d{2}):(\d{2})-(\d{2}):(\d{2})');
            final match = regex.firstMatch(timeString);
            if (match != null) {
              final dayStr = match.group(1)!;
              final startHour = int.parse(match.group(2)!);
              final startMinute = int.parse(match.group(3)!);
              final endHour = int.parse(match.group(4)!);
              final endMinute = int.parse(match.group(5)!);
              final targetWeekday = _indoToWeekday(dayStr);
              final nowMinutes = now.hour * 60 + now.minute;
              final startMinutes = startHour * 60 + startMinute;
              final endMinutes = endHour * 60 + endMinute;
              
              if (targetWeekday == now.weekday) {
                if (nowMinutes >= startMinutes && nowMinutes <= endMinutes) {
                  _currentSchedules.add(data);
                  _currentScheduleIds.add(doc.id);
                  foundSchedule ??= data;
                  foundScheduleId ??= doc.id;
                  _scheduleEndTime = DateTime(now.year, now.month, now.day, endHour, endMinute);
                } else if (startMinutes > nowMinutes) {
                  final scheduleDateTime = DateTime(now.year, now.month, now.day, startHour, startMinute);
                  if (nearestTime == null || scheduleDateTime.isBefore(nearestTime)) {
                    nearestTime = scheduleDateTime;
                    nearestSchedule = data;
                    print('    → Set as nearest schedule');
                  }
                }
              } else {
                int daysDiff = (targetWeekday - now.weekday) % 7;
                if (daysDiff < 0) daysDiff += 7;
                final scheduleDateTime = DateTime(now.year, now.month, now.day + daysDiff, startHour, startMinute);
                print('    Schedule is for another day (${daysDiff} days from now)');
                if (scheduleDateTime.isAfter(now)) {
                  if (nearestTime == null || scheduleDateTime.isBefore(nearestTime)) {
                    nearestTime = scheduleDateTime;
                    nearestSchedule = data;
                    print('    → Set as nearest schedule');
                  }
                }
              }
            } else {
              print('  ✗ Could not parse time string: $timeString');
            }
          } else {
            print('  ✗ No time data in schedule');
          }
        }
      }

      if (_currentSchedules.isEmpty && foundSchedule == null) {
        print('\n✗ NO SCHEDULE FOUND!');
        print('Nearest schedule: ${nearestSchedule != null ? nearestSchedule['time'] : 'None'}');
        
        setState(() {
          isLoading = false;
          errorMsg = 'Tidak ada jadwal mengajar untuk waktu ini.';
        });
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

      // Choose active index based on first found
      if (_currentSchedules.isEmpty && foundSchedule != null) {
        _currentSchedules.add(foundSchedule);
        _currentScheduleIds.add(foundScheduleId ?? '');
      }
      _activeScheduleIndex = 0;

      print('\n✓ SCHEDULE(S) FOUND! Count: ${_currentSchedules.length}');
      print('Active schedule index: $_activeScheduleIndex');

      // Preload class display names for all current schedules
      final classIdSet = _currentSchedules
          .map((s) => (s['class_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();
      _classDisplayById = await _fetchClassDisplayNames(classIdSet);

      final active = _currentSchedules[_activeScheduleIndex];
      classId = active['class_id'];
      scheduleId = _currentScheduleIds[_activeScheduleIndex];
      scheduleType = active['schedule_type'];
      scheduleSubject = active['subject'];
      scheduleTime = active['time'];
      // Determine editability
      if (_scheduleEndTime != null) {
        canEdit = DateTime.now().isBefore(_scheduleEndTime!) || DateTime.now().isAtSameMomentAs(_scheduleEndTime!);
      } else {
        canEdit = false;
      }

      // Check if attendance already exists for today
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      
      print('\n=== CHECKING EXISTING ATTENDANCE ===');
      print('Schedule ID: $scheduleId');
      print('Teacher ID (NUPTK): $nuptk');
      print('Date range: ${today.toIso8601String()} to ${tomorrow.toIso8601String()}');
      
      final attendanceQuery = await FirebaseFirestore.instance
        .collection('attendances')
        .where('schedule_id', isEqualTo: scheduleId)
        .where('teacher_id', isEqualTo: nuptk)
        .where('date', isGreaterThanOrEqualTo: today)
        .where('date', isLessThan: tomorrow)
        .limit(1)
        .get();
      
      print('Query result: Found ${attendanceQuery.docs.length} records');
      if (attendanceQuery.docs.isNotEmpty) {
        final doc = attendanceQuery.docs.first;
        print('Existing attendance data: ${doc.data()}');
      }
      print('=== END CHECKING EXISTING ATTENDANCE ===\n');
      
      if (attendanceQuery.docs.isNotEmpty) {
        attendanceExistsToday = true;
        attendanceDocId = attendanceQuery.docs.first.id;
        final attData = attendanceQuery.docs.first.data() as Map<String, dynamic>;
        final attMap = attData['attendance'] as Map?;
        if (attMap != null) {
          attendance = Map<String, String>.from(attMap);
        }
        print('✓ Attendance already exists for today');
      } else {
        // Try to load pending offline attendance for today
        final pendingList = await LocalStorageService.getPendingAttendance();
        final todayOnly = DateTime(now.year, now.month, now.day);
        Map<String, dynamic>? pendingMatch;
        for (final p in pendingList) {
          if ((p['schedule_id'] as String?) != scheduleId || (p['teacher_id'] as String?) != nuptk) continue;
          final pDate = p['date'];
          DateTime? pDay;
          if (pDate is DateTime) {
            pDay = DateTime(pDate.year, pDate.month, pDate.day);
          } else if (pDate is String) {
            try {
              final d = DateTime.parse(pDate);
              pDay = DateTime(d.year, d.month, d.day);
            } catch (_) {}
          }
          if (pDay != null && pDay == todayOnly) {
            pendingMatch = p;
            break;
          }
        }
        if (pendingMatch != null) {
          final attMap = pendingMatch['attendance'] as Map?;
          if (attMap != null) {
            attendance = Map<String, String>.from(attMap);
          }
          attendanceExistsToday = true;
          attendanceDocId = null;
          print('Loaded pending offline attendance for today');
        } else {
          attendanceExistsToday = false;
          attendanceDocId = null;
          print('No existing attendance found');
        }
      }

      // Load students for this class from the class document
      print('\nLoading students...');
      print('Loading class document: $classId');
      
      final classDoc = await FirebaseFirestore.instance.collection('classes').doc(classId).get();
      if (!classDoc.exists) {
        setState(() {
          isLoading = false;
          errorMsg = 'Kelas tidak ditemukan.';
        });
        return;
      }
      
      final classData = classDoc.data() as Map<String, dynamic>;
      final studentIds = List<String>.from(classData['students'] ?? []);
      
      print('Found ${studentIds.length} student IDs in class: $studentIds');
      
      if (studentIds.isEmpty) {
        setState(() {
          isLoading = false;
          errorMsg = 'Tidak ada siswa di kelas ini.';
        });
        return;
      }

      // Load student details (handle large classes with batch queries)
      List<QueryDocumentSnapshot> allStudentDocs = [];
      
      // Firestore whereIn has a limit of 10 items, so we need to batch the queries
      const batchSize = 10;
      for (int i = 0; i < studentIds.length; i += batchSize) {
        final end = (i + batchSize < studentIds.length) ? i + batchSize : studentIds.length;
        final batchIds = studentIds.sublist(i, end);
        
        print('Querying batch ${(i ~/ batchSize) + 1}: ${batchIds.length} students');
        
        final batchQuery = await FirebaseFirestore.instance
          .collection('students')
          .where(FieldPath.documentId, whereIn: batchIds)
          .get();
        
        allStudentDocs.addAll(batchQuery.docs);
      }

      print('Found ${allStudentDocs.length} students with details');

      final studentsList = allStudentDocs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();

      // Sort students alphabetically by name (case-insensitive), empty names last
      studentsList.sort((a, b) {
        final aName = (a['name'] as String? ?? '').trim();
        final bName = (b['name'] as String? ?? '').trim();
        if (aName.isEmpty && bName.isEmpty) return 0;
        if (aName.isEmpty) return 1;
        if (bName.isEmpty) return -1;
        return aName.toLowerCase().compareTo(bName.toLowerCase());
      });

      setState(() {
        students = studentsList;
        isLoading = false;
        className = '${classData['grade']}${classData['class_name'] ?? ''}';
      });
      
      print('✓ Attendance screen loaded successfully');
      print('Class name: $className');
      print('Student count: ${students.length}');
      print('=== END DEBUG ===\n');
      
    } catch (e) {
      print('✗ ERROR in attendance screen: $e');
      setState(() {
        isLoading = false;
        errorMsg = 'Error: $e';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Presensi'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        leading: widget.showBackButton ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ) : null,
        actions: [
          if (!isLoading && errorMsg == null && _currentSchedules.length > 1)
            PopupMenuButton<int>(
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Pilih jadwal',
              onSelected: (index) async {
                setState(() {
                  _activeScheduleIndex = index;
                  attendance = {};
                  attendanceExistsToday = false;
                  attendanceDocId = null;
                });
                await _reloadForActiveSchedule();
              },
              itemBuilder: (context) => List.generate(_currentSchedules.length, (i) {
                final s = _currentSchedules[i];
                final label = _scheduleLabel(s);
                return PopupMenuItem<int>(
                  value: i,
                  child: Row(
                    children: [
                      if (i == _activeScheduleIndex)
                        const Icon(Icons.check, color: Colors.teal)
                      else
                        const SizedBox(width: 24),
                      const SizedBox(width: 8),
                      Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                );
              }),
            ),
        ],
      ),
      body: isLoading
        ? const Center(child: CircularProgressIndicator())
        : errorMsg != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    Text(
                      errorMsg!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                // Schedule Info Card
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              color: Colors.teal[600],
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Informasi Jadwal',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal[600],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                           'Kelas: ${className ?? '-'}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Jenis: ${_getScheduleTypeDisplay()}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Waktu: ${_getScheduleTimeDisplay()}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                        if (attendanceExistsToday) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange[100],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              canEdit ? 'Presensi hari ini dapat diedit hingga ${_formattedEndTime()}' : 'Presensi untuk hari ini sudah ada',
                              style: TextStyle(
                                color: Colors.orange[800],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                
                // Quick Actions
                if (canEdit) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                for (var student in students) {
                                  attendance[student['id']] = 'hadir';
                                }
                              });
                            },
                            icon: const Icon(Icons.check_circle),
                            label: const Text('Hadir Semua'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Search bar that scrolls to matching student
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Cari siswa (nama)...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (query) {
                        _scrollToStudent(query);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                
                // Students List
                Expanded(
                  child: ListView.builder(
                    controller: _listController,
                    padding: const EdgeInsets.only(bottom: 80), // Add bottom padding for FAB
                    itemCount: students.length,
                    itemBuilder: (context, index) {
                      final s = students[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        key: _itemKeys.putIfAbsent(index, () => GlobalKey(debugLabel: 'student_$index')),
                        child: ListTile(
                          title: Text(s['name'] ?? 'Nama tidak tersedia'),
                          trailing: canEdit 
                            ? DropdownButton<String>(
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
                              )
                            : Text(
                                attendance[s['id']] ?? 'Tidak ada data',
                                style: TextStyle(
                                  color: _getAttendanceColor(attendance[s['id']]),
                                  fontWeight: FontWeight.w500,
                                ),
                              )
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: isLoading || errorMsg != null || !canEdit
        ? null
        : FloatingActionButton.extended(
            onPressed: _saveOrUpdateAttendance,
            icon: const Icon(Icons.save),
            label: Text(attendanceExistsToday ? 'Perbarui Presensi' : 'Simpan Presensi'),
            backgroundColor: Colors.teal,
          ),
    );
  }

  Future<void> _reloadForActiveSchedule() async {
    try {
      final active = _currentSchedules[_activeScheduleIndex];
      final now = DateTime.now();
      final nuptk = widget.userInfo?['nuptk'] ?? '';

      // Update state from active schedule
      setState(() {
        classId = active['class_id'];
        scheduleId = _currentScheduleIds[_activeScheduleIndex];
        scheduleType = active['schedule_type'];
        scheduleSubject = active['subject'];
        scheduleTime = active['time'];
      });

      // Determine end time if subject_specific
      _scheduleEndTime = null;
      if (scheduleType == 'subject_specific' && scheduleTime != null) {
        final regex = RegExp(r'(\d{2}):(\d{2})-(\d{2}):(\d{2})');
        final match = regex.firstMatch(scheduleTime!);
        if (match != null) {
          final endHour = int.parse(match.group(3)!);
          final endMinute = int.parse(match.group(4)!);
          _scheduleEndTime = DateTime(now.year, now.month, now.day, endHour, endMinute);
        }
      } else if (scheduleType == 'daily_morning') {
        _scheduleEndTime = DateTime(now.year, now.month, now.day, 12, 30);
      }
      canEdit = _scheduleEndTime != null && (DateTime.now().isBefore(_scheduleEndTime!) || DateTime.now().isAtSameMomentAs(_scheduleEndTime!));

      // Reload attendance existence for this schedule
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final attendanceQuery = await FirebaseFirestore.instance
          .collection('attendances')
          .where('schedule_id', isEqualTo: scheduleId)
          .where('teacher_id', isEqualTo: nuptk)
          .where('date', isGreaterThanOrEqualTo: today)
          .where('date', isLessThan: tomorrow)
          .limit(1)
          .get();
      if (attendanceQuery.docs.isNotEmpty) {
        attendanceExistsToday = true;
        attendanceDocId = attendanceQuery.docs.first.id;
        final attData = attendanceQuery.docs.first.data() as Map<String, dynamic>;
        final attMap = attData['attendance'] as Map?;
        if (attMap != null) {
          attendance = Map<String, String>.from(attMap);
        }
      } else {
        // Load pending offline attendance for today if exists
        final pendingList = await LocalStorageService.getPendingAttendance();
        final todayOnly = DateTime(now.year, now.month, now.day);
        Map<String, dynamic>? pendingMatch;
        for (final p in pendingList) {
          if ((p['schedule_id'] as String?) != scheduleId || (p['teacher_id'] as String?) != nuptk) continue;
          final pDate = p['date'];
          DateTime? pDay;
          if (pDate is DateTime) {
            pDay = DateTime(pDate.year, pDate.month, pDate.day);
          } else if (pDate is String) {
            try {
              final d = DateTime.parse(pDate);
              pDay = DateTime(d.year, d.month, d.day);
            } catch (_) {}
          }
          if (pDay != null && pDay == todayOnly) {
            pendingMatch = p;
            break;
          }
        }
        if (pendingMatch != null) {
          final attMap = pendingMatch['attendance'] as Map?;
          if (attMap != null) {
            attendance = Map<String, String>.from(attMap);
          } else {
            attendance = {};
          }
          attendanceExistsToday = true;
          attendanceDocId = null;
        } else {
          attendanceExistsToday = false;
          attendanceDocId = null;
          attendance = {};
        }
      }

      // Reload students for class
      final classDoc = await FirebaseFirestore.instance.collection('classes').doc(classId).get();
      if (!classDoc.exists) {
        setState(() {
          errorMsg = 'Kelas tidak ditemukan.';
          students = [];
        });
        return;
      }
      final classData = classDoc.data() as Map<String, dynamic>;
      final studentIds = List<String>.from(classData['students'] ?? []);
      List<QueryDocumentSnapshot> allStudentDocs = [];
      const batchSize = 10;
      for (int i = 0; i < studentIds.length; i += batchSize) {
        final end = (i + batchSize < studentIds.length) ? i + batchSize : studentIds.length;
        final batchIds = studentIds.sublist(i, end);
        final batchQuery = await FirebaseFirestore.instance
            .collection('students')
            .where(FieldPath.documentId, whereIn: batchIds)
            .get();
        allStudentDocs.addAll(batchQuery.docs);
      }
      final studentsList = allStudentDocs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {'id': doc.id, ...data};
      }).toList();
      studentsList.sort((a, b) {
        final aName = (a['name'] as String? ?? '').trim();
        final bName = (b['name'] as String? ?? '').trim();
        if (aName.isEmpty && bName.isEmpty) return 0;
        if (aName.isEmpty) return 1;
        if (bName.isEmpty) return -1;
        return aName.toLowerCase().compareTo(bName.toLowerCase());
      });
      setState(() {
        students = studentsList;
        className = '${classData['grade']}${classData['class_name'] ?? ''}';
      });
    } catch (e) {
      setState(() {
        errorMsg = 'Gagal memuat ulang data jadwal: $e';
      });
    }
  }

  Future<Map<String, String>> _fetchClassDisplayNames(Set<String> classIds) async {
    final result = <String, String>{};
    for (final id in classIds) {
      try {
        final doc = await FirebaseFirestore.instance.collection('classes').doc(id).get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          result[id] = '${data['grade'] ?? ''}${data['class_name'] ?? ''}';
        } else {
          result[id] = id;
        }
      } catch (_) {
        result[id] = id;
      }
    }
    return result;
  }

  String _getScheduleSubject() {
    return scheduleSubject ?? 'Tidak tersedia';
  }

  String _getScheduleTypeDisplay() {
    if (scheduleType == null) return 'Tidak tersedia';
    
    switch (scheduleType) {
      case 'daily_morning':
        return 'Presensi Pagi Harian';
      case 'subject_specific':
        return 'Mata Pelajaran';
      default:
        return 'Tidak Diketahui';
    }
  }

  String _getScheduleTimeDisplay() {
    return scheduleTime ?? 'Tidak tersedia';
  }

  String _scheduleLabel(Map<String, dynamic> s) {
    final subject = (s['subject'] ?? '').toString();
    final time = (s['time'] ?? '').toString();
    // Class display: resolve human readable if we have current className for active; otherwise fallback to ID
    final classIdValue = (s['class_id'] ?? '').toString();
    String classDisplay = _classDisplayById[classIdValue] ?? classIdValue;
    if (subject.isNotEmpty) {
      return '$subject • $classDisplay\n$time';
    }
    return '$classDisplay\n$time';
  }

  Color _getAttendanceColor(String? status) {
    switch (status) {
      case 'hadir':
        return Colors.green;
      case 'sakit':
        return Colors.orange;
      case 'izin':
        return Colors.blue;
      case 'alfa':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formattedEndTime() {
    if (_scheduleEndTime == null) return '';
    final h = _scheduleEndTime!.hour.toString().padLeft(2, '0');
    final m = _scheduleEndTime!.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _saveOrUpdateAttendance() async {
    if (classId == null || scheduleId == null) return;
    
    // Check if all students have attendance status
    final studentsWithoutStatus = students.where((student) => 
      attendance[student['id']] == null || attendance[student['id']]!.isEmpty
    ).toList();
    
    if (studentsWithoutStatus.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Peringatan: ${studentsWithoutStatus.length} siswa belum memiliki status kehadiran. Silakan isi status untuk semua siswa terlebih dahulu.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }
    
    final now = DateTime.now();
    final userInfo = widget.userInfo ?? {};
    final connectivityService = ConnectivityService();
    
    final attendanceData = {
      'class_id': classId,
      'schedule_id': scheduleId,
      'teacher_id': userInfo['nuptk'] ?? '',
      'school_id': userInfo['school_id'] ?? '',
      'date': DateTime(now.year, now.month, now.day),
      'attendance': attendance,
      'student_ids': attendance.keys.toList(),
      'local_timestamp': DateTime.now().toIso8601String(),
    };

    print('\n=== SAVING ATTENDANCE ===');
    print('Attendance data to save: $attendanceData');
    print('=== END SAVING ATTENDANCE ===\n');

    try {
      if (connectivityService.isConnected) {
        // Online: Check if attendance already exists before saving
        if (attendanceExistsToday && attendanceDocId != null) {
          // Update existing attendance
          await FirebaseFirestore.instance.collection('attendances').doc(attendanceDocId).update({
            'attendance': attendance,
            'student_ids': attendance.keys.toList(),
            'updated_at': FieldValue.serverTimestamp(),
          });
        } else {
          // Save new attendance
        await FirebaseFirestore.instance.collection('attendances').add({
          ...attendanceData,
          'created_at': FieldValue.serverTimestamp(),
        });
        }
        
        // Set attendance as taken for today
        setState(() {
          attendanceExistsToday = true;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(attendanceDocId != null ? 'Presensi berhasil diperbarui!' : 'Presensi berhasil disimpan!'),
              backgroundColor: Colors.green,
            ),
          );
          
          // Navigate back to main screen after a short delay
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => AdminStudentsScreen(
                    userInfo: widget.userInfo ?? {},
                    role: (widget.userInfo?['role'] ?? 'guru'),
                  ),
                ),
              );
            }
          });
        }
      } else {
        // Offline: create or update pending attendance for today (idempotent)
        final pendingAttendance = await LocalStorageService.getPendingAttendance();
        final today = DateTime(now.year, now.month, now.day);
        final hasPendingToday = pendingAttendance.any((pending) {
          final pendingScheduleId = pending['schedule_id'] as String?;
          final pendingTeacherId = pending['teacher_id'] as String?;
          final pendingDate = pending['date'];
          if (pendingScheduleId != scheduleId || pendingTeacherId != userInfo['nuptk']) return false;
          DateTime? pendingDateTime;
          if (pendingDate is DateTime) {
            pendingDateTime = pendingDate;
          } else if (pendingDate is String) {
            try { pendingDateTime = DateTime.parse(pendingDate); } catch (_) { return false; }
          } else { return false; }
          return pendingDateTime.year == today.year && pendingDateTime.month == today.month && pendingDateTime.day == today.day;
        });

        await LocalStorageService.savePendingAttendance({
          ...attendanceData,
          'date': (attendanceData['date'] as DateTime).toIso8601String(),
          'local_timestamp': DateTime.now().toIso8601String(),
        });
        
        // Set attendance as taken for today
        setState(() {
          attendanceExistsToday = true;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(hasPendingToday ? 'Perubahan presensi disimpan offline.' : 'Presensi disimpan offline. Akan disinkronkan saat online.'),
              backgroundColor: Colors.orange,
            ),
          );
          
          // Navigate back to main screen after a short delay
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => AdminStudentsScreen(
                    userInfo: widget.userInfo ?? {},
                    role: (widget.userInfo?['role'] ?? 'guru'),
                  ),
                ),
              );
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan presensi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _scrollToStudent(String query) {
    if (query.trim().isEmpty) return;
    final idx = students.indexWhere((s) => ((s['name'] ?? '') as String).toLowerCase().contains(query.toLowerCase()));
    if (idx >= 0) {
      final key = _itemKeys[idx];
      if (key != null && key.currentContext != null) {
        Scrollable.ensureVisible(
          key.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        // Rough scroll to position to force build, then ensureVisible
        const estimatedItemExtent = 80.0; // approximate height of each card row
        final targetOffset = (idx * estimatedItemExtent).clamp(0, _listController.position.maxScrollExtent).toDouble();
        _listController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        ).then((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final ctx = _itemKeys[idx]?.currentContext;
            if (ctx != null) {
              Scrollable.ensureVisible(
                ctx,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
              );
            }
          });
        });
      }
    }
  }

  final Map<int, GlobalKey> _itemKeys = {};
  final ScrollController _listController = ScrollController();
}

class _ScheduleSwitcher extends StatelessWidget {
  final List<Map<String, dynamic>> schedules;
  final int activeIndex;
  final ValueChanged<int> onChanged;

  const _ScheduleSwitcher({
    Key? key,
    required this.schedules,
    required this.activeIndex,
    required this.onChanged,
  }) : super(key: key);

  String _labelFor(Map<String, dynamic> s) {
    final subject = s['subject'] ?? '';
    final classId = s['class_id'] ?? '';
    final time = s['time'] ?? '';
    return subject.toString().isNotEmpty
        ? '$subject • $classId\n$time'
        : '$classId\n$time';
  }

  @override
  Widget build(BuildContext context) {
    if (schedules.length <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: activeIndex > 0 ? () => onChanged(activeIndex - 1) : null,
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('Jadwal', style: TextStyle(color: Colors.white70, fontSize: 11)),
              Text(
                _labelFor(schedules[activeIndex]),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, color: Colors.white),
          onPressed: activeIndex < schedules.length - 1 ? () => onChanged(activeIndex + 1) : null,
        ),
      ],
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

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

      for (var doc in scheduleSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final scheduleType = data['schedule_type'] ?? 'subject_specific';
        print('\n--- Checking Schedule ${doc.id} ---');
        print('Schedule type: $scheduleType');
        print('Schedule data: $data');
        
        if (scheduleType == 'daily_morning') {
          // Check if it's morning time (6:30 AM)
          final currentTime = now.hour * 60 + now.minute;
          final morningTime = 6 * 60 + 30; // 6:30 AM
          final morningEndTime = 7 * 60; // 7:00 AM
          print('Daily morning check:');
          print('  Current time in minutes: $currentTime');
          print('  Morning start: $morningTime (6:30 AM)');
          print('  Morning end: $morningEndTime (7:00 AM)');
          print('  Is within morning time: ${currentTime >= morningTime && currentTime <= morningEndTime}');
          
          if (currentTime >= morningTime && currentTime <= morningEndTime) {
            foundSchedule = data;
            foundScheduleId = doc.id;
            print('  ✓ FOUND DAILY MORNING SCHEDULE!');
            break;
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
              
              print('  Parsed schedule:');
              print('    Day: $dayStr (weekday: $targetWeekday)');
              print('    Start: $startHour:$startMinute ($startMinutes minutes)');
              print('    End: $endHour:$endMinute ($endMinutes minutes)');
              print('    Current weekday: ${now.weekday}');
              print('    Current time: ${now.hour}:${now.minute} ($nowMinutes minutes)');
              print('    Is today: ${targetWeekday == now.weekday}');
              
              if (targetWeekday == now.weekday) {
                print('    ✓ Schedule is for today!');
                print('    Time check: $nowMinutes >= $startMinutes && $nowMinutes <= $endMinutes');
                print('    Is within time: ${nowMinutes >= startMinutes && nowMinutes <= endMinutes}');
                
                if (nowMinutes >= startMinutes && nowMinutes <= endMinutes) {
                  foundSchedule = data;
                  foundScheduleId = doc.id;
                  print('    ✓ FOUND SUBJECT-SPECIFIC SCHEDULE!');
                  break;
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

      if (foundSchedule == null) {
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

      print('\n✓ SCHEDULE FOUND!');
      print('Schedule ID: $scheduleId');
      print('Class ID: $classId');
      print('Schedule data: $foundSchedule');

      classId = foundSchedule['class_id'];
      scheduleId = foundScheduleId;
      scheduleType = foundSchedule['schedule_type'];
      scheduleSubject = foundSchedule['subject'];
      scheduleTime = foundSchedule['time'];

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
        attendanceExistsToday = false;
        attendanceDocId = null;
        print('No existing attendance found');
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

      // Load student details
      final studentsQuery = await FirebaseFirestore.instance
        .collection('students')
        .where(FieldPath.documentId, whereIn: studentIds)
        .get();

      print('Found ${studentsQuery.docs.length} students with details');

      final studentsList = studentsQuery.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();

      setState(() {
        students = studentsList;
        isLoading = false;
        className = classData['grade'].toString() + (classData['class_name'] ?? '');
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
                          'Kelas: $className',
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
                              'Presensi untuk hari ini sudah ada',
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
                if (!attendanceExistsToday) ...[
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
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                for (var student in students) {
                                  attendance[student['id']] = 'alfa';
                                }
                              });
                            },
                            icon: const Icon(Icons.cancel),
                            label: const Text('Alfa Semua'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                
                // Students List
                Expanded(
                  child: ListView.builder(
                    itemCount: students.length,
                    itemBuilder: (context, index) {
                      final s = students[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: ListTile(
                          title: Text(s['name'] ?? 'Nama tidak tersedia'),
                          trailing: attendanceExistsToday 
                            ? Text(
                                attendance[s['id']] ?? 'Tidak ada data',
                                style: TextStyle(
                                  color: _getAttendanceColor(attendance[s['id']]),
                                  fontWeight: FontWeight.w500,
                                ),
                              )
                            : DropdownButton<String>(
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
      floatingActionButton: isLoading || errorMsg != null || attendanceExistsToday
        ? null
        : FloatingActionButton.extended(
            onPressed: _saveAttendance,
            icon: const Icon(Icons.save),
            label: const Text('Simpan Presensi'),
            backgroundColor: Colors.teal,
          ),
    );
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

  Future<void> _saveAttendance() async {
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
        final today = DateTime(now.year, now.month, now.day);
        final attendanceExists = await OfflineSyncService.checkAttendanceExists(
          scheduleId!,
          userInfo['nuptk'] ?? '',
          today,
        );

        if (attendanceExists) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Presensi untuk hari ini sudah ada!'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        // Save directly to Firestore
        await FirebaseFirestore.instance.collection('attendances').add({
          ...attendanceData,
          'created_at': FieldValue.serverTimestamp(),
        });
        
        // Set attendance as taken for today
        setState(() {
          attendanceExistsToday = true;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Presensi berhasil disimpan!'),
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
        // Offline: Check pending attendance to avoid duplicates
        final pendingAttendance = await LocalStorageService.getPendingAttendance();
        final today = DateTime(now.year, now.month, now.day);
        final todayString = today.toIso8601String();
        
        // Check if we already have pending attendance for today
        final hasPendingToday = pendingAttendance.any((pending) =>
          pending['schedule_id'] == scheduleId &&
          pending['teacher_id'] == userInfo['nuptk'] &&
          pending['date'] == todayString
        );

        if (hasPendingToday) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Presensi offline untuk hari ini sudah ada!'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        // Save to local storage for later sync
        await LocalStorageService.savePendingAttendance(attendanceData);
        
        // Set attendance as taken for today
        setState(() {
          attendanceExistsToday = true;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Presensi disimpan offline. Akan disinkronkan saat online.'),
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

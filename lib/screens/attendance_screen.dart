import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'login_screen.dart';

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
  bool attendanceExistsToday = false;
  String? attendanceDocId;

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
          final timeString = data['time'].toString();
          final regex = RegExp(r'(\d{2}):(\d{2})-(\d{2}):(\d{2})');
          final match = regex.firstMatch(timeString);

          if (match != null) {
            final start = match.group(1)! + ':' + match.group(2)!;
            final end = match.group(3)! + ':' + match.group(4)!;
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
              final scheduleDateTime = DateTime(now.year, now.month, now.day, startParts[0], startParts[1]);
              if (nearestTime == null || scheduleDateTime.isBefore(nearestTime)) {
                nearestTime = scheduleDateTime;
                nearestSchedule = data;
              }
            }
          }
        } else if (data['time'] != null) {
          // Check schedules for other days this week
          final timeString = data['time'].toString();
          final regex = RegExp(r'([A-Za-z]+) (\d{2}):(\d{2})-(\d{2}):(\d{2})');
          final match = regex.firstMatch(timeString);

          if (match != null) {
            final dayStr = match.group(1)!;
            final start = match.group(2)! + ':' + match.group(3)!;
            final startParts = start.split(':').map(int.parse).toList();

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

      // Check if attendance already exists for today
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
        attendanceExistsToday = false;
        attendanceDocId = null;
      }

      final classDoc = await FirebaseFirestore.instance.collection('classes').doc(classId).get();
      final classData = classDoc.data();
      className = classData!['grade'].toString() + ' ' + (classData?['class_name'] ?? '');
      final studentIds = List<String>.from(classData?['students'] ?? []);

      if (studentIds.isEmpty) {
        setState(() {
          isLoading = false;
          errorMsg = 'Tidak ada siswa di kelas ini.';
        });
        return;
      }

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

      // If no attendance exists, initialize all as hadir
      if (!attendanceExistsToday) {
        attendance = { for (var s in students) s['id']: 'hadir' };
      }
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
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Presensi'),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
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
                if (attendanceExistsToday)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                    child: Text('Presensi untuk jadwal ini sudah diisi hari ini.', style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold)),
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
      floatingActionButton: isLoading || errorMsg != null
        ? null
        : FloatingActionButton.extended(
            onPressed: attendanceExistsToday ? null : _saveAttendance,
            icon: const Icon(Icons.save),
            label: attendanceExistsToday ? const Text('Presensi Sudah Disimpan') : const Text('Simpan'),
            backgroundColor: attendanceExistsToday ? Colors.grey : Colors.teal,
          ),
    );
  }

  Future<void> _saveAttendance() async {
    if (classId == null || scheduleId == null) return;
    final now = DateTime.now();
    final userInfo = widget.userInfo ?? {};
    try {
      await FirebaseFirestore.instance.collection('attendances').add({
        'class_id': classId,
        'schedule_id': scheduleId,
        'teacher_id': userInfo['nuptk'] ?? '',
        'date': DateTime(now.year, now.month, now.day),
        'attendance': attendance,
        'student_ids': attendance.keys.toList(),
        'created_at': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Presensi berhasil disimpan!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan presensi: $e')),
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

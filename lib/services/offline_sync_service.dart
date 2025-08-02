import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/local_storage_service.dart';
import '../services/connectivity_service.dart';

class OfflineSyncService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final ConnectivityService _connectivityService = ConnectivityService();

  /// Sync pending attendance data when online
  static Future<void> syncPendingAttendance() async {
    if (!_connectivityService.isConnected) return;

    try {
      final pendingAttendance = await LocalStorageService.getPendingAttendance();
      if (pendingAttendance.isEmpty) return;

      print('Syncing ${pendingAttendance.length} pending attendance records...');

      for (var attendanceData in pendingAttendance) {
        try {
          // Check if attendance already exists to prevent duplicates
          final existingAttendance = await _checkExistingAttendance(attendanceData);
          if (existingAttendance) {
            print('Attendance already exists for class: ${attendanceData['class_id']}, date: ${attendanceData['date']}. Skipping...');
            // Remove this pending record since it already exists
            await LocalStorageService.removePendingAttendance(
              attendanceData['schedule_id'] as String,
              attendanceData['teacher_id'] as String,
              attendanceData['date'] as String,
            );
            continue;
          }

          // Remove the local timestamp and add server timestamp
          attendanceData.remove('local_timestamp');
          
          // Convert date string back to DateTime for Firestore
          if (attendanceData['date'] is String) {
            attendanceData['date'] = DateTime.parse(attendanceData['date'] as String);
          }
          
          await _firestore.collection('attendances').add(attendanceData);
          print('Synced attendance for class: ${attendanceData['class_id']}');
          
          // Remove this specific pending record after successful sync
          await LocalStorageService.removePendingAttendance(
            attendanceData['schedule_id'] as String,
            attendanceData['teacher_id'] as String,
            attendanceData['date'] as String,
          );
        } catch (e) {
          print('Error syncing attendance: $e');
          // Continue with other records even if one fails
        }
      }

      await LocalStorageService.saveLastSync(DateTime.now());
      print('Successfully synced all pending attendance records');
    } catch (e) {
      print('Error during sync: $e');
    }
  }

  /// Check if attendance record already exists
  static Future<bool> _checkExistingAttendance(Map<String, dynamic> attendanceData) async {
    try {
      final classId = attendanceData['class_id'] as String?;
      final scheduleId = attendanceData['schedule_id'] as String?;
      final teacherId = attendanceData['teacher_id'] as String?;
      final dateString = attendanceData['date'] as String?;
      
      if (classId == null || scheduleId == null || teacherId == null || dateString == null) {
        return false;
      }

      // Parse the date string to get the date range for query
      final date = DateTime.parse(dateString);
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Query for existing attendance records
      final query = await _firestore
          .collection('attendances')
          .where('class_id', isEqualTo: classId)
          .where('schedule_id', isEqualTo: scheduleId)
          .where('teacher_id', isEqualTo: teacherId)
          .where('date', isGreaterThanOrEqualTo: startOfDay)
          .where('date', isLessThan: endOfDay)
          .limit(1)
          .get();

      return query.docs.isNotEmpty;
    } catch (e) {
      print('Error checking existing attendance: $e');
      return false;
    }
  }

  /// Check if attendance exists for a specific schedule, teacher, and date
  static Future<bool> checkAttendanceExists(String scheduleId, String teacherId, DateTime date) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final query = await _firestore
          .collection('attendances')
          .where('schedule_id', isEqualTo: scheduleId)
          .where('teacher_id', isEqualTo: teacherId)
          .where('date', isGreaterThanOrEqualTo: startOfDay)
          .where('date', isLessThan: endOfDay)
          .limit(1)
          .get();

      return query.docs.isNotEmpty;
    } catch (e) {
      print('Error checking attendance existence: $e');
      return false;
    }
  }

  /// Sync teacher data (classes and schedules)
  static Future<void> syncTeacherData(String teacherId) async {
    if (!_connectivityService.isConnected) return;

    try {
      // Check if data is stale
      final isStale = await LocalStorageService.isDataStale();
      if (!isStale) return;

      print('Syncing teacher data for teacher: $teacherId');

      // Fetch and save teacher's classes
      final classesQuery = await _firestore
          .collection('classes')
          .where('students', arrayContains: teacherId)
          .get();

      final classes = classesQuery.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();

      await LocalStorageService.saveTeacherClasses(classes);

      // Fetch and save teacher's schedules
      final schedulesQuery = await _firestore
          .collection('schedules')
          .where('teacher_id', isEqualTo: teacherId)
          .get();

      final schedules = schedulesQuery.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();

      await LocalStorageService.saveTeacherSchedules(schedules);
      await LocalStorageService.saveLastSync(DateTime.now());

      print('Successfully synced teacher data');
    } catch (e) {
      print('Error syncing teacher data: $e');
    }
  }

  /// Initialize sync monitoring
  static void initializeSyncMonitoring() {
    _connectivityService.connectionStatus.listen((isConnected) {
      if (isConnected) {
        // When connection is restored, sync pending data
        syncPendingAttendance();
      }
    });
  }

  /// Get sync status information
  static Future<Map<String, dynamic>> getSyncStatus() async {
    final pendingCount = await LocalStorageService.getPendingAttendanceCount();
    final lastSync = await LocalStorageService.getLastSync();
    final isConnected = _connectivityService.isConnected;
    
    return {
      'pendingCount': pendingCount,
      'lastSync': lastSync,
      'isConnected': isConnected,
      'hasPendingData': pendingCount > 0,
    };
  }

  /// Get current schedule for teacher (from local storage or online)
  static Future<Map<String, dynamic>?> getCurrentSchedule(String teacherId) async {
    try {
      if (_connectivityService.isConnected) {
        // Try to get from online first
        final now = DateTime.now();
        final currentDay = _getDayName(now.weekday);
        final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

        final schedulesQuery = await _firestore
            .collection('schedules')
            .where('teacher_id', isEqualTo: teacherId)
            .get();

        for (var doc in schedulesQuery.docs) {
          final schedule = doc.data();
          final scheduleType = schedule['schedule_type'] ?? 'subject_specific';
          
          if (scheduleType == 'daily_morning') {
            // Check if it's morning time (6:30 AM)
            final currentMinutes = now.hour * 60 + now.minute;
            final morningStart = 6 * 60 + 30; // 6:30 AM
            final morningEnd = 7 * 60; // 7:00 AM
            
            if (currentMinutes >= morningStart && currentMinutes <= morningEnd) {
              return {
                'id': doc.id,
                ...schedule,
              };
            }
          } else if (scheduleType == 'subject_specific') {
            // Check subject-specific schedules
            final timeString = schedule['time'] as String? ?? '';
            
            if (timeString.contains(currentDay)) {
              // Parse time range (e.g., "Senin 08:00-09:00")
              final timeMatch = RegExp(r'(\d{2}):(\d{2})-(\d{2}):(\d{2})').firstMatch(timeString);
              if (timeMatch != null) {
                final startTime = '${timeMatch.group(1)}:${timeMatch.group(2)}';
                final endTime = '${timeMatch.group(3)}:${timeMatch.group(4)}';
                
                if (_isTimeInRange(currentTime, startTime, endTime)) {
                  return {
                    'id': doc.id,
                    ...schedule,
                  };
                }
              }
            }
          }
        }
      } else {
        // Use local storage
        final schedules = await LocalStorageService.getTeacherSchedules();
        final now = DateTime.now();
        final currentDay = _getDayName(now.weekday);
        final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

        for (var schedule in schedules) {
          final scheduleType = schedule['schedule_type'] ?? 'subject_specific';
          
          if (scheduleType == 'daily_morning') {
            // Check if it's morning time (6:30 AM)
            final currentMinutes = now.hour * 60 + now.minute;
            final morningStart = 6 * 60 + 30; // 6:30 AM
            final morningEnd = 7 * 60; // 7:00 AM
            
            if (currentMinutes >= morningStart && currentMinutes <= morningEnd) {
              return schedule;
            }
          } else if (scheduleType == 'subject_specific') {
            // Check subject-specific schedules
            final timeString = schedule['time'] as String? ?? '';
            
            if (timeString.contains(currentDay)) {
              final timeMatch = RegExp(r'(\d{2}):(\d{2})-(\d{2}):(\d{2})').firstMatch(timeString);
              if (timeMatch != null) {
                final startTime = '${timeMatch.group(1)}:${timeMatch.group(2)}';
                final endTime = '${timeMatch.group(3)}:${timeMatch.group(4)}';
                
                if (_isTimeInRange(currentTime, startTime, endTime)) {
                  return schedule;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error getting current schedule: $e');
    }
    return null;
  }

  /// Get students for a class (from local storage or online)
  static Future<List<Map<String, dynamic>>> getStudentsForClass(String classId) async {
    try {
      if (_connectivityService.isConnected) {
        // Get from online
        final classDoc = await _firestore.collection('classes').doc(classId).get();
        if (!classDoc.exists) return [];

        final classData = classDoc.data() as Map<String, dynamic>;
        final studentIds = List<String>.from(classData['students'] ?? []);

        if (studentIds.isEmpty) return [];

        final studentsQuery = await _firestore
            .collection('students')
            .where(FieldPath.documentId, whereIn: studentIds)
            .get();

        return studentsQuery.docs.map((doc) => {
          'id': doc.id,
          ...doc.data(),
        }).toList();
      } else {
        // Use local storage - this would need to be implemented based on your data structure
        // For now, return empty list when offline
        return [];
      }
    } catch (e) {
      print('Error getting students for class: $e');
      return [];
    }
  }

  /// Helper method to get day name
  static String _getDayName(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Senin';
      case DateTime.tuesday:
        return 'Selasa';
      case DateTime.wednesday:
        return 'Rabu';
      case DateTime.thursday:
        return 'Kamis';
      case DateTime.friday:
        return 'Jumat';
      case DateTime.saturday:
        return 'Sabtu';
      case DateTime.sunday:
        return 'Minggu';
      default:
        return '';
    }
  }

  /// Helper method to check if time is in range
  static bool _isTimeInRange(String currentTime, String startTime, String endTime) {
    final current = _timeToMinutes(currentTime);
    final start = _timeToMinutes(startTime);
    final end = _timeToMinutes(endTime);
    
    return current >= start && current <= end;
  }

  /// Helper method to convert time string to minutes
  static int _timeToMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
} 
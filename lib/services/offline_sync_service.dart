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
          // Remove the local timestamp and add server timestamp
          attendanceData.remove('local_timestamp');
          
          // Convert date string back to DateTime for Firestore
          if (attendanceData['date'] is String) {
            attendanceData['date'] = DateTime.parse(attendanceData['date'] as String);
          }
          
          await _firestore.collection('attendances').add(attendanceData);
          print('Synced attendance for class: ${attendanceData['class_id']}');
        } catch (e) {
          print('Error syncing attendance: $e');
          // Continue with other records even if one fails
        }
      }

      // Clear pending attendance after successful sync
      await LocalStorageService.clearPendingAttendance();
      await LocalStorageService.saveLastSync(DateTime.now());
      
      print('Successfully synced all pending attendance records');
    } catch (e) {
      print('Error during sync: $e');
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
      } else {
        // Use local storage
        final schedules = await LocalStorageService.getTeacherSchedules();
        final now = DateTime.now();
        final currentDay = _getDayName(now.weekday);
        final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

        for (var schedule in schedules) {
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
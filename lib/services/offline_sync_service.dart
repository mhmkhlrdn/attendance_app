import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/local_storage_service.dart';
import '../services/connectivity_service.dart';

class OfflineSyncService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final ConnectivityService _connectivityService = ConnectivityService();
  static bool _isSyncing = false; // Prevent multiple simultaneous sync operations

  static Future<void> syncPendingAttendance() async {
    // Prevent multiple simultaneous sync operations
    if (_isSyncing) {
      print('Sync already in progress, skipping...');
      return;
    }

    if (!_connectivityService.isConnected) {
      print('No internet connection, skipping sync...');
      return;
    }

    _isSyncing = true;

    try {
      final pendingAttendance = await LocalStorageService.getPendingAttendance();
      if (pendingAttendance.isEmpty) {
        print('No pending attendance to sync');
        return;
      }

      // Deduplicate by (schedule_id, teacher_id, date YYYY-MM-DD) keeping the latest local_timestamp
      final Map<String, Map<String, dynamic>> latestByKey = {};
      DateTime _parseTs(dynamic v) {
        if (v is DateTime) return v;
        if (v is String) {
          try { return DateTime.parse(v); } catch (_) {}
        }
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
      String _dateKey(dynamic dateVal) {
        if (dateVal is DateTime) return dateVal.toIso8601String().split('T')[0];
        if (dateVal is String) return dateVal.split('T')[0];
        return '';
      }
      for (final att in pendingAttendance) {
        final sid = att['schedule_id'] as String? ?? '';
        final tid = att['teacher_id'] as String? ?? '';
        final dkey = _dateKey(att['date']);
        if (sid.isEmpty || tid.isEmpty || dkey.isEmpty) continue;
        final key = '$sid|$tid|$dkey';
        final currentTs = _parseTs(att['local_timestamp']);
        if (!latestByKey.containsKey(key)) {
          latestByKey[key] = att;
        } else {
          final existingTs = _parseTs(latestByKey[key]!['local_timestamp']);
          if (currentTs.isAfter(existingTs)) {
            latestByKey[key] = att;
          }
        }
      }

      final toSync = latestByKey.values.toList();
      print('Syncing ${toSync.length} pending attendance records (deduped from ${pendingAttendance.length})...');

      // Process each attendance record (latest only per day)
      for (var attendanceData in toSync) {
        print('Processing attendance: class=${attendanceData['class_id']}, date=${attendanceData['date']}, type=${attendanceData['date'].runtimeType}');
        try {
          // Check if attendance already exists to prevent duplicates
          final existingAttendance = await _checkExistingAttendance(attendanceData);
          if (existingAttendance) {
            // If a record exists for that day/schedule/teacher, update it instead of skipping
            final cleanData = Map<String, dynamic>.from(attendanceData);
            if (cleanData['date'] is String) {
              cleanData['date'] = DateTime.parse(cleanData['date'] as String);
            }
            final startOfDay = DateTime(cleanData['date'].year, cleanData['date'].month, cleanData['date'].day);
            final endOfDay = startOfDay.add(const Duration(days: 1));
            final query = await _firestore
                .collection('attendances')
                .where('schedule_id', isEqualTo: cleanData['schedule_id'])
                .where('teacher_id', isEqualTo: cleanData['teacher_id'])
                .where('date', isGreaterThanOrEqualTo: startOfDay)
                .where('date', isLessThan: endOfDay)
                .limit(1)
                .get();
            if (query.docs.isNotEmpty) {
              await _firestore.collection('attendances').doc(query.docs.first.id).update({
                'attendance': cleanData['attendance'],
                'student_ids': cleanData['student_ids'],
                'updated_at': FieldValue.serverTimestamp(),
              });
              // Remove from pending after successful update
            final dateValue = attendanceData['date'];
            String dateString;
            if (dateValue is DateTime) {
              dateString = dateValue.toIso8601String();
            } else if (dateValue is String) {
              dateString = dateValue;
            } else {
              continue;
            }
              await LocalStorageService.removePendingAttendance(
                attendanceData['schedule_id'] as String,
                attendanceData['teacher_id'] as String,
                dateString,
              );
            continue;
            }
          }

          final cleanData = Map<String, dynamic>.from(attendanceData);

          cleanData.remove('local_timestamp');

          if (cleanData['date'] is String) {
            cleanData['date'] = DateTime.parse(cleanData['date'] as String);
          }

          cleanData['server_timestamp'] = FieldValue.serverTimestamp();
          
          await _firestore.collection('attendances').add(cleanData);
          print('Successfully synced attendance for class: ${attendanceData['class_id']}');

          final dateValue = attendanceData['date'];
          String dateString;
          if (dateValue is DateTime) {
            dateString = dateValue.toIso8601String();
          } else if (dateValue is String) {
            dateString = dateValue;
          } else {
            print('Invalid date format for removal: $dateValue');
            continue;
          }
          await LocalStorageService.removePendingAttendance(
            attendanceData['schedule_id'] as String,
            attendanceData['teacher_id'] as String,
            dateString,
          );
        } catch (e) {
          print('Error syncing individual attendance: $e');
          // Continue with other records even if one fails
          // Don't remove the pending record if sync failed
        }
      }

      await LocalStorageService.saveLastSync(DateTime.now());
      print('Successfully completed sync operation');
    } catch (e) {
      print('Error during sync: $e');
      rethrow; // Re-throw to let the UI handle the error
    } finally {
      _isSyncing = false;
    }
  }

  /// Check if attendance record already exists
  static Future<bool> _checkExistingAttendance(Map<String, dynamic> attendanceData) async {
    try {
      final classId = attendanceData['class_id'] as String?;
      final scheduleId = attendanceData['schedule_id'] as String?;
      final teacherId = attendanceData['teacher_id'] as String?;
      final dateValue = attendanceData['date'];
      
      if (classId == null || scheduleId == null || teacherId == null || dateValue == null) {
        print('Missing required fields for duplicate check');
        return false;
      }

      // Handle both DateTime and String date formats
      DateTime date;
      if (dateValue is DateTime) {
        date = dateValue;
      } else if (dateValue is String) {
        date = DateTime.parse(dateValue);
      } else {
        print('Invalid date format for duplicate check');
        return false;
      }

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

      final exists = query.docs.isNotEmpty;
      if (exists) {
        print('Duplicate found: class=$classId, schedule=$scheduleId, teacher=$teacherId, date=$date');
      }
      
      return exists;
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

  /// Check if sync is currently in progress
  static bool get isSyncing => _isSyncing;

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
      'isSyncing': _isSyncing,
      'canSync': isConnected && !_isSyncing && pendingCount > 0,
    };
  }

  /// Get detailed sync information for debugging
  static Future<Map<String, dynamic>> getDetailedSyncInfo() async {
    final pendingAttendance = await LocalStorageService.getPendingAttendance();
    final lastSync = await LocalStorageService.getLastSync();
    final isConnected = _connectivityService.isConnected;
    
    return {
      'pendingCount': pendingAttendance.length,
      'lastSync': lastSync,
      'isConnected': isConnected,
      'isSyncing': _isSyncing,
      'pendingDetails': pendingAttendance.map((attendance) => {
        'class_id': attendance['class_id'],
        'schedule_id': attendance['schedule_id'],
        'teacher_id': attendance['teacher_id'],
        'date': attendance['date'],
        'student_count': (attendance['student_ids'] as List<dynamic>?)?.length ?? 0,
      }).toList(),
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
            // Morning window: 6:30 AM to 12:30 PM
            final currentMinutes = now.hour * 60 + now.minute;
            final morningStart = 6 * 60 + 30;
            final morningEnd = 12 * 60 + 30;
            
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
            // Morning window: 6:30 AM to 12:30 PM
            final currentMinutes = now.hour * 60 + now.minute;
            final morningStart = 6 * 60 + 30;
            final morningEnd = 12 * 60 + 30;
            
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

        // Load students in batches to handle Firestore's whereIn limit of 10 items
        List<QueryDocumentSnapshot> allStudentDocs = [];
        
        // Firestore whereIn has a limit of 10 items, so we need to batch the queries
        const batchSize = 10;
        for (int i = 0; i < studentIds.length; i += batchSize) {
          final end = (i + batchSize < studentIds.length) ? i + batchSize : studentIds.length;
          final batchIds = studentIds.sublist(i, end);
          
          final batchQuery = await _firestore
            .collection('students')
            .where(FieldPath.documentId, whereIn: batchIds)
            .get();
          
          allStudentDocs.addAll(batchQuery.docs);
        }

        return allStudentDocs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            'id': doc.id,
            ...data,
          };
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
    
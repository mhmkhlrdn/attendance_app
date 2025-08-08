import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static const String _userKey = 'user_info';
  static const String _isLoggedInKey = 'is_logged_in';
  static const String _teacherClassesKey = 'teacher_classes';
  static const String _teacherSchedulesKey = 'teacher_schedules';
  static const String _pendingAttendanceKey = 'pending_attendance';
  static const String _lastSyncKey = 'last_sync';

  /// Save user information locally
  static Future<void> saveUserInfo(Map<String, String> userInfo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(userInfo));
    await prefs.setBool(_isLoggedInKey, true);
  }

  /// Get saved user information
  static Future<Map<String, String>?> getUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final userString = prefs.getString(_userKey);
    if (userString != null) {
      try {
        final userMap = jsonDecode(userString) as Map<String, dynamic>;
        return Map<String, String>.from(userMap);
      } catch (e) {
        print('Error parsing user info: $e');
        return null;
      }
    }
    return null;
  }

  /// Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  /// Clear user data (logout)
  static Future<void> clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.setBool(_isLoggedInKey, false);
    await prefs.remove(_teacherClassesKey);
    await prefs.remove(_teacherSchedulesKey);
    await prefs.remove(_pendingAttendanceKey);
    await prefs.remove(_lastSyncKey);
  }

  /// Save teacher's classes locally
  static Future<void> saveTeacherClasses(List<Map<String, dynamic>> classes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_teacherClassesKey, jsonEncode(classes));
  }

  /// Get teacher's classes from local storage
  static Future<List<Map<String, dynamic>>> getTeacherClasses() async {
    final prefs = await SharedPreferences.getInstance();
    final classesString = prefs.getString(_teacherClassesKey);
    if (classesString != null) {
      try {
        final classesList = jsonDecode(classesString) as List<dynamic>;
        return classesList.map((item) => Map<String, dynamic>.from(item)).toList();
      } catch (e) {
        print('Error parsing teacher classes: $e');
        return [];
      }
    }
    return [];
  }

  /// Save teacher's schedules locally
  static Future<void> saveTeacherSchedules(List<Map<String, dynamic>> schedules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_teacherSchedulesKey, jsonEncode(schedules));
  }

  /// Get teacher's schedules from local storage
  static Future<List<Map<String, dynamic>>> getTeacherSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final schedulesString = prefs.getString(_teacherSchedulesKey);
    if (schedulesString != null) {
      try {
        final schedulesList = jsonDecode(schedulesString) as List<dynamic>;
        return schedulesList.map((item) => Map<String, dynamic>.from(item)).toList();
      } catch (e) {
        print('Error parsing teacher schedules: $e');
        return [];
      }
    }
    return [];
  }

  /// Save pending attendance data (for offline sync)
  static Future<void> savePendingAttendance(Map<String, dynamic> attendanceData) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingList = await getPendingAttendance();
    
    // Check for duplicates before adding
    final isDuplicate = pendingList.any((existing) {
      final existingScheduleId = existing['schedule_id'] as String?;
      final existingTeacherId = existing['teacher_id'] as String?;
      final existingDate = existing['date'];
      final newScheduleId = attendanceData['schedule_id'] as String?;
      final newTeacherId = attendanceData['teacher_id'] as String?;
      final newDate = attendanceData['date'];
      
      if (existingScheduleId != newScheduleId || existingTeacherId != newTeacherId) {
        return false;
      }
      
      // Compare dates
      String existingDateString;
      String newDateString;
      
      if (existingDate is DateTime) {
        existingDateString = existingDate.toIso8601String().split('T')[0];
      } else if (existingDate is String) {
        existingDateString = existingDate.split('T')[0];
      } else {
        return false;
      }
      
      if (newDate is DateTime) {
        newDateString = newDate.toIso8601String().split('T')[0];
      } else if (newDate is String) {
        newDateString = newDate.split('T')[0];
      } else {
        return false;
      }
      
      return existingDateString == newDateString;
    });
    
    if (isDuplicate) {
      print('Duplicate pending attendance detected, skipping save');
      return;
    }
    
    // Convert DateTime objects to strings for JSON serialization
    final serializableData = Map<String, dynamic>.from(attendanceData);
    if (serializableData['date'] is DateTime) {
      serializableData['date'] = (serializableData['date'] as DateTime).toIso8601String();
    }
    if (serializableData['local_timestamp'] is DateTime) {
      serializableData['local_timestamp'] = (serializableData['local_timestamp'] as DateTime).toIso8601String();
    }
    if (serializableData['created_at'] is DateTime) {
      serializableData['created_at'] = (serializableData['created_at'] as DateTime).toIso8601String();
    }
    
    pendingList.add(serializableData);
    await prefs.setString(_pendingAttendanceKey, jsonEncode(pendingList));
    print('Saved pending attendance: ${attendanceData['class_id']} - ${attendanceData['date']}');
  }

  /// Get pending attendance data
  static Future<List<Map<String, dynamic>>> getPendingAttendance() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingString = prefs.getString(_pendingAttendanceKey);
    if (pendingString != null) {
      try {
        final pendingList = jsonDecode(pendingString) as List<dynamic>;
        return pendingList.map((item) {
          final data = Map<String, dynamic>.from(item);
          
          // Convert date strings back to DateTime objects
          if (data['date'] is String) {
            try {
              data['date'] = DateTime.parse(data['date'] as String);
            } catch (e) {
              print('Error parsing date string: ${data['date']}');
              // Keep as string if parsing fails
            }
          }
          if (data['local_timestamp'] is String) {
            try {
              data['local_timestamp'] = DateTime.parse(data['local_timestamp'] as String);
            } catch (e) {
              print('Error parsing local_timestamp string: ${data['local_timestamp']}');
              // Keep as string if parsing fails
            }
          }
          if (data['created_at'] is String) {
            try {
              data['created_at'] = DateTime.parse(data['created_at'] as String);
            } catch (e) {
              print('Error parsing created_at string: ${data['created_at']}');
              // Keep as string if parsing fails
            }
          }
          
          return data;
        }).toList();
      } catch (e) {
        print('Error parsing pending attendance: $e');
        // If parsing fails, clear the corrupted data
        await prefs.remove(_pendingAttendanceKey);
        return [];
      }
    }
    return [];
  }

  /// Get count of pending attendance records
  static Future<int> getPendingAttendanceCount() async {
    final pendingAttendance = await getPendingAttendance();
    return pendingAttendance.length;
  }

  /// Clear pending attendance after successful sync
  static Future<void> clearPendingAttendance() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingAttendanceKey);
    print('Cleared all pending attendance data');
  }

  /// Remove specific pending attendance record
  static Future<void> removePendingAttendance(String scheduleId, String teacherId, String date) async {
    print('Attempting to remove pending attendance: scheduleId=$scheduleId, teacherId=$teacherId, date=$date');
    final prefs = await SharedPreferences.getInstance();
    final pendingList = await getPendingAttendance();
    
    final initialCount = pendingList.length;
    print('Initial pending count: $initialCount');
    
    // Remove the specific attendance record
    pendingList.removeWhere((attendance) {
      final attendanceScheduleId = attendance['schedule_id'] as String?;
      final attendanceTeacherId = attendance['teacher_id'] as String?;
      final attendanceDate = attendance['date'];
      
      print('Checking attendance: scheduleId=$attendanceScheduleId, teacherId=$attendanceTeacherId, date=$attendanceDate');
      print('Target: scheduleId=$scheduleId, teacherId=$teacherId, date=$date');
      
      if (attendanceScheduleId != scheduleId || attendanceTeacherId != teacherId) {
        print('Schedule or teacher ID mismatch');
        return false;
      }
      
      // Handle both DateTime and String date formats
      String attendanceDateString;
      if (attendanceDate is DateTime) {
        attendanceDateString = attendanceDate.toIso8601String().split('T')[0]; // Get just the date part
      } else if (attendanceDate is String) {
        attendanceDateString = attendanceDate.split('T')[0]; // Get just the date part
      } else {
        print('Invalid attendance date type: ${attendanceDate.runtimeType}');
        return false;
      }
      
      final targetDateString = date.split('T')[0];
      print('Date comparison: attendanceDateString=$attendanceDateString, targetDateString=$targetDateString');
      final matches = attendanceDateString == targetDateString;
      print('Date match: $matches');
      return matches;
    });
    
    final finalCount = pendingList.length;
    print('Final pending count: $finalCount');
    if (initialCount != finalCount) {
      print('Removed ${initialCount - finalCount} pending attendance record(s)');
    } else {
      print('No records were removed - possible matching issue');
    }
    
    // Convert DateTime objects back to strings before saving
    final serializableList = pendingList.map((attendance) {
      final data = Map<String, dynamic>.from(attendance);
      if (data['date'] is DateTime) {
        data['date'] = (data['date'] as DateTime).toIso8601String();
      }
      if (data['local_timestamp'] is DateTime) {
        data['local_timestamp'] = (data['local_timestamp'] as DateTime).toIso8601String();
      }
      if (data['created_at'] is DateTime) {
        data['created_at'] = (data['created_at'] as DateTime).toIso8601String();
      }
      return data;
    }).toList();
    
    await prefs.setString(_pendingAttendanceKey, jsonEncode(serializableList));
  }

  /// Save last sync timestamp
  static Future<void> saveLastSync(DateTime timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, timestamp.toIso8601String());
  }

  /// Get last sync timestamp
  static Future<DateTime?> getLastSync() async {
    final prefs = await SharedPreferences.getInstance();
    final syncString = prefs.getString(_lastSyncKey);
    if (syncString != null) {
      try {
        return DateTime.parse(syncString);
      } catch (e) {
        print('Error parsing last sync: $e');
        return null;
      }
    }
    return null;
  }

  /// Check if data is stale (older than 24 hours)
  static Future<bool> isDataStale() async {
    final lastSync = await getLastSync();
    if (lastSync == null) return true;
    
    final now = DateTime.now();
    final difference = now.difference(lastSync);
    return difference.inHours > 24;
  }
} 
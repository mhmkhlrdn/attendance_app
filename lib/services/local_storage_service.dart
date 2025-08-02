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
    pendingList.add(attendanceData);
    await prefs.setString(_pendingAttendanceKey, jsonEncode(pendingList));
  }

  /// Get pending attendance data
  static Future<List<Map<String, dynamic>>> getPendingAttendance() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingString = prefs.getString(_pendingAttendanceKey);
    if (pendingString != null) {
      try {
        final pendingList = jsonDecode(pendingString) as List<dynamic>;
        return pendingList.map((item) => Map<String, dynamic>.from(item)).toList();
      } catch (e) {
        print('Error parsing pending attendance: $e');
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
  }

  /// Remove specific pending attendance record
  static Future<void> removePendingAttendance(String scheduleId, String teacherId, String date) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingList = await getPendingAttendance();
    
    // Remove the specific attendance record
    pendingList.removeWhere((attendance) =>
      attendance['schedule_id'] == scheduleId &&
      attendance['teacher_id'] == teacherId &&
      attendance['date'] == date
    );
    
    await prefs.setString(_pendingAttendanceKey, jsonEncode(pendingList));
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
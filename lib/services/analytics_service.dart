import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AnalyticsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get attendance trends over time for a specific period
  static Future<Map<String, dynamic>> getAttendanceTrends({
    required DateTime startDate,
    required DateTime endDate,
    String? classId,
    String? teacherId,
  }) async {
    try {
      // Convert dates to Timestamp objects for querying since we store dates as Timestamps
      final startTimestamp = Timestamp.fromDate(DateTime(startDate.year, startDate.month, startDate.day));
      final endTimestamp = Timestamp.fromDate(DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59));
      
      print('Querying with date range: $startTimestamp to $endTimestamp');
      
      Query query = _firestore.collection('attendances')
          .where('date', isGreaterThanOrEqualTo: startTimestamp)
          .where('date', isLessThanOrEqualTo: endTimestamp);

      if (classId != null) {
        query = query.where('class_id', isEqualTo: classId);
      }
      if (teacherId != null) {
        query = query.where('teacher_id', isEqualTo: teacherId);
      }

      final snapshot = await query.get();
      final attendances = snapshot.docs;
      
      print('Found ${attendances.length} attendance records');
      if (attendances.isNotEmpty) {
        print('Sample attendance data: ${attendances.first.data()}');
      } else {
        // Try to get all attendance records to see if there's any data
        final allSnapshot = await _firestore.collection('attendances').limit(5).get();
        print('Total attendance records in collection: ${allSnapshot.docs.length}');
        if (allSnapshot.docs.isNotEmpty) {
          print('Sample of all attendance data: ${allSnapshot.docs.first.data()}');
        }
      }

      // Group by date
      Map<String, Map<String, int>> dailyStats = {};
      for (var doc in attendances) {
        final data = doc.data() as Map<String, dynamic>;
        
        // Handle both Timestamp and String date formats
        DateTime date;
        if (data['date'] is Timestamp) {
          date = (data['date'] as Timestamp).toDate();
        } else if (data['date'] is String) {
          date = DateTime.parse(data['date'] as String);
        } else if (data['created_at'] is Timestamp) {
          // Fallback to created_at if date field is not available
          date = (data['created_at'] as Timestamp).toDate();
        } else {
          print('Skipping record with invalid date format: ${data['date']}');
          continue; // Skip invalid date format
        }
        
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        final attendance = Map<String, dynamic>.from(data['attendance'] ?? {});

        if (!dailyStats.containsKey(dateStr)) {
          dailyStats[dateStr] = {
            'hadir': 0,
            'sakit': 0,
            'izin': 0,
            'alfa': 0,
            'total': 0,
          };
        }

        attendance.forEach((studentId, status) {
          final statusStr = status.toString().toLowerCase();
          if (dailyStats[dateStr]!.containsKey(statusStr)) {
            dailyStats[dateStr]![statusStr] = (dailyStats[dateStr]![statusStr] ?? 0) + 1;
          }
          dailyStats[dateStr]!['total'] = (dailyStats[dateStr]!['total'] ?? 0) + 1;
        });
      }

      // Convert to chart data format
      List<Map<String, dynamic>> chartData = [];
      dailyStats.forEach((date, stats) {
        chartData.add({
          'date': date,
          'hadir': stats['hadir'] ?? 0,
          'sakit': stats['sakit'] ?? 0,
          'izin': stats['izin'] ?? 0,
          'alfa': stats['alfa'] ?? 0,
          'total': stats['total'] ?? 0,
        });
      });

      // Sort by date (strings are already in yyyy-MM-dd format, so string comparison works)
      chartData.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

      return {
        'success': true,
        'data': chartData,
        'summary': {
          'totalDays': chartData.length,
          'totalStudents': chartData.fold<int>(0, (sum, day) => sum + ((day['total'] ?? 0) as int)),
          'averageAttendance': chartData.isNotEmpty 
              ? chartData.fold<double>(0.0, (sum, day) => sum + ((day['hadir'] ?? 0) as double)) / chartData.length 
              : 0.0,
        }
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'data': [],
        'summary': {},
      };
    }
  }

  /// Get student performance analytics
  static Future<Map<String, dynamic>> getStudentPerformance({
    required String studentId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      Query query = _firestore.collection('attendances')
          .where('student_ids', arrayContains: studentId);

      if (startDate != null) {
        final startTimestamp = Timestamp.fromDate(DateTime(startDate.year, startDate.month, startDate.day));
        query = query.where('date', isGreaterThanOrEqualTo: startTimestamp);
      }
      if (endDate != null) {
        final endTimestamp = Timestamp.fromDate(DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59));
        query = query.where('date', isLessThanOrEqualTo: endTimestamp);
      }

      final snapshot = await query.get();
      final attendances = snapshot.docs;

      Map<String, int> statusCount = {
        'hadir': 0,
        'sakit': 0,
        'izin': 0,
        'alfa': 0,
      };

      int totalDays = 0;
      List<Map<String, dynamic>> dailyAttendance = [];

      for (var doc in attendances) {
        final data = doc.data() as Map<String, dynamic>;
        final attendance = Map<String, dynamic>.from(data['attendance'] ?? {});
        
        // Handle both Timestamp and String date formats
        DateTime date;
        if (data['date'] is Timestamp) {
          date = (data['date'] as Timestamp).toDate();
        } else if (data['date'] is String) {
          date = DateTime.parse(data['date'] as String);
        } else {
          continue; // Skip invalid date format
        }
        
        if (attendance.containsKey(studentId)) {
          final status = attendance[studentId].toString().toLowerCase();
          if (statusCount.containsKey(status)) {
            statusCount[status] = (statusCount[status] ?? 0) + 1;
          }
          totalDays++;

          dailyAttendance.add({
            'date': DateFormat('yyyy-MM-dd').format(date),
            'status': status,
            'class_id': data['class_id'],
          });
        }
      }

      // Calculate attendance percentage
      double attendancePercentage = totalDays > 0 
          ? (statusCount['hadir'] ?? 0) / totalDays * 100 
          : 0.0;

      // Get student info
      final studentDoc = await _firestore.collection('students').doc(studentId).get();
      final studentData = studentDoc.data();

      return {
        'success': true,
        'student': studentData,
        'stats': {
          'totalDays': totalDays,
          'hadir': statusCount['hadir'] ?? 0,
          'sakit': statusCount['sakit'] ?? 0,
          'izin': statusCount['izin'] ?? 0,
          'alfa': statusCount['alfa'] ?? 0,
          'attendancePercentage': attendancePercentage,
        },
        'dailyAttendance': dailyAttendance,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Get class comparison reports
  static Future<Map<String, dynamic>> getClassComparison({
    required String yearId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      // Get all classes for the year
      final classesSnapshot = await _firestore
          .collection('classes')
          .where('year_id', isEqualTo: yearId)
          .get();

      List<Map<String, dynamic>> classStats = [];

      for (var classDoc in classesSnapshot.docs) {
        final classData = classDoc.data();
        final classId = classDoc.id;

        // Get attendance data for this class
        Query attendanceQuery = _firestore.collection('attendances')
            .where('class_id', isEqualTo: classId);

        if (startDate != null) {
          final startTimestamp = Timestamp.fromDate(DateTime(startDate.year, startDate.month, startDate.day));
          attendanceQuery = attendanceQuery.where('date', isGreaterThanOrEqualTo: startTimestamp);
        }
        if (endDate != null) {
          final endTimestamp = Timestamp.fromDate(DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59));
          attendanceQuery = attendanceQuery.where('date', isLessThanOrEqualTo: endTimestamp);
        }

        final attendanceSnapshot = await attendanceQuery.get();
        final attendances = attendanceSnapshot.docs;

        Map<String, int> statusCount = {
          'hadir': 0,
          'sakit': 0,
          'izin': 0,
          'alfa': 0,
        };

        int totalDays = 0;
        Set<String> uniqueStudents = {};

        for (var doc in attendances) {
          final data = doc.data() as Map<String, dynamic>;
          final attendance = Map<String, dynamic>.from(data['attendance'] ?? {});
          
          totalDays++;
          attendance.forEach((studentId, status) {
            uniqueStudents.add(studentId);
            final statusStr = status.toString().toLowerCase();
            if (statusCount.containsKey(statusStr)) {
              statusCount[statusStr] = (statusCount[statusStr] ?? 0) + 1;
            }
          });
        }

        double attendancePercentage = totalDays > 0 && uniqueStudents.isNotEmpty
            ? (statusCount['hadir'] ?? 0) / (totalDays * uniqueStudents.length) * 100
            : 0.0;

        classStats.add({
          'classId': classId,
          'className': '${classData['grade']}${classData['class_name']}',
          'studentCount': uniqueStudents.length,
          'totalDays': totalDays,
          'hadir': statusCount['hadir'] ?? 0,
          'sakit': statusCount['sakit'] ?? 0,
          'izin': statusCount['izin'] ?? 0,
          'alfa': statusCount['alfa'] ?? 0,
          'attendancePercentage': attendancePercentage,
        });
      }

      // Sort by attendance percentage (descending)
      classStats.sort((a, b) => (b['attendancePercentage'] as double)
          .compareTo(a['attendancePercentage'] as double));

      return {
        'success': true,
        'data': classStats,
        'summary': {
          'totalClasses': classStats.length,
          'averageAttendance': classStats.isNotEmpty
              ? classStats.fold<double>(0.0, (sum, cls) => sum + (cls['attendancePercentage'] as double)) / classStats.length
              : 0.0,
        }
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'data': [],
        'summary': {},
      };
    }
  }

  /// Get teacher performance analytics
  static Future<Map<String, dynamic>> getTeacherPerformance({
    required String teacherId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      Query query = _firestore.collection('attendances')
          .where('teacher_id', isEqualTo: teacherId);

      if (startDate != null) {
        final startTimestamp = Timestamp.fromDate(DateTime(startDate.year, startDate.month, startDate.day));
        query = query.where('date', isGreaterThanOrEqualTo: startTimestamp);
      }
      if (endDate != null) {
        final endTimestamp = Timestamp.fromDate(DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59));
        query = query.where('date', isLessThanOrEqualTo: endTimestamp);
      }

      final snapshot = await query.get();
      final attendances = snapshot.docs;

      Map<String, int> statusCount = {
        'hadir': 0,
        'sakit': 0,
        'izin': 0,
        'alfa': 0,
      };

      int totalClasses = 0;
      Set<String> uniqueStudents = {};
      Map<String, int> classAttendance = {};

      for (var doc in attendances) {
        final data = doc.data() as Map<String, dynamic>;
        final attendance = Map<String, dynamic>.from(data['attendance'] ?? {});
        final classId = data['class_id'];
        
        totalClasses++;
        attendance.forEach((studentId, status) {
          uniqueStudents.add(studentId);
          final statusStr = status.toString().toLowerCase();
          if (statusCount.containsKey(statusStr)) {
            statusCount[statusStr] = (statusCount[statusStr] ?? 0) + 1;
          }
        });

        // Track attendance by class
        if (!classAttendance.containsKey(classId)) {
          classAttendance[classId] = 0;
        }
        classAttendance[classId] = (classAttendance[classId] ?? 0) + attendance.length;
      }

      // Get teacher info
      final teacherQuery = await _firestore
          .collection('teachers')
          .where('nuptk', isEqualTo: teacherId)
          .limit(1)
          .get();

      final teacherData = teacherQuery.docs.isNotEmpty ? teacherQuery.docs.first.data() : {};

      return {
        'success': true,
        'teacher': teacherData,
        'stats': {
          'totalClasses': totalClasses,
          'uniqueStudents': uniqueStudents.length,
          'hadir': statusCount['hadir'] ?? 0,
          'sakit': statusCount['sakit'] ?? 0,
          'izin': statusCount['izin'] ?? 0,
          'alfa': statusCount['alfa'] ?? 0,
          'averageAttendance': totalClasses > 0 
              ? (statusCount['hadir'] ?? 0) / totalClasses 
              : 0.0,
        },
        'classAttendance': classAttendance,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Get summary statistics for dashboard
  static Future<Map<String, dynamic>> getDashboardStats() async {
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0);

      // Get this month's attendance
      final monthlyAttendance = await getAttendanceTrends(
        startDate: startOfMonth,
        endDate: endOfMonth,
      );

      // Get class comparison for current year
      final currentYear = now.year.toString();
      final currentYearMinusOne = now.year.toInt() - 1;
      final currentYearMinusOneStr = currentYearMinusOne.toString();
      final yearQuery = await _firestore
          .collection('school_years')
          .where('name', isGreaterThanOrEqualTo: '$currentYear/')
          .where('name', isLessThan: '$currentYearMinusOneStr/')
          .limit(1)
          .get();

      String? currentYearId;
      if (yearQuery.docs.isNotEmpty) {
        currentYearId = yearQuery.docs.first.id;
      }

      Map<String, dynamic> classComparison = {};
      if (currentYearId != null) {
        classComparison = await getClassComparison(yearId: currentYearId);
      }

      // Get total students
      final studentsSnapshot = await _firestore
          .collection('students')
          .where('status', isEqualTo: 'active')
          .get();

      // Get total teachers
      final teachersSnapshot = await _firestore
          .collection('teachers')
          .get();

      return {
        'success': true,
        'monthlyAttendance': monthlyAttendance,
        'classComparison': classComparison,
        'summary': {
          'totalStudents': studentsSnapshot.docs.length,
          'totalTeachers': teachersSnapshot.docs.length,
          'totalClasses': classComparison['data']?.length ?? 0,
        }
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
} 
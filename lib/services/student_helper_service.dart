import 'package:cloud_firestore/cloud_firestore.dart';

class StudentHelperService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get the current (most recent) enrollment for a student
  static Map<String, dynamic>? getCurrentEnrollment(Map<String, dynamic> studentData) {
    final enrollments = studentData['enrollments'] as List?;
    if (enrollments == null || enrollments.isEmpty) {
      return null;
    }
    
    // Return the most recent enrollment (last in the list)
    return enrollments.last as Map<String, dynamic>;
  }

  /// Get the current class display string for a student
  static String getCurrentClassDisplay(Map<String, dynamic> studentData) {
    final currentEnrollment = getCurrentEnrollment(studentData);
    if (currentEnrollment == null) {
      return 'Kelas: Belum terdaftar';
    }
    
    final grade = currentEnrollment['grade'] ?? '';
    final className = currentEnrollment['class'] ?? '';
    
    if (grade.isEmpty && className.isEmpty) {
      return 'Kelas: Belum terdaftar';
    }
    
    return 'Kelas: $grade$className';
  }

  /// Get the current year for a student
  static String? getCurrentYear(Map<String, dynamic> studentData) {
    final currentEnrollment = getCurrentEnrollment(studentData);
    return currentEnrollment?['year_id'];
  }

  /// Check if a student is currently enrolled in a specific class
  static Future<bool> isEnrolledInClass(Map<String, dynamic> studentData, String classId) async {
    final currentEnrollment = getCurrentEnrollment(studentData);
    if (currentEnrollment == null) return false;
    
    // Query the class to check if the student is in the students array
    final classDoc = await _firestore.collection('classes').doc(classId).get();
    if (!classDoc.exists) return false;
    
    final classData = classDoc.data() as Map<String, dynamic>;
    final students = List<String>.from(classData['students'] ?? []);
    
    return students.contains(studentData['id']);
  }

  /// Get all students with their current enrollment info
  static Future<List<Map<String, dynamic>>> getStudentsWithCurrentEnrollment() async {
    final studentsSnapshot = await _firestore
        .collection('students')
        .where('status', isEqualTo: 'active')
        .get();

    return studentsSnapshot.docs.map((doc) {
      final data = doc.data();
      final currentEnrollment = getCurrentEnrollment(data);
      
      return {
        'id': doc.id,
        ...data,
        'currentEnrollment': currentEnrollment,
        'currentClassDisplay': getCurrentClassDisplay(data),
      };
    }).toList();
  }
} 
import 'package:cloud_firestore/cloud_firestore.dart';

class PromotionService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Promotes students to the next grade and graduates 6th graders
  static Future<Map<String, dynamic>> promoteStudents(String newYearId) async {
    int promotedCount = 0;
    int graduatedCount = 0;
    List<String> errors = [];

    try {
      // Get all active students
      final studentsSnapshot = await _firestore
          .collection('students')
          .where('status', isEqualTo: 'active')
          .get();

      // Get existing classes for the new year
      final classesSnapshot = await _firestore
          .collection('classes')
          .where('year_id', isEqualTo: newYearId)
          .get();

      Map<String, String> existingClasses = {};
      for (var classDoc in classesSnapshot.docs) {
        final data = classDoc.data();
        final key = '${data['grade']}${data['class_name']}';
        existingClasses[key] = classDoc.id;
      }

      // Process each student
      for (var studentDoc in studentsSnapshot.docs) {
        try {
          final studentData = studentDoc.data();
          final enrollments = List<Map<String, dynamic>>.from(studentData['enrollments'] ?? []);
          
          if (enrollments.isEmpty) {
            errors.add('Student ${studentData['name']} has no enrollments');
            continue;
          }

          // Get the latest enrollment
          final latestEnrollment = enrollments.last;
          final currentGrade = int.tryParse(latestEnrollment['grade']?.toString() ?? '') ?? 0;
          final currentClass = latestEnrollment['class']?.toString() ?? '';

          if (currentGrade < 6) {
            // Promote student
            final newGrade = currentGrade + 1;
            final newClassKey = '$newGrade$currentClass';
            
            // Find or create the new class
            String? newClassId = existingClasses[newClassKey];
            if (newClassId == null) {
              // Create new class
              final newClassDoc = await _firestore.collection('classes').add({
                'class_name': currentClass,
                'grade': newGrade.toString(),
                'year_id': newYearId,
                'students': [],
              });
              newClassId = newClassDoc.id;
              existingClasses[newClassKey] = newClassId;
            }

            // Remove student from old class first
            final oldClassQuery = await _firestore
                .collection('classes')
                .where('grade', isEqualTo: currentGrade.toString())
                .where('class_name', isEqualTo: currentClass)
                .where('year_id', isEqualTo: latestEnrollment['year_id'])
                .get();

            for (var oldClassDoc in oldClassQuery.docs) {
              await oldClassDoc.reference.update({
                'students': FieldValue.arrayRemove([studentDoc.id]),
              });
            }

            // Add new enrollment to student
            enrollments.add({
              'grade': newGrade.toString(),
              'class': currentClass,
              'year_id': newYearId,
            });

            // Update student document
            await studentDoc.reference.update({
              'enrollments': enrollments,
            });

            // Add student to new class
            await _firestore.collection('classes').doc(newClassId).update({
              'students': FieldValue.arrayUnion([studentDoc.id]),
            });

            promotedCount++;
          } else {
            // Graduate student (grade 6)
            await studentDoc.reference.update({
              'status': 'graduated',
            });

            // Remove student from all current classes
            for (var enrollment in enrollments) {
              final classQuery = await _firestore
                  .collection('classes')
                  .where('grade', isEqualTo: enrollment['grade'])
                  .where('class_name', isEqualTo: enrollment['class'])
                  .where('year_id', isEqualTo: enrollment['year_id'])
                  .get();

              for (var classDoc in classQuery.docs) {
                await classDoc.reference.update({
                  'students': FieldValue.arrayRemove([studentDoc.id]),
                });
              }
            }

            graduatedCount++;
          }
        } catch (e) {
          errors.add('Error processing student ${studentDoc.data()['name']}: $e');
        }
      }

      return {
        'success': true,
        'promotedCount': promotedCount,
        'graduatedCount': graduatedCount,
        'errors': errors,
      };
    } catch (e) {
      return {
        'success': false,
        'promotedCount': promotedCount,
        'graduatedCount': graduatedCount,
        'errors': ['General error: $e'],
      };
    }
  }

  /// Get available school years for promotion
  static Future<List<Map<String, dynamic>>> getAvailableYears() async {
    try {
      final snapshot = await _firestore.collection('school_years').get();
      return snapshot.docs.map((doc) => {
        'id': doc.id,
        'name': doc.data()['name'],
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get promotion preview (counts without actually promoting)
  static Future<Map<String, dynamic>> getPromotionPreview(String newYearId) async {
    int toPromote = 0;
    int toGraduate = 0;

    try {
      final studentsSnapshot = await _firestore
          .collection('students')
          .where('status', isEqualTo: 'active')
          .get();

      for (var studentDoc in studentsSnapshot.docs) {
        final studentData = studentDoc.data();
        final enrollments = List<Map<String, dynamic>>.from(studentData['enrollments'] ?? []);
        
        if (enrollments.isNotEmpty) {
          final latestEnrollment = enrollments.last;
          final currentGrade = int.tryParse(latestEnrollment['grade']?.toString() ?? '') ?? 0;

          if (currentGrade < 6) {
            toPromote++;
          } else {
            toGraduate++;
          }
        }
      }

      return {
        'toPromote': toPromote,
        'toGraduate': toGraduate,
      };
    } catch (e) {
      return {
        'toPromote': 0,
        'toGraduate': 0,
        'error': e.toString(),
      };
    }
  }
} 
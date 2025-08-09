import 'package:cloud_firestore/cloud_firestore.dart';

class PromotionService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Promotes students to the next grade and graduates 6th graders
  static Future<Map<String, dynamic>> promoteStudents(String newYearId, {required String schoolId}) async {
    int promotedCount = 0;
    int graduatedCount = 0;
    List<String> errors = [];

    try {
      // Archive classes from the latest past year (immediately before newYearId) with enrolled student snapshot
      try {
        // Load new year to get its start_date
        final newYearDoc = await _firestore.collection('school_years').doc(newYearId).get();
        final newYearData = newYearDoc.data();
        DateTime? newYearStart;
        if (newYearData != null && newYearData['start_date'] is Timestamp) {
          newYearStart = (newYearData['start_date'] as Timestamp).toDate();
        }

        String? previousYearId;
        if (newYearStart != null) {
          // Find the immediate previous year
          final prevYearQuery = await _firestore
              .collection('school_years')
              .where('start_date', isLessThan: newYearStart)
              .orderBy('start_date', descending: true)
              .limit(1)
              .get();
          if (prevYearQuery.docs.isNotEmpty) {
            previousYearId = prevYearQuery.docs.first.id;
          }
        }

        if (previousYearId != null) {
          final priorClassesSnapshot = await _firestore
              .collection('classes')
              .where('school_id', isEqualTo: schoolId)
              .where('year_id', isEqualTo: previousYearId)
              .get();

          for (final classDoc in priorClassesSnapshot.docs) {
            final cdata = classDoc.data();
            final existingArchived = cdata['archived'] == true;
            final studentIds = List<String>.from(cdata['students'] ?? const []);

            // Build archived_enrollments from student enrollment field
            List<Map<String, dynamic>> archivedEnrollments = [];
            if (studentIds.isNotEmpty) {
              const batchSize = 10; // Firestore whereIn limit
              for (int i = 0; i < studentIds.length; i += batchSize) {
                final batch = studentIds.sublist(i, i + batchSize > studentIds.length ? studentIds.length : i + batchSize);
                final studentsBatch = await _firestore
                    .collection('students')
                    .where(FieldPath.documentId, whereIn: batch)
                    .get();
                for (final s in studentsBatch.docs) {
                  final sdata = s.data();
                  final enrollments = List<Map<String, dynamic>>.from(sdata['enrollments'] ?? []);
                  final matched = enrollments.where((e) => e['year_id'] == previousYearId).toList();
                  if (matched.isNotEmpty) {
                    // Store only the latest enrollment for that year
                    final last = matched.last;
                    archivedEnrollments.add({
                      'student_id': s.id,
                      'name': sdata['name'] ?? '',
                      'grade': last['grade'] ?? '',
                      'class': last['class'] ?? '',
                      'year_id': last['year_id'] ?? previousYearId,
                    });
                  }
                }
              }
            }

            if (!existingArchived) {
              await classDoc.reference.update({
                'archived': true,
                'archived_at': FieldValue.serverTimestamp(),
                'archived_students': studentIds,
                'archived_enrollments': archivedEnrollments,
              });
            } else {
              // Refresh snapshot data if exists
              await classDoc.reference.update({
                'archived_students': studentIds,
                'archived_enrollments': archivedEnrollments,
              });
            }
          }
        }
      } catch (e) {
        errors.add('Archiving previous year classes failed: $e');
      }

      // Get all active students for the school
      final studentsSnapshot = await _firestore
          .collection('students')
          .where('status', isEqualTo: 'active')
          .where('school_id', isEqualTo: schoolId)
          .get();

      // Get existing classes for the new year within the same school
      final classesSnapshot = await _firestore
          .collection('classes')
          .where('year_id', isEqualTo: newYearId)
          .where('school_id', isEqualTo: schoolId)
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
                'school_id': schoolId,
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
                .where('school_id', isEqualTo: schoolId)
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
                  .where('school_id', isEqualTo: schoolId)
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
  static Future<List<Map<String, dynamic>>> getAvailableYears({String? schoolId}) async {
    try {
      // If schoolId is provided, prefer years referenced by classes of that school
      if (schoolId != null && schoolId.isNotEmpty) {
        final classYearsSnapshot = await _firestore
            .collection('classes')
            .where('school_id', isEqualTo: schoolId)
            .get();

        final yearIds = classYearsSnapshot.docs
            .map((d) => (d.data()['year_id'] as String?))
            .where((id) => id != null && id!.isNotEmpty)
            .toSet()
            .toList();

        if (yearIds.isNotEmpty) {
          // Fetch only those school_years
          List<Map<String, dynamic>> years = [];
          const batchSize = 10; // Firestore whereIn limit
          for (int i = 0; i < yearIds.length; i += batchSize) {
            final batch = yearIds.sublist(i, i + batchSize > yearIds.length ? yearIds.length : i + batchSize);
            final snapshot = await _firestore
                .collection('school_years')
                .where(FieldPath.documentId, whereIn: batch)
                .get();
            years.addAll(snapshot.docs.map((doc) => {
                  'id': doc.id,
                  'name': doc.data()['name'],
                }));
          }
          years.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
          return years;
        }
      }

      // Fallback: return all years
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
  static Future<Map<String, dynamic>> getPromotionPreview(String newYearId, {required String schoolId}) async {
    int toPromote = 0;
    int toGraduate = 0;

    try {
      final studentsSnapshot = await _firestore
          .collection('students')
          .where('status', isEqualTo: 'active')
          .where('school_id', isEqualTo: schoolId)
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
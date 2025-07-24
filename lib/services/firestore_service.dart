import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/class_model.dart';
import '../models/schedule_model.dart';

class FirestoreService {
  final _db = FirebaseFirestore.instance;

  // Create or update a class
  Future<void> setClass(SchoolClass schoolClass) async {
    await _db.collection('classes').doc(schoolClass.id).set(schoolClass.toMap());
  }

  // Create or update a schedule
  Future<void> setSchedule(Schedule schedule) async {
    await _db.collection('schedules').doc(schedule.id).set(schedule.toMap());
  }

  // Get all students for a class (by class name and year)
  Future<List<String>> getStudentIdsForClass(String className, int year) async {
    final query = await _db
        .collection('students')
        .where('class', isEqualTo: className)
        .where('year', isEqualTo: year)
        .get();
    return query.docs.map((doc) => doc.id).toList();
  }
}
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/student_helper_service.dart';

class ClassStudentsScreen extends StatelessWidget {
  final String className;
  final String grade;
  final String year;
  final List<String> studentIds;

  const ClassStudentsScreen({
    Key? key,
    required this.className,
    required this.grade,
    required this.year,
    required this.studentIds,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Siswa di Kelas $grade$className ($year)'),
      ),
      body: studentIds.isEmpty
          ? const Center(child: Text('Tidak ada siswa di kelas ini.'))
          : FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance
            .collection('students')
            .where(FieldPath.documentId, whereIn: studentIds)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Tidak ada siswa ditemukan.'));
          }
          // Filter students to only show those whose current enrollment matches this class
          final allStudents = snapshot.data!.docs;
          final currentStudents = <QueryDocumentSnapshot>[];
          
                    for (var studentDoc in allStudents) {
            final studentData = studentDoc.data() as Map<String, dynamic>;
            final currentEnrollment = StudentHelperService.getCurrentEnrollment(studentData);
            
            if (currentEnrollment != null) {
              final currentGrade = currentEnrollment['grade']?.toString() ?? '';
              final currentClass = currentEnrollment['class']?.toString() ?? '';
              final currentYear = currentEnrollment['year_id']?.toString() ?? '';
              
              // Normalize class names for comparison (handle empty class names)
              final normalizedCurrentClass = currentClass.trim();
              final normalizedClassName = className.trim();
              
              // Check if this student's current enrollment matches this class
              if (currentGrade == grade && 
                  (normalizedCurrentClass == normalizedClassName || 
                   (normalizedCurrentClass.isEmpty && normalizedClassName.isEmpty)) &&
                  currentYear == year) {
                currentStudents.add(studentDoc);
              }
            }
          }
          
          if (currentStudents.isEmpty) {
            return const Center(child: Text('Tidak ada siswa aktif di kelas ini.'));
          }
          
          return ListView.builder(
            itemCount: currentStudents.length,
            itemBuilder: (context, index) {
              final data = currentStudents[index].data() as Map<String, dynamic>;
              return ListTile(
                title: Text(data['name'] ?? ''),
                subtitle: Text('Jenis Kelamin: ${data['gender'] ?? '-'} | No. Hp Orang Tua: ${data['parent_phone'] ?? '-'}'),
              );
            },
          );
        },
      ),
    );
  }
}
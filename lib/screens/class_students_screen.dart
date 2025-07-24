import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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
          final students = snapshot.data!.docs;
          return ListView.builder(
            itemCount: students.length,
            itemBuilder: (context, index) {
              final data = students[index].data() as Map<String, dynamic>;
              return ListTile(
                title: Text(data['name'] ?? ''),
                subtitle: Text('NISN: ${data['nisn'] ?? ''}'),
              );
            },
          );
        },
      ),
    );
  }
}
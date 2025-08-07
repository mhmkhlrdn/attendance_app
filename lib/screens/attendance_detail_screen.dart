import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AttendanceDetailScreen extends StatelessWidget {
  final Map<String, dynamic> attendanceData;
  final String attendanceId;
  const AttendanceDetailScreen({Key? key, required this.attendanceData, required this.attendanceId}) : super(key: key);

  /// Load students in batches to handle Firestore's whereIn limit of 10 items
  Future<List<QueryDocumentSnapshot>> _loadStudentsInBatches(List<String> studentIds) async {
    List<QueryDocumentSnapshot> allStudentDocs = [];
    
    // Firestore whereIn has a limit of 10 items, so we need to batch the queries
    const batchSize = 10;
    for (int i = 0; i < studentIds.length; i += batchSize) {
      final end = (i + batchSize < studentIds.length) ? i + batchSize : studentIds.length;
      final batchIds = studentIds.sublist(i, end);
      
      final batchQuery = await FirebaseFirestore.instance
        .collection('students')
        .where(FieldPath.documentId, whereIn: batchIds)
        .get();
      
      allStudentDocs.addAll(batchQuery.docs);
    }
    
    return allStudentDocs;
  }

  @override
  Widget build(BuildContext context) {
    final attendance = attendanceData['attendance'] as Map?;
    if (attendance == null || attendance.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detail Presensi')),
        body: const Center(child: Text('Tidak ada data presensi.')),
      );
    }
    final studentIds = attendance.keys.map((key) => key.toString()).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Detail Presensi')),
      body: FutureBuilder<List<QueryDocumentSnapshot>>(
        future: _loadStudentsInBatches(studentIds),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Tidak ada data siswa.'));
          }
          final students = {for (var doc in snapshot.data!) doc.id: (doc.data() as Map<String, dynamic>)['name'] ?? doc.id};
          // Group students by status
          final Map<String, List<String>> statusMap = {
            'hadir': [], 'sakit': [], 'izin': [], 'alfa': []
          };
          attendance.forEach((studentId, status) {
            final name = students[studentId] ?? studentId;
            if (statusMap.containsKey(status)) {
              statusMap[status]!.add(name);
            }
          });
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildStatusSection('Hadir', statusMap['hadir']!),
              _buildStatusSection('Sakit', statusMap['sakit']!),
              _buildStatusSection('Izin', statusMap['izin']!),
              _buildStatusSection('Alfa', statusMap['alfa']!),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusSection(String status, List<String> names) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        title: Text('$status (${names.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
        children: names.isEmpty
            ? [const ListTile(title: Text('Tidak ada'))]
            : names.map((name) => ListTile(title: Text(name))).toList(),
      ),
    );
  }
} 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class StudentDetailScreen extends StatelessWidget {
  final String studentId;
  const StudentDetailScreen({Key? key, required this.studentId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Siswa'),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('students').doc(studentId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Data siswa tidak ditemukan.'));
          }
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final name = data['name'] ?? '-';
          final gender = data['gender'] ?? '-';
          final phone = data['parent_phone'] ?? '-';
          final enrollments = data['enrollments'] as List?;
          String kelas = '-';
          String tahun = '-';
          if (enrollments != null && enrollments.isNotEmpty) {
            final enrollment = enrollments.first as Map<String, dynamic>;
            final grade = enrollment['grade'] ?? '';
            final className = enrollment['class'] ?? '';
            kelas = '$grade$className';
            tahun = enrollment['year_id'] ?? '-';
          }
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: ListTile(
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Text('Jenis Kelamin: $gender'),
                        Text('Kelas: $kelas'),
                        Text('Tahun Ajaran: $tahun'),
                        Text('No. HP Ortu: $phone'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Riwayat Presensi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('attendances')
                        .where('student_ids', arrayContains: studentId)
                        .orderBy('date', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(child: Text('Belum ada data presensi.'));
                      }
                      final records = snapshot.data!.docs;
                      return ListView.builder(
                        itemCount: records.length,
                        itemBuilder: (context, index) {
                          final data = records[index].data() as Map<String, dynamic>;
                          final date = (data['date'] as Timestamp?)?.toDate();
                          final dateStr = date != null ? '${date.day}/${date.month}/${date.year}' : '-';
                          final classId = data['class_id'] ?? '-';
                          final status = (data['attendance'] as Map)[studentId] ?? '-';
                          return ListTile(
                            leading: const Icon(Icons.event_available),
                            title: Text('Tanggal: $dateStr'),
                            subtitle: Text('Status: $status'),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
} 
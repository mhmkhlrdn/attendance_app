import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DataMigrationScreen extends StatefulWidget {
  const DataMigrationScreen({Key? key}) : super(key: key);

  @override
  State<DataMigrationScreen> createState() => _DataMigrationScreenState();
}

class _DataMigrationScreenState extends State<DataMigrationScreen> {
  bool _isMigrating = false;
  String _status = '';
  int _progress = 0;
  int _total = 0;

  Future<void> _migrateData() async {
    setState(() {
      _isMigrating = true;
      _status = 'Starting migration...';
      _progress = 0;
    });

    try {
      // First, create schools collection if it doesn't exist
      await _createSchools();
      
      // Migrate teachers
      await _migrateTeachers();
      
      // Migrate classes
      await _migrateClasses();
      
      // Migrate students
      await _migrateStudents();
      
      // Migrate schedules
      await _migrateSchedules();
      
      // Migrate attendances
      await _migrateAttendances();
      
      setState(() {
        _status = 'Migration completed successfully!';
      });
    } catch (e) {
      setState(() {
        _status = 'Error during migration: $e';
      });
    } finally {
      setState(() {
        _isMigrating = false;
      });
    }
  }

  Future<void> _createSchools() async {
    setState(() {
      _status = 'Creating schools collection...';
    });

    final schools = [
      {
        'id': 'school_1',
        'name': 'SDN Kurjati',
        'address': 'Desa Tanjungkarang',
        'principal': 'Kepala Sekolah 1',
      },
      {
        'id': 'school_2',
        'name': 'SDN Tanjungsari',
        'address': 'Desa Tanjungkarang',
        'principal': 'Kepala Sekolah 2',
      },
      {
        'id': 'school_3',
        'name': 'SDN ',
        'address': 'Desa Tanjungkarang',
        'principal': 'Kepala Sekolah 3',
      },
    ];

    for (var school in schools) {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(school['id'])
          .set({
        'name': school['name'],
        'address': school['address'],
        'principal': school['principal'],
        'created_at': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _migrateTeachers() async {
    setState(() {
      _status = 'Migrating teachers...';
    });

    final teachersQuery = await FirebaseFirestore.instance.collection('teachers').get();
    _total = teachersQuery.docs.length;

    for (int i = 0; i < teachersQuery.docs.length; i++) {
      final doc = teachersQuery.docs[i];
      final data = doc.data();
      
      if (data['school_id'] == null) {
        // Assign to school_1 by default (you can change this logic)
        await doc.reference.update({
          'school_id': 'school_1',
        });
      }
      
      setState(() {
        _progress = i + 1;
      });
    }
  }

  Future<void> _migrateClasses() async {
    setState(() {
      _status = 'Migrating classes...';
    });

    final classesQuery = await FirebaseFirestore.instance.collection('classes').get();
    _total = classesQuery.docs.length;

    for (int i = 0; i < classesQuery.docs.length; i++) {
      final doc = classesQuery.docs[i];
      final data = doc.data();
      
      if (data['school_id'] == null) {
        // Assign to school_1 by default (you can change this logic)
        await doc.reference.update({
          'school_id': 'school_1',
        });
      }
      
      setState(() {
        _progress = i + 1;
      });
    }
  }

  Future<void> _migrateStudents() async {
    setState(() {
      _status = 'Migrating students...';
    });

    final studentsQuery = await FirebaseFirestore.instance.collection('students').get();
    _total = studentsQuery.docs.length;

    for (int i = 0; i < studentsQuery.docs.length; i++) {
      final doc = studentsQuery.docs[i];
      final data = doc.data();
      
      if (data['school_id'] == null) {
        // Assign to school_1 by default (you can change this logic)
        await doc.reference.update({
          'school_id': 'school_1',
        });
      }
      
      setState(() {
        _progress = i + 1;
      });
    }
  }

  Future<void> _migrateSchedules() async {
    setState(() {
      _status = 'Migrating schedules...';
    });

    final schedulesQuery = await FirebaseFirestore.instance.collection('schedules').get();
    _total = schedulesQuery.docs.length;

    for (int i = 0; i < schedulesQuery.docs.length; i++) {
      final doc = schedulesQuery.docs[i];
      final data = doc.data();
      
      if (data['school_id'] == null) {
        // Assign to school_1 by default (you can change this logic)
        await doc.reference.update({
          'school_id': 'school_1',
        });
      }
      
      setState(() {
        _progress = i + 1;
      });
    }
  }

  Future<void> _migrateAttendances() async {
    setState(() {
      _status = 'Migrating attendances...';
    });

    final attendancesQuery = await FirebaseFirestore.instance.collection('attendances').get();
    _total = attendancesQuery.docs.length;

    for (int i = 0; i < attendancesQuery.docs.length; i++) {
      final doc = attendancesQuery.docs[i];
      final data = doc.data();
      
      if (data['school_id'] == null) {
        // Assign to school_1 by default (you can change this logic)
        await doc.reference.update({
          'school_id': 'school_1',
        });
      }
      
      setState(() {
        _progress = i + 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Migration'),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'School-Based Data Migration',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This will add school_id to all existing data and create the schools collection. '
                      'All existing data will be assigned to "SDN Tanjungkarang 1" by default.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    if (_isMigrating) ...[
                      LinearProgressIndicator(
                        value: _total > 0 ? _progress / _total : 0,
                      ),
                      const SizedBox(height: 8),
                      Text('Progress: $_progress / $_total'),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      _status,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isMigrating ? null : _migrateData,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isMigrating
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      'Start Migration',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
} 
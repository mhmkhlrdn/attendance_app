import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CreateScheduleScreen extends StatefulWidget {
  final Map<String, dynamic>? schedule; // For edit mode
  final Map<String, String>? userInfo; // For school_id
  const CreateScheduleScreen({Key? key, this.schedule, this.userInfo}) : super(key: key);

  @override
  State<CreateScheduleScreen> createState() => _CreateScheduleScreenState();
}

class _CreateScheduleScreenState extends State<CreateScheduleScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedClassId;
  String? _selectedTeacherId;
  final TextEditingController _subjectController = TextEditingController();
  String _scheduleType = 'subject_specific'; // 'daily_morning' or 'subject_specific'
  String? _selectedDay;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isSaving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (widget.schedule != null) {
      // Edit mode - populate fields with existing data
      _selectedClassId = widget.schedule!['class_id'];
      _selectedTeacherId = widget.schedule!['teacher_id'];
      _subjectController.text = widget.schedule!['subject'] ?? '';
      _scheduleType = widget.schedule!['schedule_type'] ?? 'subject_specific';
      _selectedDay = widget.schedule!['day_of_week'];
      
      // Parse time string to extract times
      final timeString = widget.schedule!['time'] ?? '';
      if (timeString.isNotEmpty) {
        if (_scheduleType == 'daily_morning') {
          // For daily morning, time is just "06:30"
          final timeParts = timeString.split(':');
          if (timeParts.length == 2) {
            _startTime = TimeOfDay(
              hour: int.parse(timeParts[0]),
              minute: int.parse(timeParts[1]),
            );
            _endTime = TimeOfDay(
              hour: int.parse(timeParts[0]),
              minute: int.parse(timeParts[1]) + 30, // 30 minutes duration
            );
          }
        } else {
          // For subject-specific, parse day and time range
          final parts = timeString.split(' ');
          if (parts.length >= 2) {
            _selectedDay = parts[0];
            final timeRange = parts[1];
            final timeParts = timeRange.split('-');
            if (timeParts.length == 2) {
              final startParts = timeParts[0].split(':');
              final endParts = timeParts[1].split(':');
              if (startParts.length == 2 && endParts.length == 2) {
                _startTime = TimeOfDay(
                  hour: int.parse(startParts[0]),
                  minute: int.parse(startParts[1]),
                );
                _endTime = TimeOfDay(
                  hour: int.parse(endParts[0]),
                  minute: int.parse(endParts[1]),
                );
              }
            }
          }
        }
      }
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.schedule != null ? 'Edit Jadwal' : 'Buat Jadwal Baru'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Schedule Type Selection
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Jenis Jadwal',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      RadioListTile<String>(
                        title: const Text('Presensi Pagi Harian'),
                        subtitle: const Text('Presensi setiap pagi pukul 06:30'),
                        value: 'daily_morning',
                        groupValue: _scheduleType,
                        onChanged: (value) {
                          setState(() {
                            _scheduleType = value!;
                            // Set default time for daily morning
                            _startTime = const TimeOfDay(hour: 6, minute: 30);
                            _endTime = const TimeOfDay(hour: 7, minute: 0);
                            _selectedDay = null;
                            // Set the subject text for daily morning
                            _subjectController.text = 'Presensi Pagi Harian';
                          });
                        },
                      ),
                      RadioListTile<String>(
                        title: const Text('Mata Pelajaran Spesifik'),
                        subtitle: const Text('Jadwal untuk mata pelajaran tertentu (seperti Olahraga)'),
                        value: 'subject_specific',
                        groupValue: _scheduleType,
                        onChanged: (value) {
                          setState(() {
                            _scheduleType = value!;
                            _startTime = null;
                            _endTime = null;
                            _selectedDay = null;
                            // Clear the subject text for subject-specific
                            _subjectController.clear();
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Class Selection
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pilih Kelas',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('classes').where('school_id', isEqualTo: widget.userInfo?['school_id'] ?? 'school_1').snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            return const Text('Tidak ada kelas tersedia.');
                          }
                          final classes = snapshot.data!.docs;
                          final classOptions = classes.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            return DropdownMenuItem(
                              value: doc.id,
                              child: Text('${data['grade']} ${data['class_name']}'),
                            );
                          }).toList()
                            ..sort((a, b) => ((a.child as Text).data ?? '').compareTo((b.child as Text).data ?? ''));
                          return DropdownButtonFormField<String>(
                            value: _selectedClassId,
                            decoration: const InputDecoration(
                              labelText: 'Kelas',
                              border: OutlineInputBorder(),
                            ),
                            items: classOptions,
                            onChanged: (value) => setState(() => _selectedClassId = value),
                            validator: (value) => value == null ? 'Pilih kelas' : null,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Teacher Selection
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pilih Guru',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('teachers').where('school_id', isEqualTo: widget.userInfo!['school_id']).snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            return const Text('Tidak ada guru tersedia.');
                          }
                          final teachers = snapshot.data!.docs;
                          final teacherOptions = teachers.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            return DropdownMenuItem(
                              value: doc.id,
                              child: Text('${data['name']} (${data['nuptk']})'),
                            );
                          }).toList()
                            ..sort((a, b) => ((a.child as Text).data ?? '').compareTo((b.child as Text).data ?? ''));
                          return DropdownButtonFormField<String>(
                            value: _selectedTeacherId,
                            decoration: const InputDecoration(
                              labelText: 'Guru',
                              border: OutlineInputBorder(),
                            ),
                            items: teacherOptions,
                            onChanged: (value) => setState(() => _selectedTeacherId = value),
                            validator: (value) => value == null ? 'Pilih guru' : null,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Subject (only for subject-specific schedules)
              if (_scheduleType == 'subject_specific') ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mata Pelajaran',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _subjectController,
                          decoration: const InputDecoration(
                            labelText: 'Nama Mata Pelajaran',
                            border: OutlineInputBorder(),
                            hintText: 'Contoh: Olahraga, Matematika, dll.',
                          ),
                          validator: (value) => value?.trim().isEmpty == true ? 'Masukkan nama mata pelajaran' : null,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                // For daily morning, show a disabled field with the preset text
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mata Pelajaran',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _subjectController,
                          enabled: false,
                          decoration: InputDecoration(
                            labelText: 'Nama Mata Pelajaran',
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.grey[200],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Day Selection (only for subject-specific schedules)
              if (_scheduleType == 'subject_specific') ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Hari',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _selectedDay,
                          decoration: const InputDecoration(
                            labelText: 'Pilih Hari',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Senin', child: Text('Senin')),
                            DropdownMenuItem(value: 'Selasa', child: Text('Selasa')),
                            DropdownMenuItem(value: 'Rabu', child: Text('Rabu')),
                            DropdownMenuItem(value: 'Kamis', child: Text('Kamis')),
                            DropdownMenuItem(value: 'Jumat', child: Text('Jumat')),
                            DropdownMenuItem(value: 'Sabtu', child: Text('Sabtu')),
                            DropdownMenuItem(value: 'Minggu', child: Text('Minggu')),
                          ],
                          onChanged: (value) => setState(() => _selectedDay = value),
                          validator: (value) => value == null ? 'Pilih hari' : null,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Time Selection
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _scheduleType == 'daily_morning' ? 'Waktu Presensi Pagi' : 'Waktu Mata Pelajaran',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ListTile(
                              title: const Text('Waktu Mulai'),
                              subtitle: Text(_startTime?.format(context) ?? 'Pilih waktu'),
                              trailing: const Icon(Icons.access_time),
                              onTap: () => _pickTime(isStart: true),
                            ),
                          ),
                          if (_scheduleType == 'subject_specific') ...[
                            Expanded(
                              child: ListTile(
                                title: const Text('Waktu Selesai'),
                                subtitle: Text(_endTime?.format(context) ?? 'Pilih waktu'),
                                trailing: const Icon(Icons.access_time),
                                onTap: () => _pickTime(isStart: false),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (_scheduleType == 'daily_morning') ...[
                        const SizedBox(height: 8),
                        Text(
                          'Presensi pagi akan berlangsung selama 120 menit',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              if (_message != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _message!.contains('berhasil') ? Colors.green[100] : Colors.red[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _message!,
                    style: TextStyle(
                      color: _message!.contains('berhasil') ? Colors.green[800] : Colors.red[800],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              _isSaving
                  ? const Center(child: CircularProgressIndicator())
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          if (_formKey.currentState!.validate() && 
                              (_scheduleType == 'daily_morning' && _startTime != null) ||
                              (_scheduleType == 'subject_specific' && _selectedDay != null && _startTime != null && _endTime != null)) {
                            setState(() => _isSaving = true);
                            try {
                              String timeString;
                              if (_scheduleType == 'daily_morning') {
                                timeString = _startTime!.format(context);
                                // Set subject automatically for daily morning
                                _subjectController.text = 'Presensi Pagi Harian';
                              } else {
                                timeString = '$_selectedDay ${_startTime!.format(context)}-${_endTime!.format(context)}';
                              }
                              
                              final scheduleData = {
                                'teacher_id': _selectedTeacherId,
                                'subject': _subjectController.text.trim(),
                                'class_id': _selectedClassId,
                                'time': timeString,
                                'schedule_type': _scheduleType,
                                'day_of_week': _selectedDay,
                                'school_id': widget.userInfo!['school_id'],
                              };
                              
                              if (widget.schedule != null && widget.schedule!['id'] != null) {
                                // Edit mode
                                await FirebaseFirestore.instance
                                    .collection('schedules')
                                    .doc(widget.schedule!['id'])
                                    .update(scheduleData);
                                setState(() {
                                  _isSaving = false;
                                  _message = 'Jadwal berhasil diperbarui!';
                                });
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Jadwal berhasil diperbarui!'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                  // Navigate back after a short delay
                                  Future.delayed(const Duration(seconds: 1), () {
                                    if (mounted) {
                                      Navigator.pop(context);
                                    }
                                  });
                                }
                              } else {
                                // Create mode
                                await FirebaseFirestore.instance.collection('schedules').add(scheduleData);
                                setState(() {
                                  _isSaving = false;
                                  _message = 'Jadwal berhasil dibuat!';
                                });
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Jadwal berhasil dibuat!'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                  // Navigate back after a short delay
                                  Future.delayed(const Duration(seconds: 1), () {
                                    if (mounted) {
                                      Navigator.pop(context);
                                    }
                                  });
                                }
                              }
                            } catch (e) {
                              setState(() {
                                _isSaving = false;
                                _message = 'Gagal: $e';
                              });
                            }
                          }
                        },
                        icon: const Icon(Icons.save),
                        label: Text(widget.schedule != null ? 'Update Jadwal' : 'Buat Jadwal'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

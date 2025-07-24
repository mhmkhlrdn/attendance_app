import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CreateScheduleScreen extends StatefulWidget {
  final Map<String, dynamic>? schedule; // For edit mode
  const CreateScheduleScreen({Key? key, this.schedule}) : super(key: key);

  @override
  State<CreateScheduleScreen> createState() => _CreateScheduleScreenState();
}

class _CreateScheduleScreenState extends State<CreateScheduleScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedClassId;
  String? _selectedTeacherId;
  final TextEditingController _subjectController = TextEditingController();
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
      
      // Parse time string to extract day and times
      final timeString = widget.schedule!['time'] ?? '';
      if (timeString.isNotEmpty) {
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
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(widget.schedule != null ? 'Edit Jadwal' : 'Buat Jadwal'),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('classes').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final classes = snapshot.data!.docs;
                      return DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _selectedClassId,
                        items: classes.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final label = 'Kelas ${data['grade']}${data['class_name']} (${data['year_id']})';
                          return DropdownMenuItem<String>(
                            value: doc.id,
                            child: Text(label),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedClassId = value;
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Kelas',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          prefixIcon: const Icon(Icons.class_outlined),
                        ),
                        validator: (value) => value == null ? 'Pilih kelas' : null,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('teachers').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final teachers = snapshot.data!.docs;
                      return DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _selectedTeacherId,
                        items: teachers.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final label = '${data['name']} (${data['nuptk']})';
                          return DropdownMenuItem<String>(
                            value: doc['nuptk'],
                            child: Text(label),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedTeacherId = value;
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Guru',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                        validator: (value) => value == null ? 'Pilih guru' : null,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _subjectController,
                    decoration: InputDecoration(
                      labelText: 'Mata Pelajaran',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.book_outlined),
                    ),
                    validator: (value) => value == null || value.isEmpty ? 'Masukkan mata pelajaran' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _selectedDay,
                    items: const [
                      DropdownMenuItem(value: 'Senin', child: Text('Senin')),
                      DropdownMenuItem(value: 'Selasa', child: Text('Selasa')),
                      DropdownMenuItem(value: 'Rabu', child: Text('Rabu')),
                      DropdownMenuItem(value: 'Kamis', child: Text('Kamis')),
                      DropdownMenuItem(value: 'Jumat', child: Text('Jumat')),
                      DropdownMenuItem(value: 'Sabtu', child: Text('Sabtu')),
                      DropdownMenuItem(value: 'Minggu', child: Text('Minggu')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedDay = value;
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Hari',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.calendar_today_outlined),
                    ),
                    validator: (value) => value == null ? 'Pilih hari' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _pickTime(isStart: true),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Jam Mulai',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: Text(_startTime != null ? _startTime!.format(context) : 'Pilih...'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: InkWell(
                          onTap: () => _pickTime(isStart: false),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Jam Selesai',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: Text(_endTime != null ? _endTime!.format(context) : 'Pilih...'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _isSaving
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton.icon(
                    onPressed: () async {
                      if (_formKey.currentState!.validate() && _selectedDay != null && _startTime != null && _endTime != null) {
                        setState(() => _isSaving = true);
                        try {
                          final timeString = '$_selectedDay ${_startTime!.format(context)}-${_endTime!.format(context)}';
                          final scheduleData = {
                            'teacher_id': _selectedTeacherId,
                            'subject': _subjectController.text.trim(),
                            'class_id': _selectedClassId,
                            'time': timeString,
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
                          } else {
                            // Create mode
                            await FirebaseFirestore.instance.collection('schedules').add(scheduleData);
                            setState(() {
                              _isSaving = false;
                              _message = 'Jadwal berhasil dibuat!';
                            });
                          }
                        } catch (e) {
                          setState(() {
                            _isSaving = false;
                            _message = 'Gagal: $e';
                          });
                        }
                      }
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: Text(widget.schedule != null ? 'Perbarui Jadwal' : 'Buat Jadwal'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _message!.startsWith('Jadwal berhasil') ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

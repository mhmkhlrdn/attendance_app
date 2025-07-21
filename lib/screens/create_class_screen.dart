import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CreateClassScreen extends StatefulWidget {
  const CreateClassScreen({Key? key}) : super(key: key);

  @override
  State<CreateClassScreen> createState() => _CreateClassScreenState();
}

class _CreateClassScreenState extends State<CreateClassScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _classNameController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _gradeController = TextEditingController();
  bool _isLoading = false;
  String? _message;

  Future<void> _createClass() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    final className = _classNameController.text.trim();
    final year = _yearController.text.trim();
    final grade = _gradeController.text.trim();

    if (year == null) {
      setState(() {
        _isLoading = false;
        _message = 'Year must be a number';
      });
      return;
    }

    try {
      // Query students matching class and year
      final querySnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('class', isEqualTo: className)
          .where('year', isEqualTo: year)
          .where('grade', isEqualTo: grade)
          .get();

      final studentIds = querySnapshot.docs.map((doc) => doc.id).toList();

      // Create or update the class document
      final classDocId = '${grade}${className}-$year';
      await FirebaseFirestore.instance.collection('classes').doc(classDocId).set({
        'class': className,
        'year': year,
        'grade': grade,
        'students': studentIds,
      });

      setState(() {
        _isLoading = false;
        _message = 'Class created successfully with ${studentIds.length} students!';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _message = 'Failed to create class: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Class')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _classNameController,
                decoration: const InputDecoration(labelText: 'Class Name (e.g. A)'),
                validator: (value) => value == null || value.isEmpty ? 'Enter class name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _yearController,
                decoration: const InputDecoration(labelText: 'Year (e.g. 2024)'),
                keyboardType: TextInputType.number,
                validator: (value) => value == null || value.isEmpty ? 'Enter year' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _gradeController,
                decoration: const InputDecoration(labelText: 'Grade (e.g. 5)'),
                validator: (value) => value == null || value.isEmpty ? 'Enter grade' : null,
              ),
              const SizedBox(height: 24),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          _createClass();
                        }
                      },
                      child: const Text('Create Class'),
                    ),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(
                  _message!,
                  style: TextStyle(
                    color: _message!.startsWith('Class created') ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
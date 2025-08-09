import 'package:flutter/material.dart';
import '../services/promotion_service.dart';

class PromotionScreen extends StatefulWidget {
  final Map<String, String> userInfo;
  final String role;

  const PromotionScreen({Key? key, required this.userInfo, this.role = 'admin'}) : super(key: key);

  @override
  State<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends State<PromotionScreen> {
  String? _selectedYearId;
  String? _selectedYearName;
  bool _loading = false;
  bool _promoting = false;
  int _toPromote = 0;
  int _toGraduate = 0;
  String? _error;
  List<Map<String, dynamic>> _years = [];

  @override
  void initState() {
    super.initState();
    _fetchYears();
  }

  Future<void> _fetchYears() async {
    setState(() => _loading = true);
    final years = await PromotionService.getAvailableYears();
    setState(() {
      _years = years;
      _loading = false;
    });
  }

  Future<void> _fetchPreview() async {
    if (_selectedYearId == null) return;
    setState(() => _loading = true);
    final preview = await PromotionService.getPromotionPreview(
      _selectedYearId!,
      schoolId: widget.userInfo['school_id'] ?? '',
    );
    setState(() {
      _toPromote = preview['toPromote'] ?? 0;
      _toGraduate = preview['toGraduate'] ?? 0;
      _error = preview['error'];
      _loading = false;
    });
  }

  Future<void> _promote() async {
    if (_selectedYearId == null) return;
    setState(() => _promoting = true);
    final result = await PromotionService.promoteStudents(
      _selectedYearId!,
      schoolId: widget.userInfo['school_id'] ?? '',
    );
    setState(() => _promoting = false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hasil Promosi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Siswa dipromosikan: ${result['promotedCount']}'),
            Text('Siswa lulus: ${result['graduatedCount']}'),
            if ((result['errors'] as List).isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Error:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...((result['errors'] as List).map((e) => Text(e.toString()))),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
    _fetchPreview();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Promosi Siswa')), 
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pilih Tahun Ajaran Baru:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedYearId,
                    items: _years
                        .map((y) => DropdownMenuItem<String>(
                              value: y['id']?.toString(),
                              child: Text(y['name']?.toString() ?? ''),
                            ))
                        .toList()
                          ..sort((a, b) => ((a.child as Text).data ?? '').compareTo((b.child as Text).data ?? '')),
                    onChanged: (val) {
                      setState(() {
                        _selectedYearId = val;
                        _selectedYearName = _years.firstWhere((y) => y['id'] == val)['name'];
                      });
                      _fetchPreview();
                    },
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 24),
                  if (_selectedYearId != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Tahun Ajaran Baru: $_selectedYearName'),
                            const SizedBox(height: 8),
                            Text('Siswa yang akan dipromosikan: $_toPromote'),
                            Text('Siswa yang akan lulus: $_toGraduate'),
                            if (_error != null) ...[
                              const SizedBox(height: 8),
                              Text('Error: $_error', style: const TextStyle(color: Colors.red)),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.upgrade),
                        label: _promoting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Promosikan Siswa'),
                        onPressed: _promoting ? null : _promote,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
} 
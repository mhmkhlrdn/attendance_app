import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';
import 'dart:convert';

class ArchivedDataScreen extends StatefulWidget {
  final Map<String, String> userInfo;
  const ArchivedDataScreen({Key? key, required this.userInfo}) : super(key: key);

  @override
  State<ArchivedDataScreen> createState() => _ArchivedDataScreenState();
}

class _ArchivedDataScreenState extends State<ArchivedDataScreen> {
  String? _selectedYearId;
  String? _selectedYearName;
  bool _isExporting = false;
  List<Map<String, dynamic>> _cachedClassData = [];

  @override
  void initState() {
    super.initState();
    _loadLatestYear();
  }

  Future<void> _loadLatestYear() async {
    final years = await FirebaseFirestore.instance
        .collection('school_years')
        .orderBy('start_date', descending: true)
        .get();
    if (years.docs.isNotEmpty) {
      final doc = years.docs.first;
      final data = doc.data();
      setState(() {
        _selectedYearId = doc.id;
        _selectedYearName = (data['name'] ?? doc.id).toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Data Arsip',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.indigo[700],
        elevation: 0,
        actions: [
          if (_selectedYearId != null)
            PopupMenuButton<String>(
              onSelected: _exportData,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'excel',
                  child: Row(
                    children: [
                      Icon(Icons.table_chart, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Ekspor Excel'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'pdf',
                  child: Row(
                    children: [
                      Icon(Icons.picture_as_pdf, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Ekspor PDF'),
                    ],
                  ),
                ),
              ],
              child: Container(
                margin: const EdgeInsets.only(right: 16),
                child: const Icon(Icons.file_download, color: Colors.white),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.indigo[700]!,
                  Colors.indigo[50]!,
                ],
                stops: const [0.0, 0.3],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // Header Section
                  Container(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Arsip Data Sekolah',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Lihat dan ekspor data kelas dari tahun ajaran sebelumnya',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.indigo[100],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Content Section
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(30),
                          topRight: Radius.circular(30),
                        ),
                      ),
                      child: Column(
                        children: [
                          // Year Selector Card
                          Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today,
                                        color: Colors.indigo[700],
                                        size: 24,
                                      ),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'Pilih Tahun Ajaran',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  StreamBuilder<QuerySnapshot>(
                                    stream: FirebaseFirestore.instance
                                        .collection('school_years')
                                        .orderBy('start_date', descending: true)
                                        .snapshots(),
                                    builder: (context, snapshot) {
                                      if (!snapshot.hasData) {
                                        return const Center(child: CircularProgressIndicator());
                                      }
                                      final yearOptions = snapshot.data!.docs.map((doc) {
                                        final d = doc.data() as Map<String, dynamic>;
                                        return DropdownMenuItem<String>(
                                          value: doc.id,
                                          child: Text(d['name'] ?? doc.id),
                                        );
                                      }).toList();
                                      return Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.grey[300]!),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: DropdownButtonFormField<String>(
                                          value: _selectedYearId,
                                          items: yearOptions,
                                          onChanged: (v) => setState(() {
                                            _selectedYearId = v;
                                            _selectedYearName = yearOptions
                                                .firstWhere((e) => e.value == v)
                                                .child is Text
                                                ? ((yearOptions.firstWhere((e) => e.value == v).child as Text).data ?? v)
                                                : v;
                                            _cachedClassData.clear();
                                          }),
                                          decoration: const InputDecoration(
                                            border: InputBorder.none,
                                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            hintText: 'Pilih tahun ajaran...',
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          // Classes List
                          Expanded(
                            child: _selectedYearId == null
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.archive_outlined,
                                          size: 64,
                                          color: Colors.grey[400],
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Pilih tahun ajaran untuk melihat data',
                                          style: TextStyle(
                                            fontSize: 18,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : StreamBuilder<QuerySnapshot>(
                                    stream: FirebaseFirestore.instance
                                        .collection('classes')
                                        .where('school_id', isEqualTo: widget.userInfo['school_id'])
                                        .where('year_id', isEqualTo: _selectedYearId)
                                        .snapshots(),
                                    builder: (context, snapshot) {
                                      if (!snapshot.hasData) {
                                        return const Center(child: CircularProgressIndicator());
                                      }
                                      final classDocs = snapshot.data!.docs;
                                      if (classDocs.isEmpty) {
                                        return Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.inbox_outlined,
                                                size: 64,
                                                color: Colors.grey[400],
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                'Tidak ada kelas untuk tahun ini',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                      return ListView.builder(
                                        itemCount: classDocs.length,
                                        itemBuilder: (context, index) {
                                          final cdoc = classDocs[index];
                                          final cdata = cdoc.data() as Map<String, dynamic>;
                                          final className = '${cdata['grade'] ?? ''}${cdata['class_name'] ?? ''}'.trim();
                                          final studentIds = List<String>.from(cdata['students'] ?? const []);
                                          return Card(
                                            elevation: 2,
                                            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Theme(
                                              data: Theme.of(context).copyWith(
                                                dividerColor: Colors.transparent,
                                              ),
                                              child: ExpansionTile(
                                                leading: CircleAvatar(
                                                  backgroundColor: Colors.indigo[100],
                                                  child: Icon(
                                                    Icons.class_,
                                                    color: Colors.indigo[700],
                                                  ),
                                                ),
                                                title: Text(
                                                  'Kelas $className',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                subtitle: Text(
                                                  '${studentIds.length} siswa terdaftar',
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                                children: [
                                                  if (studentIds.isEmpty)
                                                    Padding(
                                                      padding: const EdgeInsets.all(16.0),
                                                      child: Text(
                                                        'Tidak ada siswa terdaftar',
                                                        style: TextStyle(
                                                          color: Colors.grey[500],
                                                          fontStyle: FontStyle.italic,
                                                        ),
                                                      ),
                                                    )
                                                  else
                                                    FutureBuilder<List<QueryDocumentSnapshot>>(
                                                      future: _fetchStudentsByIds(studentIds),
                                                      builder: (context, ss) {
                                                        if (!ss.hasData) {
                                                          return const Padding(
                                                            padding: EdgeInsets.all(16.0),
                                                            child: Center(child: CircularProgressIndicator()),
                                                          );
                                                        }
                                                        final studs = ss.data!;
                                                        return Container(
                                                          decoration: BoxDecoration(
                                                            color: Colors.grey[50],
                                                            borderRadius: const BorderRadius.only(
                                                              bottomLeft: Radius.circular(12),
                                                              bottomRight: Radius.circular(12),
                                                            ),
                                                          ),
                                                          child: Column(
                                                            children: studs.map((sdoc) {
                                                              final sdata = sdoc.data() as Map<String, dynamic>;
                                                              return ListTile(
                                                                dense: true,
                                                                leading: CircleAvatar(
                                                                  radius: 16,
                                                                  backgroundColor: _getStatusColor(sdata['status']),
                                                                  child: Icon(
                                                                    Icons.person,
                                                                    size: 16,
                                                                    color: Colors.white,
                                                                  ),
                                                                ),
                                                                title: Text(
                                                                  sdata['name'] ?? sdoc.id,
                                                                  style: const TextStyle(
                                                                    fontWeight: FontWeight.w500,
                                                                  ),
                                                                ),
                                                                subtitle: Text(
                                                                  'Status: ${_getStatusDisplay(sdata['status'])}',
                                                                  style: TextStyle(
                                                                    color: _getStatusColor(sdata['status']),
                                                                    fontWeight: FontWeight.w500,
                                                                  ),
                                                                ),
                                                              );
                                                            }).toList(),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Export Loading Overlay
          if (_isExporting)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Mengekspor data...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'graduated':
        return Colors.blue;
      case 'inactive':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _getStatusDisplay(String? status) {
    switch (status) {
      case 'active':
        return 'Aktif';
      case 'graduated':
        return 'Lulus';
      case 'inactive':
        return 'Tidak Aktif';
      default:
        return 'Tidak Diketahui';
    }
  }

  Future<void> _exportData(String format) async {
    if (_selectedYearId == null) return;
    
    setState(() => _isExporting = true);
    
    try {
      // Fetch all class data for export
      final classesSnapshot = await FirebaseFirestore.instance
          .collection('classes')
          .where('school_id', isEqualTo: widget.userInfo['school_id'])
          .where('year_id', isEqualTo: _selectedYearId)
          .get();
      
      List<Map<String, dynamic>> exportData = [];
      
      for (final classDoc in classesSnapshot.docs) {
        final classData = classDoc.data();
        final className = '${classData['grade'] ?? ''}${classData['class_name'] ?? ''}'.trim();
        final studentIds = List<String>.from(classData['students'] ?? const []);
        
        if (studentIds.isNotEmpty) {
          final students = await _fetchStudentsByIds(studentIds);
          for (final student in students) {
            final studentData = student.data() as Map<String, dynamic>;
            exportData.add({
              'Kelas': className,
              'Nama Siswa': studentData['name'] ?? '',
              'Jenis Kelamin': studentData['gender'] ?? '',
              'Status': _getStatusDisplay(studentData['status']),
              'No. HP Orang Tua': studentData['parent_phone'] ?? '',
              'Tahun Ajaran': _selectedYearName ?? '',
            });
          }
        }
      }
      
      if (format == 'excel') {
        await _exportToCSV(exportData);
      } else if (format == 'pdf') {
        await _exportToPDF(exportData);
      }
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error mengekspor data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isExporting = false);
    }
  }

  Future<void> _exportToCSV(List<Map<String, dynamic>> data) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'arsip_data_${_selectedYearName?.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File('${dir.path}/$fileName');
    
    StringBuffer csv = StringBuffer();
    if (data.isNotEmpty) {
      // Header
      csv.writeln(data.first.keys.join(','));
      // Data rows
      for (final row in data) {
        csv.writeln(row.values.map((v) => '"${v.toString()}"').join(','));
      }
    }
    
    await file.writeAsString(csv.toString());
    await Share.shareXFiles([XFile(file.path)], text: 'Data Arsip ${_selectedYearName}');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data berhasil diekspor ke CSV!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _exportToPDF(List<Map<String, dynamic>> data) async {
    final pdf = pw.Document();
    
    // Group data by class
    Map<String, List<Map<String, dynamic>>> classSections = {};
    for (final item in data) {
      final className = item['Kelas'] as String;
      if (!classSections.containsKey(className)) {
        classSections[className] = [];
      }
      classSections[className]!.add(item);
    }
    
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 20),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 1)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'DATA ARSIP SEKOLAH',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Tahun Ajaran: ${_selectedYearName ?? ''}',
                style: pw.TextStyle(
                  fontSize: 14,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 1)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Dibuat pada: ${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
              ),
              pw.Text(
                'Halaman ${context.pageNumber}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
        build: (context) => [
          for (final className in classSections.keys) ...[
            pw.SizedBox(height: 20),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Text(
                'Kelas $className',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800,
                ),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _buildPDFTableHeader('Nama Siswa'),
                    _buildPDFTableHeader('Jenis Kelamin'),
                    _buildPDFTableHeader('Status'),
                    _buildPDFTableHeader('No. HP Orang Tua'),
                  ],
                ),
                ...classSections[className]!.map((student) => pw.TableRow(
                  children: [
                    _buildPDFTableCell(student['Nama Siswa'] ?? ''),
                    _buildPDFTableCell(student['Jenis Kelamin'] ?? ''),
                    _buildPDFTableCell(student['Status'] ?? ''),
                    _buildPDFTableCell(student['No. HP Orang Tua'] ?? ''),
                  ],
                )),
              ],
            ),
            pw.SizedBox(height: 16),
          ],
        ],
      ),
    );
    
    final bytes = await pdf.save();
    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'arsip_data_${_selectedYearName?.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    
    await Share.shareXFiles([XFile(file.path)], text: 'Data Arsip ${_selectedYearName}');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data berhasil diekspor ke PDF!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  pw.Widget _buildPDFTableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          fontSize: 10,
          color: PdfColors.blue800,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _buildPDFTableCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 9),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  Future<List<QueryDocumentSnapshot>> _fetchStudentsByIds(List<String> ids) async {
    List<QueryDocumentSnapshot> result = [];
    const batchSize = 10;
    for (int i = 0; i < ids.length; i += batchSize) {
      final batch = ids.sublist(i, i + batchSize > ids.length ? ids.length : i + batchSize);
      final q = await FirebaseFirestore.instance
          .collection('students')
          .where(FieldPath.documentId, whereIn: batch)
          .get();
      result.addAll(q.docs);
    }
    return result;
  }
}
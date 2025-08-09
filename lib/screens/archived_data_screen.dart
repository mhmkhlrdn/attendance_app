import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' as excel;
import 'student_details_screen.dart';
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
  String? _schoolName;
  bool _isExporting = false;
  List<Map<String, dynamic>> _cachedClassData = [];

  @override
  void initState() {
    super.initState();
    _loadLatestYear();
    _loadSchoolName();
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

  Future<void> _loadSchoolName() async {
    if (widget.userInfo['school_id'] != null) {
      try {
        final schoolDoc = await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.userInfo['school_id'])
            .get();
        
        if (schoolDoc.exists) {
          setState(() {
            _schoolName = schoolDoc.data()?['name'] ?? 'Sekolah';
          });
        }
      } catch (e) {
        print('Error loading school name: $e');
      }
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
                                                                trailing: Icon(
                                                                  Icons.arrow_forward_ios,
                                                                  size: 16,
                                                                  color: Colors.grey[400],
                                                                ),
                                                                onTap: () {
                                                                  Navigator.push(
                                                                    context,
                                                                    MaterialPageRoute(
                                                                      builder: (context) => StudentDetailsScreen(
                                                                        studentId: sdoc.id,
                                                                        userInfo: widget.userInfo,
                                                                        selectedYear: _selectedYearName ?? '',
                                                                      ),
                                                                    ),
                                                                  );
                                                                },
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
              // Removed parent phone from export
              'Tahun Ajaran': _selectedYearName ?? '',
            });
          }
        }
      }
      
      if (format == 'excel') {
        await _exportToXLSX(exportData);
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

  Future<void> _exportToXLSX(List<Map<String, dynamic>> data) async {
    final excelFile = excel.Excel.createExcel();
    
    // Remove default sheet
    excelFile.delete('Sheet1');
    
    // Group data by class
    Map<String, List<Map<String, dynamic>>> classSections = {};
    for (final item in data) {
      final className = item['Kelas'] as String;
      if (!classSections.containsKey(className)) {
        classSections[className] = [];
      }
      classSections[className]!.add(item);
    }
    
    // Create a sheet for each class
    for (final className in classSections.keys) {
      final sheet = excelFile[className];
      final classData = classSections[className]!;
      
      // School name header (row 1)
      final schoolCell = sheet.cell(excel.CellIndex.indexByString('A1'));
      schoolCell.value = _schoolName ?? 'Sekolah';
      schoolCell.cellStyle = excel.CellStyle(
        bold: true,
        fontSize: 18,
        fontColorHex: 'FF1565C0', // Blue color
      );
      
      // School year header (row 2)
      final yearCell = sheet.cell(excel.CellIndex.indexByString('A2'));
      yearCell.value = 'Tahun Ajaran: ${_selectedYearName ?? ''}';
      yearCell.cellStyle = excel.CellStyle(
        bold: true,
        fontSize: 16,
        fontColorHex: 'FF1565C0', // Blue color
      );
      
      // Class name header (row 3)
      final classCell = sheet.cell(excel.CellIndex.indexByString('A3'));
      classCell.value = 'Kelas $className';
      classCell.cellStyle = excel.CellStyle(
        bold: true,
        fontSize: 14,
        fontColorHex: 'FF1976D2', // Blue color
      );
      
      // Table headers (row 5)
      final headers = ['No', 'Nama Siswa', 'Jenis Kelamin', 'Status'];
      for (int i = 0; i < headers.length; i++) {
        final headerCell = sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 4));
        headerCell.value = headers[i];
        headerCell.cellStyle = excel.CellStyle(
          bold: true,
          fontSize: 12,
          fontColorHex: 'FFFFFFFF', // White text
          backgroundColorHex: 'FF1976D2', // Blue background
          horizontalAlign: excel.HorizontalAlign.Center,
          verticalAlign: excel.VerticalAlign.Center,
          leftBorder: excel.Border(borderStyle: excel.BorderStyle.Thin),
          rightBorder: excel.Border(borderStyle: excel.BorderStyle.Thin),
          topBorder: excel.Border(borderStyle: excel.BorderStyle.Thin),
          bottomBorder: excel.Border(borderStyle: excel.BorderStyle.Thin),
        );
      }
      
      // Student data rows (starting from row 6)
      for (int i = 0; i < classData.length; i++) {
        final student = classData[i];
        final rowIndex = i + 5; // Starting from row 6 (0-indexed)
        
        // Row data
        final rowData = [
          (i + 1).toString(),
          student['Nama Siswa'] ?? '',
          student['Jenis Kelamin'] ?? '',
          student['Status'] ?? '',
          // Removed parent phone from export
        ];
        
        for (int j = 0; j < rowData.length; j++) {
          final cell = sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: j, rowIndex: rowIndex));
          cell.value = rowData[j];
          
          // Alternate row colors
          final isEvenRow = (i + 1) % 2 == 0;
          cell.cellStyle = excel.CellStyle(
            fontSize: 11,
            horizontalAlign: j == 0 ? excel.HorizontalAlign.Center : excel.HorizontalAlign.Left,
            verticalAlign: excel.VerticalAlign.Center,
            backgroundColorHex: isEvenRow ? 'FFF5F5F5' : 'FFFFFFFF', // Light gray and white
            leftBorder: excel.Border(borderStyle: excel.BorderStyle.Thin, borderColorHex: 'FFE0E0E0'),
            rightBorder: excel.Border(borderStyle: excel.BorderStyle.Thin, borderColorHex: 'FFE0E0E0'),
            topBorder: excel.Border(borderStyle: excel.BorderStyle.Thin, borderColorHex: 'FFE0E0E0'),
            bottomBorder: excel.Border(borderStyle: excel.BorderStyle.Thin, borderColorHex: 'FFE0E0E0'),
            fontColorHex: _getStatusExcelColor(student['Status']),
          );
        }
      }
      
      // Set column widths
      try {
        sheet.setColWidth(0, 5.0);   // No
        sheet.setColWidth(1, 25.0);  // Nama Siswa
        sheet.setColWidth(2, 15.0);  // Jenis Kelamin
        sheet.setColWidth(3, 12.0);  // Status
        // Removed phone column width
      } catch (e) {
        // Column width setting may not be available in this version
        print('Note: Column width setting not available: $e');
      }
      
      // Summary row
      final summaryRowIndex = classData.length + 6;
      final summaryCell = sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: summaryRowIndex));
      summaryCell.value = 'Total Siswa: ${classData.length}';
      summaryCell.cellStyle = excel.CellStyle(
        bold: true,
        fontSize: 12,
        fontColorHex: 'FF1976D2', // Blue color
      );
    }
    
    // Save file
    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'arsip_data_${_selectedYearName?.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final file = File('${dir.path}/$fileName');
    
    final bytes = excelFile.save();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Data Arsip ${_selectedYearName}');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data berhasil diekspor ke Excel!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }
  
  String _getStatusExcelColor(String? status) {
    switch (status) {
      case 'Aktif':
        return 'FF4CAF50'; // Green
      case 'Lulus':
        return 'FF2196F3'; // Blue
      case 'Tidak Aktif':
        return 'FFFF9800'; // Orange
      default:
        return 'FF000000'; // Black
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
        margin: const pw.EdgeInsets.all(16),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 16),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 1)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _schoolName ?? 'SEKOLAH',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'DATA ARSIP - Tahun Ajaran: ${_selectedYearName ?? ''}',
                style: pw.TextStyle(
                  fontSize: 12,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 1)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Dibuat pada: ${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
              pw.Text(
                'Halaman ${context.pageNumber}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
        build: (context) => [
          for (final className in classSections.keys) ...[
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Text(
                'Kelas $className',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            _buildCompactClassTable(classSections[className]!),
            pw.SizedBox(height: 12),
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
  
  pw.Widget _buildCompactClassTable(List<Map<String, dynamic>> students) {
    if (students.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(16),
        child: pw.Text(
          'Tidak ada siswa terdaftar',
          style: pw.TextStyle(
            fontSize: 10,
            fontStyle: pw.FontStyle.italic,
            color: PdfColors.grey600,
          ),
        ),
      );
    }
    
    // Check if we can fit 2 columns side by side (if we have enough students and they fit)
    const bool use2ColumnLayout = true; // We'll always try 2-column for better space usage
    
    if (use2ColumnLayout && students.length > 3) {
      return _build2ColumnLayout(students);
    } else {
      return _buildSingleColumnLayout(students);
    }
  }
  
  pw.Widget _build2ColumnLayout(List<Map<String, dynamic>> students) {
    // Split students into two columns
    final int halfLength = (students.length / 2).ceil();
    final leftColumn = students.take(halfLength).toList();
    final rightColumn = students.skip(halfLength).toList();
    
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Left Column
        pw.Expanded(
          child: _buildCompactTable(leftColumn, startIndex: 0),
        ),
        pw.SizedBox(width: 16),
        // Right Column
        pw.Expanded(
          child: _buildCompactTable(rightColumn, startIndex: halfLength),
        ),
      ],
    );
  }
  
  pw.Widget _buildSingleColumnLayout(List<Map<String, dynamic>> students) {
    return _buildCompactTable(students, startIndex: 0);
  }
  
  pw.Widget _buildCompactTable(List<Map<String, dynamic>> students, {required int startIndex}) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.3),
      columnWidths: {
        0: const pw.FixedColumnWidth(25), // No
        1: const pw.FlexColumnWidth(3),   // Nama (larger)
        2: const pw.FixedColumnWidth(20), // Gender (compact)
        // Removed phone column
      },
      children: [
        // Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _buildCompactPDFTableHeader('No'),
            _buildCompactPDFTableHeader('Nama Siswa'),
            _buildCompactPDFTableHeader('JK'), // Shortened "Jenis Kelamin" to "JK"
            // Phone header removed
          ],
        ),
        // Data rows
        ...students.asMap().entries.map((entry) {
          final index = entry.key;
          final student = entry.value;
          return pw.TableRow(
            children: [
              _buildCompactPDFTableCell((startIndex + index + 1).toString()),
              _buildCompactPDFTableCell(student['Nama Siswa'] ?? '', isName: true),
              _buildCompactPDFTableCell(_shortenGender(student['Jenis Kelamin'] ?? '')),
              // Phone cell removed
            ],
          );
        }),
      ],
    );
  }
  
  String _shortenGender(String gender) {
    switch (gender.toLowerCase()) {
      case 'laki-laki':
      case 'l':
        return 'L';
      case 'perempuan':
      case 'p':
        return 'P';
      default:
        return gender.isNotEmpty ? gender[0].toUpperCase() : '-';
    }
  }

  pw.Widget _buildCompactPDFTableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          fontSize: 8,
          color: PdfColors.blue800,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _buildCompactPDFTableCell(String text, {bool isName = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 7),
        textAlign: isName ? pw.TextAlign.left : pw.TextAlign.center,
        maxLines: isName ? 2 : 1,
        overflow: pw.TextOverflow.clip,
      ),
    );
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
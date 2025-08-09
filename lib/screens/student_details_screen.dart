import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' as excel;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:io';

class StudentDetailsScreen extends StatefulWidget {
  final String studentId;
  final Map<String, String> userInfo;
  final String selectedYear;

  const StudentDetailsScreen({
    Key? key,
    required this.studentId,
    required this.userInfo,
    required this.selectedYear,
  }) : super(key: key);

  @override
  State<StudentDetailsScreen> createState() => _StudentDetailsScreenState();
}

class _StudentDetailsScreenState extends State<StudentDetailsScreen> {
  Map<String, dynamic>? _studentData;
  List<Map<String, dynamic>> _attendanceData = [];
  String? _schoolName;
  bool _isLoading = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('id_ID', null).whenComplete(() => _loadStudentData());
  }

  Future<void> _loadStudentData() async {
    setState(() => _isLoading = true);
    
    try {
      // Load student data
      final studentDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.studentId)
          .get();
      
      if (studentDoc.exists) {
        _studentData = studentDoc.data();
      }

      // Load school name
      if (widget.userInfo['school_id'] != null) {
        final schoolDoc = await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.userInfo['school_id'])
            .get();
        
        if (schoolDoc.exists) {
          _schoolName = schoolDoc.data()?['name'] ?? 'Sekolah';
        }
      }

      // Load attendance data for this student (use arrayContains on student_ids)
      final attendanceQuery = await FirebaseFirestore.instance
          .collection('attendances')
          .where('student_ids', arrayContains: widget.studentId)
          .where('school_id', isEqualTo: widget.userInfo['school_id'])
          .orderBy('date', descending: true)
          .get();

      _attendanceData = attendanceQuery.docs.map((doc) {
        final data = doc.data();
        final attendanceMap = Map<String, dynamic>.from(data['attendance'] ?? {});
        final status = (attendanceMap[widget.studentId] ?? '').toString();
        return {
          'id': doc.id,
          'date': data['date'],
          'status': status,
          'class_id': data['class_id'],
          'notes': data['notes'] ?? '',
        };
      }).toList();

    } catch (e) {
      print('Error loading student data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Detail Siswa'),
          backgroundColor: Colors.indigo[700],
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_studentData == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Detail Siswa'),
          backgroundColor: Colors.indigo[700],
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text('Data siswa tidak ditemukan'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_studentData!['name'] ?? 'Detail Siswa'),
        backgroundColor: Colors.indigo[700],
        foregroundColor: Colors.white,
        actions: [
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
                        Text(
                          'Detail Siswa',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Informasi lengkap dan riwayat kehadiran',
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
                          // Student Info Card
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
                                      CircleAvatar(
                                        radius: 30,
                                        backgroundColor: Colors.indigo[100],
                                        child: Icon(
                                          Icons.person,
                                          size: 30,
                                          color: Colors.indigo[700],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _studentData!['name'] ?? 'Nama tidak tersedia',
                                              style: const TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Status: ${_getStatusDisplay(_studentData!['status'])}',
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: _getStatusColor(_studentData!['status']),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  const Divider(),
                                  const SizedBox(height: 16),
                                  _buildInfoRow('Jenis Kelamin', _studentData!['gender'] ?? '-'),
                                  _buildInfoRow('Alamat', _studentData!['address'] ?? '-'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          // Attendance Section
                          Expanded(
                            child: Card(
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
                                          'Riwayat Kehadiran',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.indigo[100],
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            '${_attendanceData.length} record',
                                            style: TextStyle(
                                              color: Colors.indigo[700],
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Expanded(
                                      child: _attendanceData.isEmpty
                                          ? Center(
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.event_busy,
                                                    size: 64,
                                                    color: Colors.grey[400],
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Text(
                                                    'Tidak ada data kehadiran',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          : ListView.builder(
                                              itemCount: _attendanceData.length,
                                              itemBuilder: (context, index) {
                                                final attendance = _attendanceData[index];
                                                return _buildAttendanceItem(attendance);
                                              },
                                            ),
                                    ),
                                  ],
                                ),
                              ),
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ),
          const Text(': '),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceItem(Map<String, dynamic> attendance) {
    final date = attendance['date'] as Timestamp?;
    final status = attendance['status'] as String? ?? '';
    final notes = attendance['notes'] as String? ?? '';

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getAttendanceStatusColor(status),
          child: Icon(
            _getAttendanceStatusIcon(status),
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(
          date != null 
              ? DateFormat('dd MMMM yyyy', 'id_ID').format(date.toDate())
              : 'Tanggal tidak tersedia',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getAttendanceStatusDisplay(status),
              style: TextStyle(
                color: _getAttendanceStatusColor(status),
                fontWeight: FontWeight.w500,
              ),
            ),
            if (notes.isNotEmpty)
              Text(
                notes,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
        trailing: Text(
          date != null 
              ? DateFormat('HH:mm').format(date.toDate())
              : '',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
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

  Color _getAttendanceStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'present':
      case 'hadir':
        return Colors.green;
      case 'absent':
      case 'tidak hadir':
        return Colors.red;
      case 'late':
      case 'terlambat':
        return Colors.orange;
      case 'sick':
      case 'sakit':
        return Colors.blue;
      case 'permission':
      case 'izin':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getAttendanceStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'present':
      case 'hadir':
        return Icons.check_circle;
      case 'absent':
      case 'tidak hadir':
        return Icons.cancel;
      case 'late':
      case 'terlambat':
        return Icons.access_time;
      case 'sick':
      case 'sakit':
        return Icons.local_hospital;
      case 'permission':
      case 'izin':
        return Icons.assignment;
      default:
        return Icons.help;
    }
  }

  String _getAttendanceStatusDisplay(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return 'Hadir';
      case 'absent':
        return 'Tidak Hadir';
      case 'late':
        return 'Terlambat';
      case 'sick':
        return 'Sakit';
      case 'permission':
        return 'Izin';
      default:
        return status.isNotEmpty ? status : 'Tidak Diketahui';
    }
  }

  Future<void> _exportData(String format) async {
    setState(() => _isExporting = true);
    
    try {
      if (format == 'excel') {
        await _exportToXLSX();
      } else if (format == 'pdf') {
        await _exportToPDF();
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

  Future<void> _exportToXLSX() async {
    final excelFile = excel.Excel.createExcel();
    
    // Keep default sheet; we'll use a dedicated sheet and leave defaults intact
    
    // Create student details sheet
    final sheet = excelFile['Detail Siswa'];
    
    // School and year header
    sheet.cell(excel.CellIndex.indexByString('A1')).value = '${_schoolName ?? 'Sekolah'}';
    sheet.cell(excel.CellIndex.indexByString('A1')).cellStyle = excel.CellStyle(
      bold: true,
      fontSize: 18,
      fontColorHex: 'FF1565C0',
    );
    
    sheet.cell(excel.CellIndex.indexByString('A2')).value = 'Tahun Ajaran: ${widget.selectedYear}';
    sheet.cell(excel.CellIndex.indexByString('A2')).cellStyle = excel.CellStyle(
      bold: true,
      fontSize: 14,
      fontColorHex: 'FF1976D2',
    );
    
    // Student info section
    sheet.cell(excel.CellIndex.indexByString('A4')).value = 'DETAIL SISWA';
    sheet.cell(excel.CellIndex.indexByString('A4')).cellStyle = excel.CellStyle(
      bold: true,
      fontSize: 14,
      fontColorHex: 'FF1976D2',
    );
    
    sheet.cell(excel.CellIndex.indexByString('A5')).value = 'Nama';
    sheet.cell(excel.CellIndex.indexByString('B5')).value = _studentData!['name'] ?? '';
    sheet.cell(excel.CellIndex.indexByString('A6')).value = 'Jenis Kelamin';
    sheet.cell(excel.CellIndex.indexByString('B6')).value = _studentData!['gender'] ?? '';
    sheet.cell(excel.CellIndex.indexByString('A7')).value = 'Status';
    sheet.cell(excel.CellIndex.indexByString('B7')).value = _getStatusDisplay(_studentData!['status']);
    sheet.cell(excel.CellIndex.indexByString('A8')).value = 'No. HP Orang Tua';
    sheet.cell(excel.CellIndex.indexByString('B8')).value = _studentData!['parent_phone'] ?? '';
    
    // Attendance section header
    sheet.cell(excel.CellIndex.indexByString('A10')).value = 'RIWAYAT KEHADIRAN';
    sheet.cell(excel.CellIndex.indexByString('A10')).cellStyle = excel.CellStyle(
      bold: true,
      fontSize: 14,
      fontColorHex: 'FF1976D2',
    );
    
    // Attendance table headers
    final headers = ['No', 'Tanggal (Hari, DD MMMM YYYY)', 'Status', 'Keterangan'];
    for (int i = 0; i < headers.length; i++) {
      final headerCell = sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 10));
      headerCell.value = headers[i];
      headerCell.cellStyle = excel.CellStyle(
        bold: true,
        fontSize: 12,
        fontColorHex: 'FFFFFFFF',
        backgroundColorHex: 'FF1976D2',
        horizontalAlign: excel.HorizontalAlign.Center,
        leftBorder: excel.Border(borderStyle: excel.BorderStyle.Thin),
        rightBorder: excel.Border(borderStyle: excel.BorderStyle.Thin),
        topBorder: excel.Border(borderStyle: excel.BorderStyle.Thin),
        bottomBorder: excel.Border(borderStyle: excel.BorderStyle.Thin),
      );
    }
    
    // Attendance data
    for (int i = 0; i < _attendanceData.length; i++) {
      final attendance = _attendanceData[i];
      final date = attendance['date'] as Timestamp?;
      final rowIndex = i + 11;
      
      final rowData = [
        (i + 1).toString(),
        date != null ? DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(date.toDate()) : '',
        _getAttendanceStatusDisplay(attendance['status'] ?? ''),
        attendance['notes'] ?? '',
      ];
      
      for (int j = 0; j < rowData.length; j++) {
        final cell = sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: j, rowIndex: rowIndex));
        cell.value = rowData[j];
        
        final isEvenRow = (i + 1) % 2 == 0;
        cell.cellStyle = excel.CellStyle(
          fontSize: 11,
          horizontalAlign: j == 0 ? excel.HorizontalAlign.Center : excel.HorizontalAlign.Left,
          backgroundColorHex: isEvenRow ? 'FFF5F5F5' : 'FFFFFFFF',
          leftBorder: excel.Border(borderStyle: excel.BorderStyle.Thin, borderColorHex: 'FFE0E0E0'),
          rightBorder: excel.Border(borderStyle: excel.BorderStyle.Thin, borderColorHex: 'FFE0E0E0'),
          topBorder: excel.Border(borderStyle: excel.BorderStyle.Thin, borderColorHex: 'FFE0E0E0'),
          bottomBorder: excel.Border(borderStyle: excel.BorderStyle.Thin, borderColorHex: 'FFE0E0E0'),
        );
      }
    }
    
    // Set column widths
    try {
      sheet.setColWidth(0, 5.0);   // No
      sheet.setColWidth(1, 15.0);  // Tanggal
      sheet.setColWidth(2, 15.0);  // Status
      sheet.setColWidth(3, 25.0);  // Keterangan
    } catch (e) {
      print('Note: Column width setting not available: $e');
    }
    
    // Save file
    String _slugify(String? s) => (s ?? '')
        .replaceAll(RegExp(r"[\\/:*?\<>|]"), '')
        .replaceAll(RegExp(r"\s+"), '_');
    String _nowStamp() {
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
    }
    final dir = await getApplicationDocumentsDirectory();
    final schoolSlug = _slugify(_schoolName ?? 'Sekolah');
    final studentSlug = _slugify(_studentData!['name']);
    final fileName = '${schoolSlug}_Detail_Siswa_${studentSlug}_${_nowStamp()}.xlsx';
    final file = File('${dir.path}/$fileName');
    
    final bytes = excelFile.save();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Detail Siswa ${_studentData!['name']}');
      
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

  Future<void> _exportToPDF() async {
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
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
              pw.SizedBox(height: 4),
              pw.Text(
                'Tahun Ajaran: ${widget.selectedYear}',
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
                'Dibuat pada: ${DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(DateTime.now())}',
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
          // Student Details Section
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'DETAIL SISWA',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue800,
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Table(
                  children: [
                    _buildPDFInfoRow('Nama', _studentData!['name'] ?? ''),
                    _buildPDFInfoRow('Jenis Kelamin', _studentData!['gender'] ?? ''),
                    _buildPDFInfoRow('Status', _getStatusDisplay(_studentData!['status'])),
                    _buildPDFInfoRow('No. HP Orang Tua', _studentData!['parent_phone'] ?? ''),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          // Attendance Section
          pw.Text(
            'RIWAYAT KEHADIRAN',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
            ),
          ),
          pw.SizedBox(height: 12),
          if (_attendanceData.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              child: pw.Text(
                'Tidak ada data kehadiran',
                style: pw.TextStyle(
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColors.grey600,
                ),
              ),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _buildPDFTableHeader('No'),
                    _buildPDFTableHeader('Tanggal'),
                    _buildPDFTableHeader('Status'),
                    _buildPDFTableHeader('Keterangan'),
                  ],
                ),
                ..._attendanceData.asMap().entries.map((entry) {
                  final index = entry.key;
                  final attendance = entry.value;
                  final date = attendance['date'] as Timestamp?;
                  
                  return pw.TableRow(
                    children: [
                      _buildPDFTableCell((index + 1).toString()),
                      _buildPDFTableCell(
                        date != null ? DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(date.toDate()) : '',
                      ),
                      _buildPDFTableCell(_getAttendanceStatusDisplay(attendance['status'] ?? '')),
                      _buildPDFTableCell(attendance['notes'] ?? ''),
                    ],
                  );
                }),
              ],
            ),
        ],
      ),
    );
    
    final bytes = await pdf.save();
    String _slugify(String? s) => (s ?? '')
        .replaceAll(RegExp(r"[\\/:*?\<>|]"), '')
        .replaceAll(RegExp(r"\s+"), '_');
    String _nowStamp() {
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
    }
    final dir = await getApplicationDocumentsDirectory();
    final schoolSlug = _slugify(_schoolName ?? 'Sekolah');
    final studentSlug = _slugify(_studentData!['name']);
    final fileName = '${schoolSlug}_Detail_Siswa_${studentSlug}_${_nowStamp()}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    
    await Share.shareXFiles([XFile(file.path)], text: 'Detail Siswa ${_studentData!['name']}');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data berhasil diekspor ke PDF!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  pw.TableRow _buildPDFInfoRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(
            label,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(': $value'),
        ),
      ],
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
}



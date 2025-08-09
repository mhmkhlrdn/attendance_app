import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'advanced_report_screen.dart';

class AttendanceReportScreen extends StatefulWidget {
  final Map<String, String> userInfo;
  final String role;

  const AttendanceReportScreen({
    Key? key,
    required this.userInfo,
    required this.role,
  }) : super(key: key);

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  String? _selectedClassId;
  DateTime? _selectedDate;
  String _reportType = 'daily'; // 'daily', 'monthly', 'yearly'
  List<QueryDocumentSnapshot>? _classes;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _fetchClasses();
  }

  Future<void> _fetchClasses() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('classes')
        .where('school_id', isEqualTo: widget.userInfo['school_id'])
        .get();
    setState(() {
      _classes = snapshot.docs;
    });
  }

  Future<List<QueryDocumentSnapshot>> _fetchAttendanceRecords() async {
    Query query = FirebaseFirestore.instance
        .collection('attendances')
        .where('school_id', isEqualTo: widget.userInfo['school_id']);
    
    // Filter by class if selected
    if (_selectedClassId != null && _selectedClassId!.isNotEmpty) {
      query = query.where('class_id', isEqualTo: _selectedClassId);
    }
    
    // Filter by date range based on report type
    if (_selectedDate != null) {
      DateTime start, end;
      
      switch (_reportType) {
        case 'daily':
          start = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
          end = start.add(const Duration(days: 1));
          break;
        case 'monthly':
          start = DateTime(_selectedDate!.year, _selectedDate!.month, 1);
          end = DateTime(_selectedDate!.year, _selectedDate!.month + 1, 1);
          break;
        case 'yearly':
          start = DateTime(_selectedDate!.year, 1, 1);
          end = DateTime(_selectedDate!.year + 1, 1, 1);
          break;
        default:
          start = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
          end = start.add(const Duration(days: 1));
      }
      
      query = query.where('date', isGreaterThanOrEqualTo: start).where('date', isLessThan: end);
    }
    
    final snapshot = await query.get();
    return snapshot.docs;
  }

  Future<void> _exportToPDF(List<QueryDocumentSnapshot> records) async {
    setState(() => _isExporting = true);
    
    try {
      // Create PDF document
      final pdf = pw.Document();
      
      // Get report period string with proper null checking
      String getReportPeriod() {
        if (_selectedDate == null) return 'Semua Periode';
        switch (_reportType) {
          case 'daily':
            return '${_selectedDate!.day.toString().padLeft(2, '0')}/${_selectedDate!.month.toString().padLeft(2, '0')}/${_selectedDate!.year}';
          case 'monthly':
            final months = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
                          'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
            return '${months[_selectedDate!.month - 1]} ${_selectedDate!.year}';
          case 'yearly':
            return 'Tahun ${_selectedDate!.year}';
          default:
            return '${_selectedDate!.day.toString().padLeft(2, '0')}/${_selectedDate!.month.toString().padLeft(2, '0')}/${_selectedDate!.year}';
        }
      }
      
      // Get class filter string
      String getClassFilter() {
        if (_selectedClassId == null || _selectedClassId!.isEmpty) return 'Semua Kelas';
        final selectedClass = _classes?.firstWhere(
          (doc) => doc.id == _selectedClassId,
          orElse: () => throw Exception('Class not found'),
        );
        if (selectedClass != null) {
          final data = selectedClass.data() as Map<String, dynamic>;
          return 'Kelas ${data['grade'] ?? ''} ${data['class_name'] ?? ''}'.trim();
        }
        return 'Kelas Terpilih';
      }
      
      // Process attendance data
      final Map<String, Map<String, int>> classStats = {};
      final List<Map<String, dynamic>> detailedRecords = [];
      
      for (final doc in records) {
        final data = doc.data() as Map<String, dynamic>;
        final date = (data['date'] as Timestamp?)?.toDate();
        final classId = data['class_id'] ?? '';
        final teacherId = data['teacher_id'] ?? '';
        final attendance = data['attendance'] as Map?;

        // Fetch class and teacher info
        final classDoc = await FirebaseFirestore.instance.collection('classes').doc(classId).get();
        final classData = classDoc.data() as Map<String, dynamic>?;
        final className = classData != null ? '${classData['grade'] ?? ''} ${classData['class_name'] ?? ''}'.trim() : classId;

        final teacherQuery = await FirebaseFirestore.instance.collection('teachers').where('nuptk', isEqualTo: teacherId).limit(1).get();
        final teacherName = teacherQuery.docs.isNotEmpty ? teacherQuery.docs.first['name'] ?? teacherId : teacherId;

        // Initialize class stats
        if (!classStats.containsKey(className)) {
          classStats[className] = {'hadir': 0, 'sakit': 0, 'izin': 0, 'alfa': 0, 'total': 0};
        }

        if (attendance != null) {
          for (final entry in attendance.entries) {
            final studentId = entry.key;
            final status = entry.value;

            // Fetch student name
            final studentDoc = await FirebaseFirestore.instance.collection('students').doc(studentId).get();
            final studentName = studentDoc.exists ? studentDoc['name'] ?? studentId : studentId;

            // Update stats
            if (classStats[className]!.containsKey(status)) {
              classStats[className]![status] = classStats[className]![status]! + 1;
            }
            classStats[className]!['total'] = classStats[className]!['total']! + 1;

            // Add to detailed records
            detailedRecords.add({
              'date': date != null ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}' : '-',
              'class': className,
              'teacher': teacherName,
              'student': studentName,
              'status': status,
            });
          }
        }
      }

      // Calculate overall totals
      int totalHadir = 0, totalSakit = 0, totalIzin = 0, totalAlfa = 0, totalRecords = 0;
      for (final stats in classStats.values) {
        totalHadir += stats['hadir'] ?? 0;
        totalSakit += stats['sakit'] ?? 0;
        totalIzin += stats['izin'] ?? 0;
        totalAlfa += stats['alfa'] ?? 0;
        totalRecords += stats['total'] ?? 0;
      }

      // Build PDF content with modern styling
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(25),
          header: (context) => pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 20),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 1)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'LAPORAN PRESENSI SISWA',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue800,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'SADESA - Sistem Absensi Digital Siswa Tanjungkarang',
                      style: pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      getReportPeriod(),
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue700,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      getClassFilter(),
                      style: pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
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
                  'Dibuat pada: ${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year} ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                ),
                pw.Text(
                  'Halaman ${context.pageNumber} dari ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                ),
              ],
            ),
          ),
          build: (context) => [
            pw.SizedBox(height: 20),

            // Overall Summary Card
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                border: pw.Border.all(color: PdfColors.blue200, width: 1),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Ringkasan Keseluruhan',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue800,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildSummaryCard('Hadir', totalHadir, PdfColors.green),
                      _buildSummaryCard('Sakit', totalSakit, PdfColors.orange),
                      _buildSummaryCard('Izin', totalIzin, PdfColors.blue),
                      _buildSummaryCard('Alfa', totalAlfa, PdfColors.red),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 25),

            // Class-wise Summary Section
            pw.Text(
              'Ringkasan per Kelas',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800,
              ),
            ),

            pw.SizedBox(height: 12),

            // Class summary table with modern styling
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 1),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Table(
                border: pw.TableBorder.symmetric(
                  // horizontalInside: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                inside: pw.BorderSide(color: PdfColors.grey200, width: 0.5)
                ),
                children: [
                  // Header row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.blue100),
                    children: [
                      _buildTableHeader('Kelas'),
                      _buildTableHeader('Hadir'),
                      _buildTableHeader('Sakit'),
                      _buildTableHeader('Izin'),
                      _buildTableHeader('Alfa'),
                      _buildTableHeader('Total'),
                    ],
                  ),
                  // Data rows
                  ...classStats.entries.map((entry) => pw.TableRow(
                    children: [
                      _buildTableCell(entry.key, isBold: true),
                      _buildTableCell('${entry.value['hadir']}', color: PdfColors.green700),
                      _buildTableCell('${entry.value['sakit']}', color: PdfColors.orange700),
                      _buildTableCell('${entry.value['izin']}', color: PdfColors.blue700),
                      _buildTableCell('${entry.value['alfa']}', color: PdfColors.red700),
                      _buildTableCell('${entry.value['total']}', isBold: true),
                    ],
                  )).toList(),
                ],
              ),
            ),

            pw.SizedBox(height: 25),

            // Detailed Records Section
            pw.Text(
              'Detail Presensi',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800,
              ),
            ),

            pw.SizedBox(height: 12),

            // Detailed records table
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 1),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Table(
                border: pw.TableBorder.symmetric(
                  inside: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                ),
                children: [
                  // Header row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    children: [
                      _buildTableHeader('Tanggal', fontSize: 9),
                      _buildTableHeader('Kelas', fontSize: 9),
                      _buildTableHeader('Guru', fontSize: 9),
                      _buildTableHeader('Siswa', fontSize: 9),
                      _buildTableHeader('Status', fontSize: 9),
                    ],
                  ),
                  ...detailedRecords.map((record) => pw.TableRow(
                    children: [
                      _buildTableCell(record['date'], fontSize: 9),
                      _buildTableCell(record['class'], fontSize: 9),
                      _buildTableCell(record['teacher'], fontSize: 9),
                      _buildTableCell(record['student'], fontSize: 9),
                      _buildStatusCell(record['status'], fontSize: 9),
                    ],
                  )).toList(),
                ],
              ),
            ),

           
          ],
        ),
      );

      // Save PDF
      final bytes = await pdf.save();
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'laporan_presensi_${_reportType}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      setState(() => _isExporting = false);
      await Share.shareXFiles([XFile(file.path)], text: 'Laporan Presensi PDF');

    } catch (e) {
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Helper methods for PDF styling
  pw.Widget _buildSummaryCard(String label, int count, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: color, width: 1),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '$count',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTableHeader(String text, {double fontSize = 11}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          fontSize: fontSize,
          color: PdfColors.blue800,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _buildTableCell(String text, {bool isBold = false, PdfColor? color, double fontSize = 11}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontSize: fontSize,
          color: color ?? PdfColors.black,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _buildStatusCell(String status, {double fontSize = 11}) {
    PdfColor statusColor;
    switch (status.toLowerCase()) {
      case 'hadir':
        statusColor = PdfColors.green700;
        break;
      case 'sakit':
        statusColor = PdfColors.orange700;
        break;
      case 'izin':
        statusColor = PdfColors.blue700;
        break;
      case 'alfa':
        statusColor = PdfColors.red700;
        break;
      default:
        statusColor = PdfColors.grey700;
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: pw.BoxDecoration(
          // color: statusColor.alpha,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          border: pw.Border.all(color: statusColor, width: 0.5),
        ),
        child: pw.Text(
          status.toUpperCase(),
          style: pw.TextStyle(
            fontSize: fontSize - 1,
            fontWeight: pw.FontWeight.bold,
            color: statusColor,
          ),
          textAlign: pw.TextAlign.center,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Laporan Presensi',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.blue[700],
        elevation: 0,
        // actions: [
        //   Container(
        //     margin: const EdgeInsets.only(right: 16),
        //     child: TextButton.icon(
        //       onPressed: () {
        //         Navigator.push(
        //           context,
        //           MaterialPageRoute(
        //             builder: (context) => AdvancedReportScreen(
        //               userInfo: widget.userInfo,
        //               role: widget.role,
        //             ),
        //           ),
        //         );
        //       },
        //       // icon: const Icon(Icons.analytics, color: Colors.white, size: 20),
        //       // label: const Text(
        //       //   'Laporan Lanjutan',
        //       //   style: TextStyle(
        //       //     color: Colors.white,
        //       //     fontWeight: FontWeight.w500,
        //       //   ),
        //       // ),
        //       // style: TextButton.styleFrom(
        //       //   backgroundColor: Colors.blue[600],
        //       //   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        //       //   shape: RoundedRectangleBorder(
        //       //     borderRadius: BorderRadius.circular(8),
        //       //   ),
        //       // ),
        //     ),
        //   ),
        // ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue[700]!,
              Colors.blue[50]!,
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
                      'Buat Laporan Presensi',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pilih periode dan kelas untuk menghasilkan laporan PDF',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.blue[100],
                      ),
                    ),
                  ],
                ),
              ),

              // Filters Section
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Filters Card
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
                                    Icons.filter_list,
                                    color: Colors.blue[700],
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Filter Laporan',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              // Report Type Selector
                              const Text(
                                'Jenis Laporan',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[300]!),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: DropdownButtonFormField<String>(
                                  value: _reportType,
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'daily',
                                      child: Row(
                                        children: [
                                          Icon(Icons.calendar_today, size: 18),
                                          SizedBox(width: 8),
                                          Text('Harian'),
                                        ],
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'monthly',
                                      child: Row(
                                        children: [
                                          Icon(Icons.calendar_month, size: 18),
                                          SizedBox(width: 8),
                                          Text('Bulanan'),
                                        ],
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'yearly',
                                      child: Row(
                                        children: [
                                          Icon(Icons.calendar_month_rounded, size: 18),
                                          SizedBox(width: 8),
                                          Text('Tahunan'),
                                        ],
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) => setState(() => _reportType = value!),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Class and Date Selectors
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Kelas',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          decoration: BoxDecoration(
                                            border: Border.all(color: Colors.grey[300]!),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: DropdownButtonFormField<String>(
                                            isExpanded: true,
                                            value: _selectedClassId,
                                            decoration: const InputDecoration(
                                              border: InputBorder.none,
                                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            ),
                                            items: [
                                              const DropdownMenuItem(
                                                value: '',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.class_, size: 18),
                                                    SizedBox(width: 8),
                                                    Text('Semua Kelas'),
                                                  ],
                                                ),
                                              ),
                                              ...(_classes ?? []).map((doc) {
                                                final data = doc.data() as Map<String, dynamic>;
                                                final label = '${data['grade'] ?? ''} ${data['class_name'] ?? ''}'.trim();
                                                return DropdownMenuItem(
                                                  value: doc.id,
                                                  child: Text(label),
                                                );
                                                                                              }).toList()
                                                  ..sort((a, b) {
                                                    if (a.value == '') return -1;
                                                    if (b.value == '') return 1;
                                                    return ((a.child as Text).data ?? '').compareTo((b.child as Text).data ?? '');
                                                  }),
                                            ],
                                            onChanged: (v) => setState(() => _selectedClassId = v == '' ? null : v),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _reportType == 'daily'
                                              ? 'Tanggal'
                                              : _reportType == 'monthly'
                                                  ? 'Bulan'
                                                  : 'Tahun',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        InkWell(
                                          onTap: () async {
                                            DateTime? initialDate;
                                            DateTime? firstDate;
                                            DateTime? lastDate;

                                            switch (_reportType) {
                                              case 'daily':
                                                initialDate = _selectedDate ?? DateTime.now();
                                                firstDate = DateTime(2020);
                                                lastDate = DateTime.now().add(const Duration(days: 365));
                                                break;
                                              case 'monthly':
                                                initialDate = _selectedDate ?? DateTime.now();
                                                firstDate = DateTime(2020, 1);
                                                lastDate = DateTime.now();
                                                break;
                                              case 'yearly':
                                                initialDate = _selectedDate ?? DateTime.now();
                                                firstDate = DateTime(2020);
                                                lastDate = DateTime.now();
                                                break;
                                            }

                                            final picked = await showDatePicker(
                                              context: context,
                                              initialDate: initialDate!,
                                              firstDate: firstDate!,
                                              lastDate: lastDate!,
                                              initialDatePickerMode: _reportType == 'yearly'
                                                  ? DatePickerMode.year
                                                  : _reportType == 'monthly'
                                                      ? DatePickerMode.year
                                                      : DatePickerMode.day,
                                            );
                                            if (picked != null) setState(() => _selectedDate = picked);
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            decoration: BoxDecoration(
                                              border: Border.all(color: Colors.grey[300]!),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.calendar_today,
                                                  size: 18,
                                                  color: Colors.grey[600],
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    _selectedDate == null
                                                        ? _reportType == 'daily'
                                                            ? 'Semua Tanggal'
                                                            : _reportType == 'monthly'
                                                                ? 'Semua Bulan'
                                                                : 'Semua Tahun'
                                                        : _reportType == 'daily'
                                                            ? '${_selectedDate!.day.toString().padLeft(2, '0')}/${_selectedDate!.month.toString().padLeft(2, '0')}/${_selectedDate!.year}'
                                                            : _reportType == 'monthly'
                                                                ? '${_selectedDate!.month.toString().padLeft(2, '0')}/${_selectedDate!.year}'
                                                                : '${_selectedDate!.year}',
                                                    style: TextStyle(
                                                      color: _selectedDate == null ? Colors.grey[500] : Colors.black,
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
                                ],
                              ),

                              const SizedBox(height: 16),

                              // Reset Button
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => setState(() {
                                      _selectedClassId = null;
                                      _selectedDate = null;
                                    }),
                                    icon: const Icon(Icons.refresh, size: 18),
                                    label: const Text('Reset Filter'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Data Preview Section
                      Expanded(
                        child: FutureBuilder<List<QueryDocumentSnapshot>>(
                          future: _fetchAttendanceRecords(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 16),
                                    Text('Memuat data...'),
                                  ],
                                ),
                              );
                            }

                            if (!snapshot.hasData || snapshot.data!.isEmpty) {
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
                                      'Tidak ada data presensi',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Coba ubah filter atau pilih periode lain',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final records = snapshot.data!;

                            // Calculate statistics
                            int hadir = 0, sakit = 0, izin = 0, alfa = 0;
                            for (final doc in records) {
                              final data = doc.data() as Map<String, dynamic>;
                              final attendance = data['attendance'] as Map?;
                              if (attendance != null) {
                                for (final status in attendance.values) {
                                  if (status == 'hadir') hadir++;
                                  if (status == 'sakit') sakit++;
                                  if (status == 'izin') izin++;
                                  if (status == 'alfa') alfa++;
                                }
                              }
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Statistics Cards
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildStatCard('Hadir', hadir, Colors.green, Icons.check_circle),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildStatCard('Sakit', sakit, Colors.orange, Icons.local_hospital),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildStatCard('Izin', izin, Colors.blue, Icons.info),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildStatCard('Alfa', alfa, Colors.red, Icons.cancel),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 20),

                      //           // Records Preview
                      //           Row(
                      //             children: [
                      //               Icon(
                      //                 Icons.list_alt,
                      //                 color: Colors.blue[700],
                      //                 size: 20,
                      //               ),
                      //               const SizedBox(width: 8),
                      //               const Text(
                      //                 'Preview Data',
                      //                 style: TextStyle(
                      //                   fontSize: 16,
                      //                   fontWeight: FontWeight.bold,
                      //                 ),
                      //               ),
                      //               const Spacer(),
                      //               Text(
                      //                 '${records.length} record ditemukan',
                      //                 style: TextStyle(
                      //                   fontSize: 14,
                      //                   color: Colors.grey[600],
                      //                 ),
                      //               ),
                      //             ],
                      //           ),
                      //
                      //           const SizedBox(height: 12),
                      //
                      //           // Records List
                      //           Expanded(
                      //             child: Card(
                      //               elevation: 2,
                      //               shape: RoundedRectangleBorder(
                      //                 borderRadius: BorderRadius.circular(12),
                      //               ),
                      //               child: ListView.builder(
                      //                 padding: const EdgeInsets.all(8),
                      //                 itemCount: records.length > 10 ? 10 : records.length,
                      //                 itemBuilder: (context, index) {
                      //                   final data = records[index].data() as Map<String, dynamic>;
                      //                   final date = (data['date'] as Timestamp?)?.toDate();
                      //                   final dateStr = date != null
                      //                       ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'
                      //                       : '-';
                      //                   final classId = data['class_id'] ?? '-';
                      //                   final teacherId = data['teacher_id'] ?? '-';
                      //
                      //                   return ListTile(
                      //                     leading: CircleAvatar(
                      //                       backgroundColor: Colors.blue[100],
                      //                       child: Icon(
                      //                         Icons.calendar_today,
                      //                         color: Colors.blue[700],
                      //                         size: 20,
                      //                       ),
                      //                     ),
                      //                     title: Text(
                      //                       'Tanggal: $dateStr',
                      //                       style: const TextStyle(fontWeight: FontWeight.w600),
                      //                     ),
                      //                     subtitle: Text('Kelas: $classId • Guru: $teacherId'),
                      //                     trailing: Icon(
                      //                       Icons.chevron_right,
                      //                       color: Colors.grey[400],
                      //                     ),
                      //                   );
                      //                 },
                      //               ),
                      //             ),
                      //           ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Export Button at the bottom
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isExporting ? null : () async {
                      final records = await _fetchAttendanceRecords();
                      await _exportToPDF(records);
                    },
                    icon: _isExporting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.picture_as_pdf, size: 24),
                    label: Text(
                      _isExporting ? 'Membuat PDF...' : 'Buat Laporan Presensi',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, int count, Color color, IconData icon) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              icon,
              color: color,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'advanced_report_screen.dart';
import 'package:excel/excel.dart' as excel;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

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
  String _reportType = 'daily';
  List<QueryDocumentSnapshot>? _classes;
  bool _isExporting = false;
  String? _schoolName;
  final Set<String> _selectedStatuses = <String>{};
  String _sortByStatus = 'hadir';
  bool _sortDescending = true;
  bool _rankingEnabled = false;

  String _slugify(String? input) {
    final s = (input ?? '').trim();
    if (s.isEmpty) return '';
    return s
        .replaceAll(RegExp(r"[\\/:*?\<>|]"), '')
        .replaceAll(RegExp(r"\s+"), '_');
  }

  String _nowStamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
  }

  @override
  void initState() {
    super.initState();
    _fetchClasses();
    _loadSchoolName();
    // Initialize Indonesian locale for month/day names in exports
    initializeDateFormatting('id_ID', null);
  }

  Future<void> _loadSchoolName() async {
    if (widget.userInfo['school_id'] != null) {
      final schoolDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.userInfo['school_id'])
          .get();
      
      if (schoolDoc.exists) {
        setState(() {
          _schoolName = schoolDoc.data()?['name'] ?? 'Sekolah';
        });
      }
    }
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
      // Use orderBy on the same field when doing range queries
      query = query
          .orderBy('date')
          .where('date', isGreaterThanOrEqualTo: start)
          .where('date', isLessThan: end);
    }
    
    try {
    final snapshot = await query.get();
      // If monthly/yearly selected and no data returned, fallback to client-side filter
      if ((_reportType == 'monthly' || _reportType == 'yearly') && _selectedDate != null && snapshot.docs.isEmpty) {
        // Fallback: fetch by equality filters only, then filter in memory
        Query fallback = FirebaseFirestore.instance
            .collection('attendances')
            .where('school_id', isEqualTo: widget.userInfo['school_id']);
        if (_selectedClassId != null && _selectedClassId!.isNotEmpty) {
          fallback = fallback.where('class_id', isEqualTo: _selectedClassId);
        }
        final fb = await fallback.get();
        final docs = fb.docs.where((d) {
          final dt = (d['date'] as Timestamp?)?.toDate();
          if (dt == null) return false;
          if (_reportType == 'monthly') {
            return dt.year == _selectedDate!.year && dt.month == _selectedDate!.month;
          } else {
            return dt.year == _selectedDate!.year;
          }
        }).toList();
        return docs;
      }
    return snapshot.docs;
    } catch (e) {
      // Absolute fallback on any error
      Query fb = FirebaseFirestore.instance
          .collection('attendances')
          .where('school_id', isEqualTo: widget.userInfo['school_id']);
      if (_selectedClassId != null && _selectedClassId!.isNotEmpty) {
        fb = fb.where('class_id', isEqualTo: _selectedClassId);
      }
      final res = await fb.get();
      if (_selectedDate == null) return res.docs;
      return res.docs.where((d) {
        final dt = (d['date'] as Timestamp?)?.toDate();
        if (dt == null) return false;
        switch (_reportType) {
          case 'daily':
            final start = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
            final end = start.add(const Duration(days: 1));
            return dt.isAfter(start.subtract(const Duration(microseconds: 1))) && dt.isBefore(end);
          case 'monthly':
            return dt.year == _selectedDate!.year && dt.month == _selectedDate!.month;
          case 'yearly':
            return dt.year == _selectedDate!.year;
          default:
            return true;
        }
      }).toList();
    }
  }

  Future<void> _exportToPDF(List<QueryDocumentSnapshot> records) async {
    setState(() => _isExporting = true);
    
    try {
      // Create PDF document
      final pdf = pw.Document();
      
      // Get report period string with Indonesian day/month names
      String getReportPeriod() {
        if (_selectedDate == null) return 'Semua Periode';
        switch (_reportType) {
          case 'daily':
            return DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(_selectedDate!);
          case 'monthly':
            return DateFormat('MMMM yyyy', 'id_ID').format(_selectedDate!);
          case 'yearly':
            return 'Tahun ${DateFormat('yyyy', 'id_ID').format(_selectedDate!)}';
          default:
            return DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(_selectedDate!);
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
      
      // Prefetch and process data to avoid long waits and UI stuck
      final Map<String, Map<String, int>> classStats = {};
      final List<Map<String, dynamic>> detailedRecords = [];
      final Map<String, int> studentStatusCounter = {}; // counts for _sortByStatus
      final Map<String, String> studentIdToName = {};
      final Map<String, String> classIdToName = {};
      final Map<String, String> teacherIdToName = {};

      // 1) Collect IDs
      final Set<String> classIds = {};
      final Set<String> teacherIds = {};
      final Set<String> studentIds = {};
      for (final doc in records) {
        final data = doc.data() as Map<String, dynamic>;
        final classId = (data['class_id'] ?? '').toString();
        final teacherId = (data['teacher_id'] ?? '').toString();
        if (classId.isNotEmpty) classIds.add(classId);
        if (teacherId.isNotEmpty) teacherIds.add(teacherId);
        final attendance = data['attendance'] as Map?;
        if (attendance != null) {
          attendance.forEach((sid, st) {
            final status = (st ?? '').toString();
            if (_selectedStatuses.isEmpty || _selectedStatuses.contains(status)) {
              studentIds.add((sid ?? '').toString());
            }
          });
        }
      }

      // 2) Prefetch class docs (chunked by 10)
      Future<void> _prefetchCollection(String collection,
          Set<String> ids, void Function(QueryDocumentSnapshot) onDoc) async {
        const int chunk = 10;
        final idList = ids.toList();
        for (int i = 0; i < idList.length; i += chunk) {
          final part = idList.sublist(i, (i + chunk > idList.length) ? idList.length : i + chunk);
          final snap = await FirebaseFirestore.instance
              .collection(collection)
              .where(FieldPath.documentId, whereIn: part)
              .get();
          for (final d in snap.docs) {
            onDoc(d);
          }
        }
      }

      await _prefetchCollection('classes', classIds, (d) {
        final cd = d.data() as Map<String, dynamic>;
        classIdToName[d.id] = '${cd['grade'] ?? ''} ${cd['class_name'] ?? ''}'.trim().isEmpty
            ? d.id
            : '${cd['grade'] ?? ''} ${cd['class_name'] ?? ''}'.trim();
      });

      // Prefetch teachers by documentId
      await _prefetchCollection('teachers', teacherIds, (d) {
        final td = d.data() as Map<String, dynamic>;
        final teacherName = (td['name'] ?? d.id).toString();
        teacherIdToName[d.id] = teacherName;
        // Also map by NUPTK if present so lookups by nuptk work too
        final nuptk = (td['nuptk'] ?? '').toString();
        if (nuptk.isNotEmpty) {
          teacherIdToName[nuptk] = teacherName;
        }
      });

      // Prefetch teachers by NUPTK as well, for cases where attendance stores NUPTK instead of teacher doc ID
      if (teacherIds.isNotEmpty) {
        const int chunk = 10;
        final idList = teacherIds.toList();
        for (int i = 0; i < idList.length; i += chunk) {
          final part = idList.sublist(i, (i + chunk > idList.length) ? idList.length : i + chunk);
          final snap = await FirebaseFirestore.instance
              .collection('teachers')
              .where('nuptk', whereIn: part)
              .get();
          for (final d in snap.docs) {
            final td = d.data() as Map<String, dynamic>;
            final teacherName = (td['name'] ?? d.id).toString();
            final nuptk = (td['nuptk'] ?? '').toString();
            if (nuptk.isNotEmpty) {
              teacherIdToName[nuptk] = teacherName;
            }
            // Keep docId mapping as well just in case
            teacherIdToName[d.id] = teacherName;
          }
        }
      }

      await _prefetchCollection('students', studentIds, (d) {
        final sd = d.data() as Map<String, dynamic>;
        studentIdToName[d.id] = (sd['name'] ?? d.id).toString();
      });
      
      String _formatPeriodCell(DateTime? dt) {
        if (dt == null) return '-';
        switch (_reportType) {
          case 'daily':
            return DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(dt);
          case 'monthly':
            return DateFormat('MMMM yyyy', 'id_ID').format(dt);
          case 'yearly':
            return DateFormat('yyyy', 'id_ID').format(dt);
          default:
            return DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(dt);
        }
      }
      
      for (final doc in records) {
        final data = doc.data() as Map<String, dynamic>;
        final date = (data['date'] as Timestamp?)?.toDate();
        final classId = data['class_id'] ?? '';
        final teacherId = data['teacher_id'] ?? '';
        final attendance = data['attendance'] as Map?;

        // Fetch class and teacher info with caching
        final className = classIdToName[classId] ?? classId;
        final teacherName = teacherIdToName[teacherId] ?? teacherId;

        // Initialize class stats
        if (!classStats.containsKey(className)) {
          classStats[className] = {'hadir': 0, 'sakit': 0, 'izin': 0, 'alfa': 0, 'total': 0};
        }

        if (attendance != null) {
          for (final entry in attendance.entries) {
            final studentId = entry.key;
            final status = (entry.value ?? '').toString();

            // Apply status filter if any selected
            if (_selectedStatuses.isNotEmpty && !_selectedStatuses.contains(status)) {
              continue;
            }

            // Fetch student name with caching
            final studentName = studentIdToName[studentId] ?? studentId;
            studentIdToName[studentId] = studentName;

            // Update stats
            if (classStats[className]!.containsKey(status)) {
              classStats[className]![status] = classStats[className]![status]! + 1;
            }
            classStats[className]!['total'] = classStats[className]!['total']! + 1;

            // Update student ranking counter for selected status key
            if (status == _sortByStatus) {
              studentStatusCounter[studentId] = (studentStatusCounter[studentId] ?? 0) + 1;
            }

            // Add to detailed records
            detailedRecords.add({
              'date': _formatPeriodCell(date),
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

      // Prepare student ranking list
      final List<MapEntry<String, int>> rankingEntries = _rankingEnabled
          ? (studentStatusCounter.entries.toList()
            ..sort((a, b) => _sortDescending ? b.value.compareTo(a.value) : a.value.compareTo(b.value)))
          : <MapEntry<String, int>>[];

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
                      _schoolName ?? 'SEKOLAH',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue800,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'LAPORAN PRESENSI SISWA',
                      style: pw.TextStyle(
                        fontSize: 16,
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
              'Dibuat pada: ${DateFormat('EEEE, dd MMMM yyyy HH:mm', 'id_ID').format(DateTime.now())}',
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

            // Student Ranking Section
            if (_rankingEnabled && rankingEntries.isNotEmpty) ...[
              pw.SizedBox(height: 25),
            pw.Text(
                'Peringkat Siswa berdasarkan status "${_sortByStatus.toUpperCase()}"',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800,
              ),
            ),
            pw.SizedBox(height: 12),
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
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    children: [
                        _buildTableHeader('No', fontSize: 9),
                      _buildTableHeader('Siswa', fontSize: 9),
                        _buildTableHeader('Jumlah ${_sortByStatus.toUpperCase()}', fontSize: 9),
                    ],
                  ),
                    ...List.generate(rankingEntries.length, (i) => i).map((i) {
                      final entry = rankingEntries[i];
                      final studentName = studentIdToName[entry.key] ?? entry.key;
                      return pw.TableRow(
                    children: [
                          _buildTableCell('${i + 1}', fontSize: 9),
                          _buildTableCell(studentName, fontSize: 9),
                          _buildTableCell('${entry.value}', fontSize: 9, isBold: true),
                        ],
                      );
                    }).toList(),
                ],
              ),
            ),
            ],

            // Detailed Records Section grouped by date and class
            pw.Text(
              'Detail Presensi',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800,
              ),
            ),

            pw.SizedBox(height: 12),

            ..._buildGroupedDetailSections(detailedRecords),

           
          ],
        ),
      );

      // Save PDF with clear file name
      final bytes = await pdf.save();
      final dir = await getApplicationDocumentsDirectory();
      final period = getReportPeriod();
      final kelas = getClassFilter();
      final schoolSlug = _slugify(_schoolName ?? 'Sekolah');
      final periodSlug = _slugify(period);
      final kelasSlug = _slugify(kelas);
      final fileName = '${schoolSlug}_Laporan_Presensi_${_reportType.toUpperCase()}_${periodSlug}_${kelasSlug}_${_nowStamp()}.pdf';
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

  Future<void> _exportToExcel(List<QueryDocumentSnapshot> records) async {
    setState(() => _isExporting = true);
    try {
      // Prepare data similar to PDF export
      final Map<String, Map<String, int>> classStats = {};
      final List<Map<String, dynamic>> detailedRecords = [];
      final Map<String, int> studentStatusCounter = {};
      final Map<String, String> studentIdToName = {};

      for (final doc in records) {
        final data = doc.data() as Map<String, dynamic>;
        final date = (data['date'] as Timestamp?)?.toDate();
        final classId = data['class_id'] ?? '';
        final teacherId = data['teacher_id'] ?? '';
        final attendance = data['attendance'] as Map?;

        final classDoc = await FirebaseFirestore.instance.collection('classes').doc(classId).get();
        final classData = classDoc.data() as Map<String, dynamic>?;
        final className = classData != null ? '${classData['grade'] ?? ''} ${classData['class_name'] ?? ''}'.trim() : classId;

        // Resolve teacher name by either doc id or nuptk
        String teacherName;
        try {
          final tDoc = await FirebaseFirestore.instance.collection('teachers').doc(teacherId).get();
          if (tDoc.exists) {
            final td = tDoc.data() as Map<String, dynamic>?;
            teacherName = (td?['name'] ?? teacherId).toString();
          } else {
            final tq = await FirebaseFirestore.instance.collection('teachers').where('nuptk', isEqualTo: teacherId).limit(1).get();
            teacherName = tq.docs.isNotEmpty ? (tq.docs.first.data()['name'] ?? teacherId).toString() : teacherId;
          }
        } catch (_) {
          teacherName = teacherId;
        }

        classStats.putIfAbsent(className, () => {'hadir': 0, 'sakit': 0, 'izin': 0, 'alfa': 0, 'total': 0});

        if (attendance != null) {
          for (final entry in attendance.entries) {
            final studentId = entry.key;
            final status = (entry.value ?? '').toString();
            if (_selectedStatuses.isNotEmpty && !_selectedStatuses.contains(status)) continue;

            final studentDoc = await FirebaseFirestore.instance.collection('students').doc(studentId).get();
            final studentName = studentDoc.exists ? (studentDoc['name'] ?? studentId) : studentId;
            studentIdToName[studentId] = studentName;

            if (classStats[className]!.containsKey(status)) {
              classStats[className]![status] = classStats[className]![status]! + 1;
            }
            classStats[className]!['total'] = classStats[className]!['total']! + 1;

            if (status == _sortByStatus) {
              studentStatusCounter[studentId] = (studentStatusCounter[studentId] ?? 0) + 1;
            }

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

      final rankings = List<MapEntry<String, int>>.from(studentStatusCounter.entries)
        ..sort((a, b) => _sortDescending ? b.value.compareTo(a.value) : a.value.compareTo(b.value));

      // Create Excel workbook
      final book = excel.Excel.createExcel();
      // Sheets setup - avoid deleting/renaming that mutates internal lists unpredictably
      // Use default 'Sheet1' for summary, then create others by access.
      final String summarySheet = 'Sheet1';
      final String rankingSheet = 'PERINGKAT';
      final String detailSheet = 'DETAIL';

      final summary = book[summarySheet];
      final ranking = book[rankingSheet];
      final detail = book[detailSheet];

      // Headers and styles for summary sheet
      final sA1 = summary.cell(excel.CellIndex.indexByString('A1'));
      sA1.value = _schoolName ?? 'Sekolah';
      sA1.cellStyle = excel.CellStyle(bold: true, fontSize: 18, fontColorHex: 'FF1565C0');
      final sA2 = summary.cell(excel.CellIndex.indexByString('A2'));
      sA2.value = 'Laporan Presensi (${_reportType.toUpperCase()})';
      sA2.cellStyle = excel.CellStyle(bold: true, fontSize: 14, fontColorHex: 'FF1976D2');

      // Table headers at row 4
      const summaryHeaders = ['Kelas', 'Hadir', 'Sakit', 'Izin', 'Alfa', 'Total'];
      for (int c = 0; c < summaryHeaders.length; c++) {
        final cell = summary.cell(excel.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 4));
        cell.value = summaryHeaders[c];
        cell.cellStyle = excel.CellStyle(
          bold: true,
          fontSize: 12,
          fontColorHex: 'FFFFFFFF',
          backgroundColorHex: 'FF1565C0',
          horizontalAlign: excel.HorizontalAlign.Center,
          verticalAlign: excel.VerticalAlign.Center,
          leftBorder: excel.Border(borderStyle: excel.BorderStyle.Thin),
          rightBorder: excel.Border(borderStyle: excel.BorderStyle.Thin),
          topBorder: excel.Border(borderStyle: excel.BorderStyle.Thin),
          bottomBorder: excel.Border(borderStyle: excel.BorderStyle.Thin),
        );
      }
      int sRow = 5;
      for (final entry in classStats.entries) {
        final stats = entry.value;
        final rowValues = [
          entry.key,
          stats['hadir'] ?? 0,
          stats['sakit'] ?? 0,
          stats['izin'] ?? 0,
          stats['alfa'] ?? 0,
          stats['total'] ?? 0,
        ];
        for (int c = 0; c < rowValues.length; c++) {
          final cell = summary.cell(excel.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: sRow));
          cell.value = rowValues[c];
          final even = ((sRow - 4) % 2 == 0);
          cell.cellStyle = excel.CellStyle(
            fontSize: 11,
            backgroundColorHex: even ? 'FFF7FBFF' : 'FFFFFFFF',
            leftBorder: excel.Border(borderStyle: excel.BorderStyle.Thin, borderColorHex: 'FFE0E0E0'),
            rightBorder: excel.Border(borderStyle: excel.BorderStyle.Thin, borderColorHex: 'FFE0E0E0'),
            topBorder: excel.Border(borderStyle: excel.BorderStyle.Thin, borderColorHex: 'FFE0E0E0'),
            bottomBorder: excel.Border(borderStyle: excel.BorderStyle.Thin, borderColorHex: 'FFE0E0E0'),
            horizontalAlign: c == 0 ? excel.HorizontalAlign.Left : excel.HorizontalAlign.Center,
          );
        }
        sRow++;
      }
      // Column widths
      try {
        summary.setColWidth(0, 25);
        for (int c = 1; c <= 5; c++) {
          summary.setColWidth(c, 12);
        }
      } catch (_) {}

      // Ranking sheet
      // Ranking sheet header and table
      final rA1 = ranking.cell(excel.CellIndex.indexByString('A1'));
      rA1.value = 'Peringkat Siswa (${_sortByStatus.toUpperCase()})';
      rA1.cellStyle = excel.CellStyle(bold: true, fontSize: 14, fontColorHex: 'FF1976D2');
      const rankingHeaders = ['No', 'Siswa', 'Jumlah'];
      for (int c = 0; c < rankingHeaders.length; c++) {
        final cell = ranking.cell(excel.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 2));
        cell.value = rankingHeaders[c];
        cell.cellStyle = excel.CellStyle(
          bold: true,
          fontSize: 12,
          fontColorHex: 'FFFFFFFF',
          backgroundColorHex: 'FF2E7D32',
          horizontalAlign: excel.HorizontalAlign.Center,
          leftBorder: excel.Border(borderStyle: excel.BorderStyle.Thin),
          rightBorder: excel.Border(borderStyle: excel.BorderStyle.Thin),
          topBorder: excel.Border(borderStyle: excel.BorderStyle.Thin),
          bottomBorder: excel.Border(borderStyle: excel.BorderStyle.Thin),
        );
      }
      int rRow = 3;
      for (int i = 0; i < rankings.length; i++) {
        final e = rankings[i];
        final vals = [i + 1, studentIdToName[e.key] ?? e.key, e.value];
        for (int c = 0; c < vals.length; c++) {
          final cell = ranking.cell(excel.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rRow));
          cell.value = vals[c];
          final even = ((rRow - 2) % 2 == 0);
          cell.cellStyle = excel.CellStyle(
            fontSize: 11,
            backgroundColorHex: even ? 'FFF1F8E9' : 'FFFFFFFF',
            leftBorder: excel.Border(borderStyle: excel.BorderStyle.Thin, borderColorHex: 'FFE0E0E0'),
            rightBorder: excel.Border(borderStyle: excel.BorderStyle.Thin, borderColorHex: 'FFE0E0E0'),
            topBorder: excel.Border(borderStyle: excel.BorderStyle.Thin, borderColorHex: 'FFE0E0E0'),
            bottomBorder: excel.Border(borderStyle: excel.BorderStyle.Thin, borderColorHex: 'FFE0E0E0'),
            horizontalAlign: c == 1 ? excel.HorizontalAlign.Left : excel.HorizontalAlign.Center,
          );
        }
        rRow++;
      }
      try {
        ranking.setColWidth(0, 6);
        ranking.setColWidth(1, 30);
        ranking.setColWidth(2, 10);
      } catch (_) {}

      // Detail sheet
      // Detail sheet header and table
      final dA1 = detail.cell(excel.CellIndex.indexByString('A1'));
      dA1.value = 'Detail Presensi';
      dA1.cellStyle = excel.CellStyle(bold: true, fontSize: 14, fontColorHex: 'FF1976D2');
      const detailHeaders = ['Periode', 'Kelas', 'Guru', 'Siswa', 'Status'];
      for (int c = 0; c < detailHeaders.length; c++) {
        final cell = detail.cell(excel.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 2));
        cell.value = detailHeaders[c];
        cell.cellStyle = excel.CellStyle(
          bold: true,
          fontSize: 12,
          fontColorHex: 'FFFFFFFF',
          backgroundColorHex: 'FF0D47A1',
          horizontalAlign: excel.HorizontalAlign.Center,
          leftBorder: excel.Border(borderStyle: excel.BorderStyle.Thin),
          rightBorder: excel.Border(borderStyle: excel.BorderStyle.Thin),
          topBorder: excel.Border(borderStyle: excel.BorderStyle.Thin),
          bottomBorder: excel.Border(borderStyle: excel.BorderStyle.Thin),
        );
      }
      int dRow = 3;
      for (final rec in detailedRecords) {
        final vals = [rec['date'], rec['class'], rec['teacher'], rec['student'], rec['status']];
        for (int c = 0; c < vals.length; c++) {
          final cell = detail.cell(excel.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: dRow));
          cell.value = vals[c];
          final even = ((dRow - 2) % 2 == 0);
          cell.cellStyle = excel.CellStyle(
            fontSize: 11,
            backgroundColorHex: even ? 'FFE3F2FD' : 'FFFFFFFF',
            leftBorder: excel.Border(borderStyle: excel.BorderStyle.Thin, borderColorHex: 'FFE0E0E0'),
            rightBorder: excel.Border(borderStyle: excel.BorderStyle.Thin, borderColorHex: 'FFE0E0E0'),
            topBorder: excel.Border(borderStyle: excel.BorderStyle.Thin, borderColorHex: 'FFE0E0E0'),
            bottomBorder: excel.Border(borderStyle: excel.BorderStyle.Thin, borderColorHex: 'FFE0E0E0'),
            horizontalAlign: c == 3 ? excel.HorizontalAlign.Left : excel.HorizontalAlign.Center,
          );
        }
        dRow++;
      }
      try {
        detail.setColWidth(0, 14);
        detail.setColWidth(1, 16);
        detail.setColWidth(2, 18);
        detail.setColWidth(3, 28);
        detail.setColWidth(4, 12);
      } catch (_) {}

      final bytes = book.encode()!;
      final dir = await getApplicationDocumentsDirectory();
      // Match PDF naming
      final period = (_selectedDate == null)
          ? 'Semua Periode'
          : (_reportType == 'daily'
              ? DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(_selectedDate!)
              : _reportType == 'monthly'
                  ? DateFormat('MMMM yyyy', 'id_ID').format(_selectedDate!)
                  : 'Tahun ${DateFormat('yyyy', 'id_ID').format(_selectedDate!)}');
      final kelas = (_selectedClassId == null || _selectedClassId!.isEmpty)
          ? 'Semua Kelas'
          : (() {
              final selected = _classes?.firstWhere(
                (doc) => doc.id == _selectedClassId,
                orElse: () => _classes!.first,
              );
              final data = selected?.data() as Map<String, dynamic>?;
              return data != null ? 'Kelas ${data['grade'] ?? ''} ${data['class_name'] ?? ''}'.trim() : 'Kelas Terpilih';
            })();
      final schoolSlug = _slugify(_schoolName ?? 'Sekolah');
      final periodSlug = _slugify(period);
      final kelasSlug = _slugify(kelas);
      final fileName = '${schoolSlug}_Laporan_Presensi_${_reportType.toUpperCase()}_${periodSlug}_${kelasSlug}_${_nowStamp()}.xlsx';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      setState(() => _isExporting = false);
      await Share.shareXFiles([XFile(file.path)], text: 'Laporan Presensi Excel');
    } catch (e) {
      setState(() => _isExporting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating Excel: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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

  List<pw.Widget> _buildGroupedDetailSections(List<Map<String, dynamic>> detailedRecords) {
    // Group by date -> class
    final Map<String, Map<String, List<Map<String, dynamic>>>> grouped = {};
    for (final rec in detailedRecords) {
      final date = (rec['date'] ?? '-') as String; // already formatted as per report type
      final kelas = (rec['class'] ?? '-') as String;
      grouped.putIfAbsent(date, () => {});
      grouped[date]!.putIfAbsent(kelas, () => []);
      grouped[date]![kelas]!.add(rec);
    }

    final List<pw.Widget> sections = [];
    final dates = grouped.keys.toList()..sort();
    for (final date in dates) {
      sections.add(pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey200,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Text(
          'Tanggal: $date',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
        ),
      ));
      sections.add(pw.SizedBox(height: 8));

      final kelasMap = grouped[date]!;
      final kelasList = kelasMap.keys.toList()..sort();
      for (final kelas in kelasList) {
        sections.add(pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: pw.BoxDecoration(
            color: PdfColors.blue50,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Text(
            'Kelas: $kelas',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800),
          ),
        ));
        sections.add(pw.SizedBox(height: 6));

        final rows = kelasMap[kelas]!;
        sections.add(pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300, width: 1),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Table(
            border: pw.TableBorder.symmetric(
              inside: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
            ),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                children: [
                  _buildTableHeader('Siswa', fontSize: 9),
                  _buildTableHeader('Status', fontSize: 9),
                  _buildTableHeader('Guru', fontSize: 9),
                ],
              ),
              ...rows.map((r) => pw.TableRow(
                children: [
                  _buildTableCell(r['student'], fontSize: 9),
                  _buildStatusCell(r['status'], fontSize: 9),
                  _buildTableCell(r['teacher'], fontSize: 9),
                ],
              )),
            ],
          ),
        ));
        sections.add(pw.SizedBox(height: 12));
      }
      sections.add(pw.SizedBox(height: 14));
    }
    return sections;
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
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
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

                              // Class and Date Selectors (stacked to take full width)
                              Column(
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
                                  const SizedBox(height: 16),
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

                              const SizedBox(height: 16),

                              // Status filters
                              const SizedBox(height: 12),
                              const Text(
                                'Filter Status',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final status in ['hadir','sakit','izin','alfa'])
                                    FilterChip(
                                      label: Text(status.toUpperCase()),
                                      selected: _selectedStatuses.contains(status),
                                      onSelected: (sel) {
                                        setState(() {
                                          if (sel) {
                                            _selectedStatuses.add(status);
                                          } else {
                                            _selectedStatuses.remove(status);
                                          }
                                        });
                                      },
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Urutkan berdasarkan status',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Switch(
                                        value: _rankingEnabled,
                                        onChanged: (v) => setState(() => _rankingEnabled = v),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          isExpanded: true,
                                          value: _rankingEnabled ? _sortByStatus : null,
                                          hint: const Text('Pilih status'),
                                          decoration: const InputDecoration(
                                            border: OutlineInputBorder(),
                                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          ),
                                          items: const [
                                            DropdownMenuItem(value: 'hadir', child: Text('HADIR')),
                                            DropdownMenuItem(value: 'sakit', child: Text('SAKIT')),
                                            DropdownMenuItem(value: 'izin', child: Text('IZIN')),
                                            DropdownMenuItem(value: 'alfa', child: Text('ALFA')),
                                          ],
                                          onChanged: _rankingEnabled
                                              ? (v) => setState(() => _sortByStatus = v ?? 'hadir')
                                              : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Urutan menurun'),
                                    value: _sortDescending,
                                    onChanged: (v) => setState(() => _sortDescending = v ?? true),
                                    controlAffinity: ListTileControlAffinity.leading,
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),
                              // Reset Button
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => setState(() {
                                      _selectedClassId = null;
                                      _selectedDate = null;
                                      _selectedStatuses.clear();
                                      _sortByStatus = 'hadir';
                                      _sortDescending = true;
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
                      FutureBuilder<List<QueryDocumentSnapshot>>(
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

                            // Calculate statistics reflecting selected status filters
                            int hadir = 0, sakit = 0, izin = 0, alfa = 0;
                            for (final doc in records) {
                              final data = doc.data() as Map<String, dynamic>;
                              final attendance = data['attendance'] as Map?;
                              if (attendance != null) {
                                for (final raw in attendance.values) {
                                  final s = (raw ?? '').toString();
                                  if (_selectedStatuses.isNotEmpty && !_selectedStatuses.contains(s)) {
                                    continue;
                                  }
                                  if (s == 'hadir') hadir++;
                                  if (s == 'sakit') sakit++;
                                  if (s == 'izin') izin++;
                                  if (s == 'alfa') alfa++;
                                }
                              }
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                 // Statistics Cards (reflect status filters immediately)
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
                      // Show export options
                      if (!mounted) return;
                      await showModalBottomSheet(
                        context: context,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        builder: (context) {
                          return SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                                    title: const Text('Export ke PDF'),
                                    onTap: () async {
                                      Navigator.pop(context);
                                      // Ensure state shows loading spinner
                                      setState(() => _isExporting = true);
                      await _exportToPDF(records);
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.grid_on, color: Colors.green),
                                    title: const Text('Export ke Excel (XLSX)'),
                                    onTap: () async {
                                      Navigator.pop(context);
                                      // Ensure state shows loading spinner
                                      setState(() => _isExporting = true);
                                      await _exportToExcel(records);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
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
                        : const Icon(Icons.ios_share, size: 24),
                    label: Text(
                      _isExporting ? 'Mengekspor...' : 'Export Laporan',
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
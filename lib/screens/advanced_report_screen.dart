import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/analytics_service.dart';
import '../services/export_service.dart';

class AdvancedReportScreen extends StatefulWidget {
  final Map<String, String> userInfo;
  final String role;

  const AdvancedReportScreen({
    Key? key,
    required this.userInfo,
    required this.role,
  }) : super(key: key);

  @override
  State<AdvancedReportScreen> createState() => _AdvancedReportScreenState();
}

class _AdvancedReportScreenState extends State<AdvancedReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1); // Start of current month
  DateTime _endDate = DateTime.now();
  String? _selectedClassId;
  String? _selectedYearId;
  bool _loading = false;
  Map<String, dynamic> _currentData = {};
  Map<String, dynamic> _currentSummary = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _loading = true);
    await _loadData();
    setState(() => _loading = false);
  }

  Future<void> _loadData() async {
    switch (_tabController.index) {
      case 0:
        await _loadAttendanceTrends();
        break;
      case 1:
        await _loadStudentPerformance();
        break;
      case 2:
        await _loadClassComparison();
        break;
      case 3:
        await _loadTeacherPerformance();
        break;
    }
  }

  Future<void> _loadAttendanceTrends() async {
    print('Loading attendance trends for dates: ${_startDate} to ${_endDate}');
    print('Selected class: $_selectedClassId');
    print('Teacher ID: ${widget.role == 'guru' ? widget.userInfo['nuptk'] : null}');
    
    // First, let's test with a simple query to see if there's any data
    try {
      final testSnapshot = await FirebaseFirestore.instance
          .collection('attendances')
          .limit(5)
          .get();
      print('Test query found ${testSnapshot.docs.length} records');
      if (testSnapshot.docs.isNotEmpty) {
        print('Test record data: ${testSnapshot.docs.first.data()}');
      }
    } catch (e) {
      print('Test query error: $e');
    }
    
    final result = await AnalyticsService.getAttendanceTrends(
      startDate: _startDate,
      endDate: _endDate,
      classId: _selectedClassId,
      teacherId: widget.role == 'guru' ? widget.userInfo['nuptk'] : null,
    );

    print('Analytics result: $result');

    setState(() {
      _currentData = Map<String, dynamic>.from(result);
      _currentSummary = Map<String, dynamic>.from(result['summary'] ?? {});
    });
  }

  Future<void> _loadStudentPerformance() async {
    // For demo, we'll show performance for the first student
    // In a real app, you'd have a student selector
    final studentsSnapshot = await FirebaseFirestore.instance
        .collection('students')
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();

    if (studentsSnapshot.docs.isNotEmpty) {
      final studentId = studentsSnapshot.docs.first.id;
      final result = await AnalyticsService.getStudentPerformance(
        studentId: studentId,
        startDate: _startDate,
        endDate: _endDate,
      );

      setState(() {
        _currentData = Map<String, dynamic>.from(result);
        _currentSummary = Map<String, dynamic>.from(result['stats'] ?? {});
      });
    }
  }

  Future<void> _loadClassComparison() async {
    if (_selectedYearId == null) {
      // Get current year
      final currentYear = DateTime.now().year.toString();
      final currentYearMinusOne = DateTime.now().year.toInt() - 1;
      final currentYearMinusOneStr = currentYearMinusOne.toString();

              final yearQuery = await FirebaseFirestore.instance
            .collection('school_years')
            .where('name', isGreaterThanOrEqualTo: '$currentYear/')
            .where('name', isLessThan: '$currentYearMinusOneStr/')
            .limit(1)
            .get();

      if (yearQuery.docs.isNotEmpty) {
        _selectedYearId = yearQuery.docs.first.id;
      }
    }

    if (_selectedYearId != null) {
      final result = await AnalyticsService.getClassComparison(
        yearId: _selectedYearId!,
        startDate: _startDate,
        endDate: _endDate,
      );

      setState(() {
        _currentData = Map<String, dynamic>.from(result);
        _currentSummary = Map<String, dynamic>.from(result['summary'] ?? {});
      });
    }
  }

  Future<void> _loadTeacherPerformance() async {
    final result = await AnalyticsService.getTeacherPerformance(
      teacherId: widget.userInfo['nuptk'] ?? '',
      startDate: _startDate,
      endDate: _endDate,
    );

    setState(() {
      _currentData = Map<String, dynamic>.from(result);
      _currentSummary = Map<String, dynamic>.from(result['stats'] ?? {});
    });
  }

  Future<void> _exportReport(String format) async {
    try {
      setState(() => _loading = true);

      final reportTypes = ['TREN PRESENSI', 'PERFORMANCE SISWA', 'PERBANDINGAN KELAS', 'PERFORMANCE GURU'];
      final reportType = reportTypes[_tabController.index];
      final fileName = 'Laporan_${reportType}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}';
      
      String filePath;
      if (format == 'excel') {
        filePath = await ExportService.exportAttendanceToCSV(
          data: _currentData['data'] ?? [],
          reportType: reportType,
          fileName: fileName,
        );
      } else {
        filePath = await ExportService.exportAttendanceToCSV(
          data: _currentData['data'] ?? [],
          reportType: reportType,
          fileName: fileName,
        );
      }

      await ExportService.shareFile(filePath, fileName);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Laporan berhasil diekspor ke CSV!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengekspor: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Lanjutan'),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          PopupMenuButton<String>(
            onSelected: _exportReport,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'csv',
                child: Row(
                  children: [
                    Icon(Icons.table_chart, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Ekspor CSV'),
                  ],
                ),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(Icons.download),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          onTap: (index) => _loadData(),
          tabs: const [
            Tab(text: 'Tren Presensi'),
            Tab(text: 'Performance Siswa'),
            Tab(text: 'Perbandingan Kelas'),
            Tab(text: 'Performance Guru'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAttendanceTrendsTab(),
                _buildStudentPerformanceTab(),
                _buildClassComparisonTab(),
                _buildTeacherPerformanceTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filter', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _startDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setState(() => _startDate = date);
                        _loadData();
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Tanggal Mulai',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(DateFormat('dd/MM/yyyy').format(_startDate)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _endDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setState(() => _endDate = date);
                        _loadData();
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Tanggal Akhir',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(DateFormat('dd/MM/yyyy').format(_endDate)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceTrendsTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final data = _currentData['data'] as List<dynamic>? ?? [];
    if (data.isEmpty) {
      return const Center(child: Text('Tidak ada data untuk ditampilkan'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSummaryCards(),
          const SizedBox(height: 24),
          _buildAttendanceTrendChart(data),
          const SizedBox(height: 24),
          _buildAttendanceDataTable(data),
        ],
      ),
    );
  }

  Widget _buildStudentPerformanceTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final student = _currentData['student'] as Map<String, dynamic>?;
    final stats = _currentData['stats'] as Map<String, dynamic>? ?? {};
    final dailyAttendance = _currentData['dailyAttendance'] as List<dynamic>? ?? [];

    if (student == null) {
      return const Center(child: Text('Tidak ada data siswa'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Siswa: ${student['name']}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('Gender: ${student['gender'] ?? '-'}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildPerformancePieChart(stats),
          const SizedBox(height: 24),
          _buildPerformanceDataTable(dailyAttendance),
        ],
      ),
    );
  }

  Widget _buildClassComparisonTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final data = _currentData['data'] as List<dynamic>? ?? [];
    if (data.isEmpty) {
      return const Center(child: Text('Tidak ada data untuk ditampilkan'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSummaryCards(),
          const SizedBox(height: 24),
          _buildClassComparisonChart(data),
          const SizedBox(height: 24),
          _buildClassComparisonTable(data),
        ],
      ),
    );
  }

  Widget _buildTeacherPerformanceTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final teacher = _currentData['teacher'] as Map<String, dynamic>?;
    final stats = _currentData['stats'] as Map<String, dynamic>? ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (teacher != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Guru: ${teacher['name']}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('NUPTK: ${teacher['nuptk'] ?? '-'}'),
                    Text('Role: ${teacher['role'] ?? '-'}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _buildTeacherPerformanceCards(stats),
          const SizedBox(height: 24),
          _buildTeacherPerformanceChart(stats),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final summary = _currentSummary;
    if (summary.isEmpty) return const SizedBox.shrink();

    return Row(
      children: summary.entries.map((entry) {
        return Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    entry.value.toString(),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    entry.key,
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAttendanceTrendChart(List<dynamic> data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tren Kehadiran', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < data.length) {
                            final date = data[value.toInt()]['date'] as String;
                            return Text(date.substring(5)); // Show only MM-DD
                          }
                          return const Text('');
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: data.asMap().entries.map((entry) {
                        return FlSpot(entry.key.toDouble(), (entry.value['hadir'] ?? 0).toDouble());
                      }).toList(),
                      isCurved: true,
                      color: Colors.green,
                      barWidth: 3,
                      dotData: FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: data.asMap().entries.map((entry) {
                        return FlSpot(entry.key.toDouble(), (entry.value['alfa'] ?? 0).toDouble());
                      }).toList(),
                      isCurved: true,
                      color: Colors.red,
                      barWidth: 3,
                      dotData: FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformancePieChart(Map<String, dynamic> stats) {
    final hadir = stats['hadir'] ?? 0;
    final sakit = stats['sakit'] ?? 0;
    final izin = stats['izin'] ?? 0;
    final alfa = stats['alfa'] ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Distribusi Kehadiran', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: PieChart(
                PieChartData(
                  sections: [
                    PieChartSectionData(
                      value: hadir.toDouble(),
                      title: 'Hadir\n$hadir',
                      color: Colors.green,
                      radius: 80,
                    ),
                    PieChartSectionData(
                      value: sakit.toDouble(),
                      title: 'Sakit\n$sakit',
                      color: Colors.orange,
                      radius: 80,
                    ),
                    PieChartSectionData(
                      value: izin.toDouble(),
                      title: 'Izin\n$izin',
                      color: Colors.blue,
                      radius: 80,
                    ),
                    PieChartSectionData(
                      value: alfa.toDouble(),
                      title: 'Alfa\n$alfa',
                      color: Colors.red,
                      radius: 80,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClassComparisonChart(List<dynamic> data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Perbandingan Kelas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 100,
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text('${value.toInt()}%');
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < data.length) {
                            return Text(data[value.toInt()]['className'] ?? '');
                          }
                          return const Text('');
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  barGroups: data.asMap().entries.map((entry) {
                    return BarChartGroupData(
                      x: entry.key,
                      barRods: [
                        BarChartRodData(
                          toY: (entry.value['attendancePercentage'] ?? 0).toDouble(),
                          color: Colors.blue,
                          width: 20,
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherPerformanceCards(Map<String, dynamic> stats) {
    return Row(
      children: [
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    '${stats['totalClasses'] ?? 0}',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const Text('Total Kelas', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    '${stats['uniqueStudents'] ?? 0}',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const Text('Siswa Unik', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    '${(stats['averageAttendance'] ?? 0).toStringAsFixed(1)}',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const Text('Rata-rata Hadir', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTeacherPerformanceChart(Map<String, dynamic> stats) {
    final hadir = stats['hadir'] ?? 0;
    final sakit = stats['sakit'] ?? 0;
    final izin = stats['izin'] ?? 0;
    final alfa = stats['alfa'] ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Statistik Kehadiran', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final labels = ['Hadir', 'Sakit', 'Izin', 'Alfa'];
                          if (value.toInt() >= 0 && value.toInt() < labels.length) {
                            return Text(labels[value.toInt()]);
                          }
                          return const Text('');
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  barGroups: [
                    BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: hadir.toDouble(), color: Colors.green)]),
                    BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: sakit.toDouble(), color: Colors.orange)]),
                    BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: izin.toDouble(), color: Colors.blue)]),
                    BarChartGroupData(x: 3, barRods: [BarChartRodData(toY: alfa.toDouble(), color: Colors.red)]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceDataTable(List<dynamic> data) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Tanggal')),
            DataColumn(label: Text('Hadir')),
            DataColumn(label: Text('Sakit')),
            DataColumn(label: Text('Izin')),
            DataColumn(label: Text('Alfa')),
            DataColumn(label: Text('Total')),
          ],
          rows: data.map((row) {
            return DataRow(
              cells: [
                DataCell(Text(row['date'] ?? '')),
                DataCell(Text('${row['hadir'] ?? 0}')),
                DataCell(Text('${row['sakit'] ?? 0}')),
                DataCell(Text('${row['izin'] ?? 0}')),
                DataCell(Text('${row['alfa'] ?? 0}')),
                DataCell(Text('${row['total'] ?? 0}')),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPerformanceDataTable(List<dynamic> data) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Tanggal')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Kelas')),
          ],
          rows: data.map((row) {
            return DataRow(
              cells: [
                DataCell(Text(row['date'] ?? '')),
                DataCell(Text(row['status'] ?? '')),
                DataCell(Text(row['class_id'] ?? '')),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildClassComparisonTable(List<dynamic> data) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Kelas')),
            DataColumn(label: Text('Jumlah Siswa')),
            DataColumn(label: Text('Total Hari')),
            DataColumn(label: Text('Hadir')),
            DataColumn(label: Text('Sakit')),
            DataColumn(label: Text('Izin')),
            DataColumn(label: Text('Alfa')),
            DataColumn(label: Text('Persentase')),
          ],
          rows: data.map((row) {
            return DataRow(
              cells: [
                DataCell(Text(row['className'] ?? '')),
                DataCell(Text('${row['studentCount'] ?? 0}')),
                DataCell(Text('${row['totalDays'] ?? 0}')),
                DataCell(Text('${row['hadir'] ?? 0}')),
                DataCell(Text('${row['sakit'] ?? 0}')),
                DataCell(Text('${row['izin'] ?? 0}')),
                DataCell(Text('${row['alfa'] ?? 0}')),
                DataCell(Text('${(row['attendancePercentage'] ?? 0).toStringAsFixed(2)}%')),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
} 
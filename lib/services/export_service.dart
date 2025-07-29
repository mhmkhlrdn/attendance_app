import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

class ExportService {
  /// Export attendance data to CSV
  static Future<String> exportToCSV({
    required List<Map<String, dynamic>> data,
    required String reportType,
    required String fileName,
  }) async {
    try {
      List<List<String>> rows = [
        ['LAPORAN $reportType'],
        ['Dibuat pada: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}'],
        [''], // Empty row
      ];

      // Add headers based on data
      if (data.isNotEmpty) {
        rows.add(data.first.keys.map((key) => key.toString()).toList());
        
        // Add data rows
        for (var row in data) {
          rows.add(row.values.map((value) => value?.toString() ?? '').toList());
        }
      }

      String csv = const ListToCsvConverter().convert(rows);
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName.csv');
      await file.writeAsString(csv);

      return file.path;
    } catch (e) {
      throw Exception('Gagal mengekspor ke CSV: $e');
    }
  }

  /// Share file
  static Future<void> shareFile(String filePath, String fileName) async {
    try {
      await Share.shareXFiles([XFile(filePath)], text: 'Laporan: $fileName');
    } catch (e) {
      throw Exception('Gagal membagikan file: $e');
    }
  }

  /// Export attendance data to CSV with custom formatting
  static Future<String> exportAttendanceToCSV({
    required List<Map<String, dynamic>> data,
    required String reportType,
    required String fileName,
  }) async {
    try {
      List<List<String>> rows = [
        ['LAPORAN $reportType'],
        ['Dibuat pada: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}'],
        [''], // Empty row
      ];

      // Add specific headers based on report type
      switch (reportType.toUpperCase()) {
        case 'TREN PRESENSI':
          rows.add(['Tanggal', 'Hadir', 'Sakit', 'Izin', 'Alfa', 'Total']);
          for (var row in data) {
            rows.add([
              row['date']?.toString() ?? '',
              (row['hadir'] ?? 0).toString(),
              (row['sakit'] ?? 0).toString(),
              (row['izin'] ?? 0).toString(),
              (row['alfa'] ?? 0).toString(),
              (row['total'] ?? 0).toString(),
            ]);
          }
          break;
        case 'PERFORMANCE SISWA':
          rows.add(['Tanggal', 'Status', 'Kelas']);
          for (var row in data) {
            rows.add([
              row['date']?.toString() ?? '',
              row['status']?.toString() ?? '',
              row['class_id']?.toString() ?? '',
            ]);
          }
          break;
        case 'PERBANDINGAN KELAS':
          rows.add(['Kelas', 'Jumlah Siswa', 'Total Hari', 'Hadir', 'Sakit', 'Izin', 'Alfa', 'Persentase Kehadiran']);
          for (var row in data) {
            rows.add([
              row['className']?.toString() ?? '',
              (row['studentCount'] ?? 0).toString(),
              (row['totalDays'] ?? 0).toString(),
              (row['hadir'] ?? 0).toString(),
              (row['sakit'] ?? 0).toString(),
              (row['izin'] ?? 0).toString(),
              (row['alfa'] ?? 0).toString(),
              '${(row['attendancePercentage'] ?? 0).toStringAsFixed(2)}%',
            ]);
          }
          break;
        case 'PERFORMANCE GURU':
          rows.add(['Kelas', 'Jumlah Presensi']);
          if (data.isNotEmpty && data.first.containsKey('classAttendance')) {
            final classAttendance = data.first['classAttendance'] as Map<String, dynamic>? ?? {};
            classAttendance.forEach((classId, count) {
              rows.add([classId.toString(), count.toString()]);
            });
          }
          break;
        default:
          // Generic export
          if (data.isNotEmpty) {
            rows.add(data.first.keys.map((key) => key.toString()).toList());
            for (var row in data) {
              rows.add(row.values.map((value) => value?.toString() ?? '').toList());
            }
          }
      }

      String csv = const ListToCsvConverter().convert(rows);
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName.csv');
      await file.writeAsString(csv);

      return file.path;
    } catch (e) {
      throw Exception('Gagal mengekspor ke CSV: $e');
    }
  }
} 
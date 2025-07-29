import 'package:flutter/material.dart';
import '../services/local_storage_service.dart';
import '../services/offline_sync_service.dart';
import '../services/connectivity_service.dart';

class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({Key? key}) : super(key: key);

  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  List<Map<String, dynamic>> _pendingAttendance = [];
  bool _isOnline = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPendingData();
    _initializeConnectivity();
  }

  void _initializeConnectivity() {
    final connectivityService = ConnectivityService();
    connectivityService.connectionStatus.listen((isOnline) {
      setState(() {
        _isOnline = isOnline;
      });
    });
  }

  Future<void> _loadPendingData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final pendingData = await LocalStorageService.getPendingAttendance();
      setState(() {
        _pendingAttendance = pendingData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading pending data: $e')),
        );
      }
    }
  }

  Future<void> _syncNow() async {
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada koneksi internet. Sinkronisasi akan dilakukan saat online.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await OfflineSyncService.syncPendingAttendance();
      await _loadPendingData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sinkronisasi berhasil!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during sync: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Status Sinkronisasi'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPendingData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Connection status card
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          _isOnline ? Icons.wifi : Icons.wifi_off,
                          color: _isOnline ? Colors.green : Colors.red,
                          size: 32,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isOnline ? 'Terhubung' : 'Tidak Terhubung',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _isOnline ? 'Internet tersedia' : 'Tidak ada koneksi internet',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Pending data card
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.pending_actions,
                              color: _pendingAttendance.isNotEmpty ? Colors.orange : Colors.green,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Data Pending',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_pendingAttendance.length} presensi menunggu sinkronisasi',
                          style: TextStyle(
                            color: Colors.grey[600],
                          ),
                        ),
                        if (_pendingAttendance.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isOnline ? _syncNow : null,
                              icon: const Icon(Icons.sync),
                              label: const Text('Sinkronisasi Sekarang'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                
                // Pending attendance list
                if (_pendingAttendance.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _pendingAttendance.length,
                      itemBuilder: (context, index) {
                        final attendance = _pendingAttendance[index];
                        final date = attendance['date'] as DateTime?;
                        final classId = attendance['class_id'] as String?;
                        final studentCount = (attendance['student_ids'] as List<dynamic>?)?.length ?? 0;
                        
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: ListTile(
                            leading: const Icon(Icons.assignment, color: Colors.blue),
                            title: Text('Presensi Kelas: $classId'),
                            subtitle: Text(
                              'Tanggal: ${date?.toString().split(' ')[0] ?? 'N/A'}\n'
                              'Siswa: $studentCount orang',
                            ),
                            trailing: Icon(
                              Icons.pending,
                              color: Colors.orange,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 32),
                  const Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 64,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Tidak ada data pending',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Semua data telah tersinkronisasi',
                          style: TextStyle(
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
} 
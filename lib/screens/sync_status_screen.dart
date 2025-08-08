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
  bool _isSyncing = false; // New flag to prevent multiple sync operations
  Map<String, dynamic> _syncStatus = {};

  @override
  void initState() {
    super.initState();
    _loadPendingData();
    _initializeConnectivity();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh connectivity status when screen becomes active
    _refreshConnectivityStatus();
  }

  void _initializeConnectivity() {
    final connectivityService = ConnectivityService();
    connectivityService.connectionStatus.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
        _loadSyncStatus();
      }
    });
  }

  Future<void> _refreshConnectivityStatus() async {
    final connectivityService = ConnectivityService();
    final isOnline = await connectivityService.checkConnectivity();
    if (mounted) {
      setState(() {
        _isOnline = isOnline;
      });
      _loadSyncStatus();
    }
  }

  Future<void> _loadSyncStatus() async {
    try {
      final status = await OfflineSyncService.getSyncStatus();
      if (mounted) {
        setState(() {
          _syncStatus = status;
        });
      }
    } catch (e) {
      print('Error loading sync status: $e');
    }
  }

  Future<void> _loadPendingData() async {
    if (_isLoading) return; // Prevent multiple simultaneous loads
    
    setState(() {
      _isLoading = true;
    });

    try {
      final pendingData = await LocalStorageService.getPendingAttendance();
      if (mounted) {
        setState(() {
          _pendingAttendance = pendingData;
          _isLoading = false;
        });
        await _loadSyncStatus(); // Refresh sync status after loading pending data
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading pending data: $e')),
        );
      }
    }
  }

  Future<void> _syncNow() async {
    // Prevent multiple sync operations
    if (_isSyncing || !_isOnline) {
      if (!_isOnline) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak ada koneksi internet. Sinkronisasi akan dilakukan saat online.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() {
      _isSyncing = true;
      _isLoading = true;
    });

    try {
      final initialCount = _pendingAttendance.length;
      
      // Perform the sync operation
      await OfflineSyncService.syncPendingAttendance();
      
      // Reload pending data to get updated state
      await _loadPendingData();
      
      final finalCount = _pendingAttendance.length;
      final syncedCount = initialCount - finalCount;
      
      if (mounted) {
        if (syncedCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Berhasil menyinkronkan $syncedCount presensi!'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (initialCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Presensi sudah ada di server. Data duplikat dicegah.'),
              backgroundColor: Colors.blue,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tidak ada data yang perlu disinkronkan.'),
              backgroundColor: Colors.green,
            ),
          );
        }
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
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _clearAllPendingData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Pending Data'),
        content: const Text('This will remove all pending attendance data. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await LocalStorageService.clearPendingAttendance();
        await _loadPendingData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All pending data cleared'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error clearing pending data: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _showDebugInfo() async {
    try {
      final debugInfo = await OfflineSyncService.getDetailedSyncInfo();
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Debug Information'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Pending Count: ${debugInfo['pendingCount']}'),
                  Text('Is Connected: ${debugInfo['isConnected']}'),
                  Text('Is Syncing: ${debugInfo['isSyncing']}'),
                  Text('Last Sync: ${debugInfo['lastSync'] ?? 'Never'}'),
                  const SizedBox(height: 16),
                  const Text('Pending Details:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...(debugInfo['pendingDetails'] as List<dynamic>).map((detail) => 
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 4),
                      child: Text('• ${detail['class_id']} - ${detail['date']} (${detail['student_count']} students)'),
                    )
                  ).toList(),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting debug info: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDateTime(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    final date = DateTime.tryParse(timestamp.toString());
    if (date == null) return 'Invalid Date';
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute}';
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
            onPressed: _isLoading ? null : _loadPendingData,
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'clear_pending') {
                await _clearAllPendingData();
              } else if (value == 'debug_info') {
                await _showDebugInfo();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear_pending',
                child: Row(
                  children: [
                    Icon(Icons.clear_all, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Clear All Pending'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'debug_info',
                child: Row(
                  children: [
                    Icon(Icons.bug_report, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Debug Info'),
                  ],
                ),
              ),
            ],
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
                              onPressed: (_isOnline && !_isSyncing) ? _syncNow : null,
                              icon: _isSyncing 
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Icon(Icons.sync),
                              label: Text(_isSyncing ? 'Menyinkronkan...' : 'Sinkronisasi Sekarang'),
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
                
                // Sync status card
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
                              Icons.info_outline,
                              color: Colors.blue,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Status Sinkronisasi',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_syncStatus['lastSync'] != null) ...[
                          Text(
                            'Terakhir sinkronisasi: ${_formatDateTime(_syncStatus['lastSync'])}',
                            style: TextStyle(
                              color: Colors.grey[600],
                            ),
                          ),
                        ] else ...[
                          Text(
                            'Belum pernah sinkronisasi',
                            style: TextStyle(
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          'Fitur pencegahan duplikat: Aktif',
                          style: TextStyle(
                            color: Colors.green[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_isSyncing) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Status: Sedang menyinkronkan...',
                            style: TextStyle(
                              color: Colors.orange[600],
                              fontWeight: FontWeight.w500,
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
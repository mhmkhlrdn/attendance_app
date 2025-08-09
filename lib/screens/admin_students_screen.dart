
import 'package:attendance_app/screens/schedule_list_screen.dart';
import 'package:attendance_app/screens/student_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'attendance_screen.dart';
import 'class_list_screen.dart';
import 'login_screen.dart';
import 'student_form_screen.dart';
import 'create_class_screen.dart';
import 'teacher_list_screen.dart';
import 'attendance_history_screen.dart';
import 'attendance_report_screen.dart';
import 'promotion_screen.dart';
import 'data_migration_screen.dart';
import 'version_management_screen.dart';
import 'change_password_screen.dart';
import '../services/local_storage_service.dart';
import '../services/connectivity_service.dart';
import '../services/offline_sync_service.dart';
import '../services/version_update_service.dart';
import 'sync_status_screen.dart';
import 'version_update_screen.dart';
import 'archived_data_screen.dart';

class AdminStudentsScreen extends StatefulWidget {
  final Map<String, String> userInfo;
  final String role;
  const AdminStudentsScreen({Key? key, required this.userInfo, this.role = 'admin'}) : super(key: key);

  @override
  State<AdminStudentsScreen> createState() => _AdminStudentsScreenState();
}

class _AdminStudentsScreenState extends State<AdminStudentsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;
  bool _drawerOpen = false;
  bool _isOnline = true;
  bool _hasPendingSync = false;

  List<Widget> _getScreens() {
    return [
      StudentListScreen(role: widget.role, userInfo: widget.userInfo),
      TeacherListScreen(role: widget.role, userInfo: widget.userInfo),
      ClassListScreen(role: widget.role, userInfo: widget.userInfo),
      ScheduleListScreen(role: widget.role, userInfo: widget.userInfo),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _onAttendancePressed() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AttendanceScreen(userInfo: widget.userInfo)),
    );
  }

  void _checkForUpdates() async {
    try {
      final updateInfo = await VersionUpdateService().forceCheckForUpdate();
      if (updateInfo != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VersionUpdateScreen(
              updateInfo: updateInfo,
              onSkip: () => Navigator.pop(context),
              onContinue: () => Navigator.pop(context),
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Tidak ada pembaruan tersedia'),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  // void _debugVersionCheck() async {
  //   try {
  //     // Clear all version data first
  //     await VersionUpdateService().clearAllVersionData();
  //
  //     // Force check ignoring skip
  //     final updateInfo = await VersionUpdateService().forceCheckForUpdateIgnoreSkip();
  //
  //     if (mounted) {
  //       if (updateInfo != null) {
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           SnackBar(
  //             content: Text('Update ditemukan: ${updateInfo.latestVersion}'),
  //             backgroundColor: Colors.green.shade600,
  //             behavior: SnackBarBehavior.floating,
  //             shape: RoundedRectangleBorder(
  //               borderRadius: BorderRadius.circular(10),
  //             ),
  //           ),
  //         );
  //
  //         // Show the update screen
  //         Navigator.push(
  //           context,
  //           MaterialPageRoute(
  //             builder: (context) => VersionUpdateScreen(
  //               updateInfo: updateInfo,
  //               onSkip: () => Navigator.pop(context),
  //               onContinue: () => Navigator.pop(context),
  //             ),
  //           ),
  //         );
  //       } else {
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           SnackBar(
  //             content: const Text('Tidak ada update yang ditemukan (debug)'),
  //             backgroundColor: Colors.orange.shade600,
  //             behavior: SnackBarBehavior.floating,
  //             shape: RoundedRectangleBorder(
  //               borderRadius: BorderRadius.circular(10),
  //             ),
  //           ),
  //         );
  //       }
  //     }
  //   } catch (e) {
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('Debug Error: $e'),
  //           backgroundColor: Colors.red.shade600,
  //           behavior: SnackBarBehavior.floating,
  //           shape: RoundedRectangleBorder(
  //             borderRadius: BorderRadius.circular(10),
  //           ),
  //         ),
  //       );
  //     }
  //   }
  // }

  void _logout() async {
    await LocalStorageService.clearUserData();

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    _initializeConnectivity();
    _checkPendingSync();
  }

  void _initializeConnectivity() {
    final connectivityService = ConnectivityService();
    connectivityService.connectionStatus.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
        
        // Sync pending data when connection is restored
        if (isOnline) {
          OfflineSyncService.syncPendingAttendance();
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshConnectivityStatus();
  }

  Future<void> _refreshConnectivityStatus() async {
    final connectivityService = ConnectivityService();
    final isOnline = await connectivityService.checkConnectivity();
    if (mounted) {
      setState(() {
        _isOnline = isOnline;
      });
    }
  }

  void _checkPendingSync() async {
    final pendingAttendance = await LocalStorageService.getPendingAttendance();
    setState(() {
      _hasPendingSync = pendingAttendance.isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            title: Text('Dashboard ${widget.role == 'admin' ? 'Admin' : 'Guru'}'),
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            actions: [
              // Sync status indicator
              Container(
                margin: const EdgeInsets.only(right: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isOnline ? Icons.wifi : Icons.wifi_off,
                      color: _isOnline ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    if (_hasPendingSync && !_isOnline)
                      Container(
                        margin: const EdgeInsets.only(left: 4),
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.sync,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          drawer: Drawer(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                UserAccountsDrawerHeader(
                  accountName: Text(
                    widget.userInfo['name'] ?? '-',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  accountEmail: Text('NUPTK: ${widget.userInfo['nuptk'] ?? '-'}'),
                  currentAccountPicture: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: Text(
                      widget.userInfo['name']?.substring(0, 1).toUpperCase() ?? 'A',
                      style: const TextStyle(fontSize: 40, color: Colors.teal),
                    ),
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.teal,
                  ),
                ),
                if (widget.role == 'admin')
                  ListTile(
                    leading: const Icon(Icons.upgrade, color: Colors.green),
                    title: const Text('Naik Kelas'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PromotionScreen(
                            userInfo: widget.userInfo,
                            role: widget.role,
                          ),
                        ),
                      );
                    },
                  ),
                if (widget.role == 'admin')
                  ListTile(
                    leading: const Icon(Icons.archive, color: Colors.brown),
                    title: const Text('Data Arsip'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ArchivedDataScreen(
                            userInfo: widget.userInfo,
                          ),
                        ),
                      );
                    },
                  ),
                if (widget.role == 'admin')
                  ListTile(
                    leading: const Icon(Icons.bar_chart, color: Colors.deepPurple),
                    title: const Text('Laporan'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AttendanceReportScreen(
                        userInfo: widget.userInfo,
                        role: widget.role,
                      ),
                        ),
                      );
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.history, color: Colors.deepOrange),
                  title: const Text('Riwayat Presensi'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AttendanceHistoryScreen(
                          userInfo: widget.userInfo,
                          role: widget.role,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.sync, color: Colors.blue),
                  title: const Text('Status Sinkronisasi'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SyncStatusScreen(),
                      ),
                    );
                  },
                ),
                if (widget.role == 'admin')
                  ListTile(
                    leading: const Icon(Icons.system_update_alt, color: Colors.indigo),
                    title: const Text('Manajemen Versi'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => VersionManagementScreen(
                            userInfo: widget.userInfo,
                          ),
                        ),
                      );
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.update, color: Colors.orange),
                  title: const Text('Cek Pembaruan'),
                  onTap: () {
                    Navigator.pop(context);
                    _checkForUpdates();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.lock_reset, color: Colors.indigo),
                  title: const Text('Ubah Password'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChangePasswordScreen(
                          userInfo: widget.userInfo,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.blueGrey),
                  title: const Text('Keluar'),
                  onTap: _logout,
                ),
              ],
            ),
          ),
          body: _getScreens()[_selectedIndex],
          bottomNavigationBar: BottomNavigationBar(
            items: <BottomNavigationBarItem>[
              const BottomNavigationBarItem(
                icon: Icon(Icons.people),
                label: 'Siswa',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: 'Guru',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.class_),
                label: 'Kelas',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.schedule),
                label: 'Jadwal',
              ),
            ],
            currentIndex: _selectedIndex,
            onTap: _onItemTapped,
            selectedItemColor: Colors.blue,
            unselectedItemColor: Colors.grey,
            backgroundColor: Colors.white,
            type: BottomNavigationBarType.fixed,
          ),
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(bottom: 24.0),
            child: FloatingActionButton(
              onPressed: _onAttendancePressed,
              backgroundColor: Colors.orange,
              elevation: 8,
              shape: const CircleBorder(),
              child: const Icon(Icons.fingerprint, size: 36, color: Colors.white),
              tooltip: 'Presensi',
            ),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
          onDrawerChanged: (isOpen) {
            setState(() {
              _drawerOpen = isOpen;
            });
          },
        ),
        // Arrow sidebar indicator
        if (!_drawerOpen)
          Positioned(
            top: MediaQuery.of(context).size.height / 2 - 32,
            left: 0,
            child: GestureDetector(
              onTap: () {
                _scaffoldKey.currentState?.openDrawer();
                setState(() {
                  _drawerOpen = true;
                });
              },
              child: Material(
                elevation: 6,
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(24)),
                color: Colors.transparent,
                child: Container(
                  width: 40,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Colors.teal,
                    borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
                  ),
                  child: const Center(
                    child: Icon(Icons.arrow_forward_ios, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class DrawerControllerNotification extends Notification {
  final bool isDrawerOpen;
  DrawerControllerNotification(this.isDrawerOpen);
}



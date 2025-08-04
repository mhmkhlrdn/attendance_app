
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
import '../services/local_storage_service.dart';
import '../services/connectivity_service.dart';
import '../services/offline_sync_service.dart';
import 'sync_status_screen.dart';

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

  void _logout() async {
    // Clear local storage
    await LocalStorageService.clearUserData();
    
    // Navigate to login screen
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  void _onDrawerChanged(bool isOpen) {
    setState(() {
      _drawerOpen = isOpen;
    });
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
    // Refresh connectivity status when screen becomes active
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
                    title: const Text('Promosi Siswa'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PromotionScreen(),
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
                ListTile(
                  leading: const Icon(Icons.storage, color: Colors.purple),
                  title: const Text('Migrasi Data'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DataMigrationScreen(),
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



// Tambahkan DrawerControllerNotification agar bisa mendeteksi drawer open/close
class DrawerControllerNotification extends Notification {
  final bool isDrawerOpen;
  DrawerControllerNotification(this.isDrawerOpen);
}



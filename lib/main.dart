import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/admin_students_screen.dart';
import 'screens/login_screen.dart';
import 'services/local_storage_service.dart';
import 'services/connectivity_service.dart';
import 'services/offline_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Initialize connectivity service
  await ConnectivityService().initialize();
  
  // Initialize offline sync monitoring
  OfflineSyncService.initializeSyncMonitoring();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attendance App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _isLoggedIn = false;
  Map<String, String>? _userInfo;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    try {
      final isLoggedIn = await LocalStorageService.isLoggedIn();
      if (isLoggedIn) {
        final userInfo = await LocalStorageService.getUserInfo();
        if (userInfo != null) {
          setState(() {
            _isLoggedIn = true;
            _userInfo = userInfo;
          });
          
          // Sync teacher data in background
          OfflineSyncService.syncTeacherData(userInfo['nuptk'] ?? '');
        }
      }
    } catch (e) {
      print('Error checking login status: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_isLoggedIn && _userInfo != null) {
      return AdminStudentsScreen(
        userInfo: _userInfo!,
        role: _userInfo!['role'] ?? 'guru',
      );
    }

    return const LoginScreen();
  }
}

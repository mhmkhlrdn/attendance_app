import 'package:flutter/material.dart';
import 'dart:async';
import '../services/local_storage_service.dart';
import '../services/connectivity_service.dart';
import '../services/offline_sync_service.dart';
import '../services/version_update_service.dart';
import 'admin_students_screen.dart';
import 'login_screen.dart';
import 'version_update_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  
  bool _isLoading = true;
  bool _isLoggedIn = false;
  Map<String, String>? _userInfo;
  String _loadingText = 'Memulai aplikasi...';
  int _loadingStep = 0;
  VersionUpdateInfo? _updateInfo;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startLoadingSequence();
  }

  void _initializeAnimations() {
    _logoController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.elasticOut,
    ));
  }

  void _startLoadingSequence() async {
    // Start animations
    _fadeController.forward();
    
    // Start logo rotation after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _logoController.repeat();
      }
    });

    // Simulate loading steps
    await _simulateLoadingSteps();
    
    // Check for updates
    await _checkForUpdates();
    
    // Check login status
    await _checkLoginStatus();
    
    // Navigate to appropriate screen
    _navigateToNextScreen();
  }

  Future<void> _simulateLoadingSteps() async {
    final steps = [
      'Memulai aplikasi...',
      'Menginisialisasi Firebase...',
      'Memeriksa koneksi internet...',
      'Memeriksa pembaruan...',
      'Memuat data pengguna...',
      'Menyiapkan sinkronisasi...',
      'Siap!',
    ];

    for (int i = 0; i < steps.length; i++) {
      await Future.delayed(Duration(milliseconds: 600 + (i * 150)));
      if (mounted) {
        setState(() {
          _loadingText = steps[i];
          _loadingStep = i;
        });
      }
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      final updateInfo = await VersionUpdateService().checkForUpdate();
      if (updateInfo != null) {
        setState(() {
          _updateInfo = updateInfo;
        });
      }
    } catch (e) {
      print('Error checking for updates: $e');
    }
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

  void _navigateToNextScreen() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        // If there's an update available, show update screen first
        if (_updateInfo != null) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) {
                return VersionUpdateScreen(
                  updateInfo: _updateInfo!,
                  onSkip: () => _navigateToMainScreen(),
                  onContinue: () => _navigateToMainScreen(),
                );
              },
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              transitionDuration: const Duration(milliseconds: 500),
            ),
          );
        } else {
          _navigateToMainScreen();
        }
      }
    });
  }

  void _navigateToMainScreen() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          if (_isLoggedIn && _userInfo != null) {
            return AdminStudentsScreen(
              userInfo: _userInfo!,
              role: _userInfo!['role'] ?? 'guru',
            );
          } else {
            return const LoginScreen();
          }
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _logoController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.teal.shade50,
              Colors.teal.shade100,
              Colors.teal.shade200,
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Background decorative elements
              Positioned(
                top: -50,
                right: -50,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.teal.shade100.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                bottom: -30,
                left: -30,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.teal.shade200.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              
              // Main content
              Column(
                children: [
                  // Top section with logo and animations
                  Expanded(
                    flex: 3,
                    child: Center(
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: ScaleTransition(
                          scale: _scaleAnimation,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // App Logo/Icon with shadow
                              AnimatedBuilder(
                                animation: _logoController,
                                builder: (context, child) {
                                  return Transform.scale(
                                    scale: 1.0 + (0.1 * _logoController.value),
                                    child: Container(
                                      width: 120,
                                      height: 120,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(30),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.teal.withOpacity(0.3),
                                            blurRadius: 20,
                                            offset: const Offset(0, 10),
                                          ),
                                        ],
                                      ),
                                      child: RotationTransition(
                                        turns: _logoController,
                                        child: Icon(
                                          Icons.school,
                                          size: 60,
                                          color: Colors.teal.shade600,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 30),
                              
                              // App Name with gradient text
                              ShaderMask(
                                shaderCallback: (bounds) => LinearGradient(
                                  colors: [
                                    Colors.teal.shade700,
                                    Colors.teal.shade500,
                                  ],
                                ).createShader(bounds),
                                child: Text(
                                  'SADESA',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              
                              // App Tagline
                              Text(
                                'Sistem Absensi Digital Siswa Tanjungkarang',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.teal.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              
                              // Version info
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.teal.shade100.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Versi 1.0.5',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.teal.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  // Bottom section with loading indicator
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.all(30),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Loading text with animation
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: Text(
                              _loadingText,
                              key: ValueKey(_loadingText),
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.teal.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 20),
                          
                          // Progress indicator with animation
                          SizedBox(
                            width: 200,
                            child: TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 500),
                              tween: Tween(begin: 0.0, end: (_loadingStep + 1) / 7),
                              builder: (context, value, child) {
                                return LinearProgressIndicator(
                                  value: value,
                                  backgroundColor: Colors.teal.shade200,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.teal.shade600,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 20),
                          
                          // Loading dots animation
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(3, (index) {
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _loadingStep >= index 
                                    ? Colors.teal.shade600 
                                    : Colors.teal.shade300,
                                  shape: BoxShape.circle,
                                ),
                              );
                            }),
                          ),
                          
                          // Copyright text
                          const SizedBox(height: 30),
                          Text(
                            'KKN LP3I Tasik 2025',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.teal.shade500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
} 
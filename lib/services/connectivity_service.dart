import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamController<bool> _connectionStatusController = StreamController<bool>.broadcast();

  Stream<bool> get connectionStatus => _connectionStatusController.stream;
  bool _isConnected = true;

  /// Initialize connectivity monitoring
  Future<void> initialize() async {
    // Check initial connectivity status
    final result = await _connectivity.checkConnectivity();
    _isConnected = result != ConnectivityResult.none;
    _connectionStatusController.add(_isConnected);

    // Listen to connectivity changes
    _connectivity.onConnectivityChanged.listen((ConnectivityResult result) {
      final wasConnected = _isConnected;
      _isConnected = result != ConnectivityResult.none;
      
      // Only emit if status actually changed
      if (wasConnected != _isConnected) {
        _connectionStatusController.add(_isConnected);
      }
    });
  }

  /// Check if currently connected
  bool get isConnected => _isConnected;

  /// Check connectivity status
  Future<bool> checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    _isConnected = result != ConnectivityResult.none;
    return _isConnected;
  }

  /// Dispose resources
  void dispose() {
    _connectionStatusController.close();
  }
} 
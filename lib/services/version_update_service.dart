import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

class VersionUpdateService {
  static const String _lastCheckKey = 'last_version_check';
  static const String _skipVersionKey = 'skip_version';
  static final VersionUpdateService _instance = VersionUpdateService._internal();
  factory VersionUpdateService() => _instance;
  VersionUpdateService._internal();

  PackageInfo? _packageInfo;

  Future<void> initialize() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }

  /// Check if there's a new version available (from GitHub releases)
  Future<VersionUpdateInfo?> checkForUpdate({bool forceCheck = false}) async {
    try {
      if (_packageInfo == null) {
        await initialize();
      }

      // Check if we should skip this check (to avoid too frequent checks)
      if (!forceCheck && !await _shouldCheckForUpdate()) {
        return null;
      }

      // Fetch latest release from GitHub
      final release = await _fetchLatestGitHubRelease();
      if (release == null) return null;

      final latestVersion = release['tag_name'] ?? release['name'];
      final releaseNotes = release['body'] ?? '';
      final assets = release['assets'] as List<dynamic>;
      final downloadUrl = assets.isNotEmpty ? assets.first['browser_download_url'] : null;
      final isForceUpdate = false; // You can set this based on release data or tag naming
      final releaseDate = release['published_at'] != null ? DateTime.tryParse(release['published_at']) : null;

      final packageInfo = _packageInfo!;
      final currentVersion = packageInfo.version;
      final currentBuildNumber = packageInfo.buildNumber;

      // Check if user has skipped this version
      final skipVersion = await _getSkipVersion();
      if (skipVersion == latestVersion) {
        return null;
      }

      if (_isNewerVersion(latestVersion, currentVersion)) {
        return VersionUpdateInfo(
          currentVersion: currentVersion,
          currentBuildNumber: currentBuildNumber,
          latestVersion: latestVersion,
          latestBuildNumber: '',
          updateUrl: downloadUrl,
          isForceUpdate: isForceUpdate,
          releaseNotes: releaseNotes,
          releaseDate: releaseDate,
          bugFixes: [],
          newFeatures: [],
        );
      }

      await _updateLastCheckTime();
      return null;
    } catch (e) {
      print('Error checking for updates (GitHub): $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchLatestGitHubRelease() async {
    final url = 'https://mhmkhlrdn.github.io/attendance_app/releases/SADESA_1_0_6.apk';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    return null;
  }

  bool _isNewerVersion(String latest, String current) {
    final l = latest.replaceAll(RegExp(r'[^0-9.]'), '').split('.').map(int.parse).toList();
    final c = current.replaceAll(RegExp(r'[^0-9.]'), '').split('.').map(int.parse).toList();
    for (int i = 0; i < l.length; i++) {
      if (i >= c.length || l[i] > c[i]) return true;
      if (l[i] < c[i]) return false;
    }
    return false;
  }

  Future<bool> _shouldCheckForUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getInt(_lastCheckKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    const checkInterval = 24 * 60 * 60 * 1000; // 24 hours in milliseconds
    return (now - lastCheck) > checkInterval;
  }

  Future<void> _updateLastCheckTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<String?> _getSkipVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_skipVersionKey);
  }

  Future<void> skipVersion(String versionName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skipVersionKey, versionName);
  }

  Future<bool> launchDownloadUrl(String url) async {
    try {
      final uri = Uri.parse(url);

      // Force launch without checking canLaunchUrl, because GitHub links can fail the check
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      print('Error launching download URL: $e');
      return false;
    }
  }



  Future<Map<String, String>> getCurrentVersionInfo() async {
    if (_packageInfo == null) {
      await initialize();
    }
    return {
      'version': _packageInfo!.version,
      'buildNumber': _packageInfo!.buildNumber,
      'packageName': _packageInfo!.packageName,
      'appName': _packageInfo!.appName,
    };
  }

  Future<VersionUpdateInfo?> forceCheckForUpdate() async {
    return await checkForUpdate(forceCheck: true);
  }

  Future<void> clearSkipVersion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_skipVersionKey);
  }
}

class VersionUpdateInfo {
  final String currentVersion;
  final String currentBuildNumber;
  final String latestVersion;
  final String latestBuildNumber;
  final String? updateUrl;
  final bool isForceUpdate;
  final String releaseNotes;
  final DateTime? releaseDate;
  final List<String> bugFixes;
  final List<String> newFeatures;

  VersionUpdateInfo({
    required this.currentVersion,
    required this.currentBuildNumber,
    required this.latestVersion,
    required this.latestBuildNumber,
    this.updateUrl,
    required this.isForceUpdate,
    required this.releaseNotes,
    this.releaseDate,
    required this.bugFixes,
    required this.newFeatures,
  });

  String get versionString => '$latestVersion';
  String get currentVersionString => 'v$currentVersion';
  bool get isMajorUpdate {
    final current = currentVersion.split('.');
    final latest = latestVersion.split('.');
    if (current.length >= 1 && latest.length >= 1) {
      return int.parse(latest[0]) > int.parse(current[0]);
    }
    return false;
  }
  String get formattedReleaseDate {
    if (releaseDate == null) return '';
    return '${releaseDate!.day}/${releaseDate!.month}/${releaseDate!.year}';
  }
} 
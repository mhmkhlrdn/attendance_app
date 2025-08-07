import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/version_update_service.dart';
import 'dart:async';

class VersionManagementScreen extends StatefulWidget {
  final Map<String, String> userInfo;

  const VersionManagementScreen({
    Key? key,
    required this.userInfo,
  }) : super(key: key);

  @override
  State<VersionManagementScreen> createState() => _VersionManagementScreenState();
}

class _VersionManagementScreenState extends State<VersionManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _versionController = TextEditingController();
  final _versionCodeController = TextEditingController();
  final _downloadUrlController = TextEditingController();
  final _releaseNotesController = TextEditingController();
  final _bugFixesController = TextEditingController();
  final _newFeaturesController = TextEditingController();
  
  bool _isForceUpdate = false;
  bool _isLoading = false;
  List<Map<String, dynamic>> _versions = [];
  Map<String, String>? _currentVersionInfo;

  @override
  void initState() {
    super.initState();
    _loadCurrentVersionInfo();
    _loadVersions();
  }

  @override
  void dispose() {
    _versionController.dispose();
    _versionCodeController.dispose();
    _downloadUrlController.dispose();
    _releaseNotesController.dispose();
    _bugFixesController.dispose();
    _newFeaturesController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentVersionInfo() async {
    try {
      final versionInfo = await VersionUpdateService().getCurrentVersionInfo();
      setState(() {
        _currentVersionInfo = versionInfo;
      });
    } catch (e) {
      print('Error loading current version info: $e');
    }
  }

  Future<void> _loadVersions() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('app_versions')
          .orderBy('version_code', descending: true)
          .get();

      setState(() {
        _versions = querySnapshot.docs
            .map((doc) => {
                  'id': doc.id,
                  ...doc.data(),
                })
            .toList();
      });
    } catch (e) {
      print('Error loading versions: $e');
      _showErrorSnackBar('Gagal memuat daftar versi: $e');
    }
  }

  Future<void> _addVersion() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final versionData = {
        'version_name': _versionController.text.trim(),
        'version_code': int.parse(_versionCodeController.text.trim()),
        'download_url': _downloadUrlController.text.trim(),
        'release_notes': _releaseNotesController.text.trim(),
        'force_update': _isForceUpdate,
        'release_date': Timestamp.now(),
        'bug_fixes': _bugFixesController.text.trim().split('\n')
            .where((line) => line.trim().isNotEmpty)
            .toList(),
        'new_features': _newFeaturesController.text.trim().split('\n')
            .where((line) => line.trim().isNotEmpty)
            .toList(),
        'created_by': widget.userInfo['nuptk'] ?? 'admin',
        'created_at': Timestamp.now(),
      };

      await FirebaseFirestore.instance
          .collection('app_versions')
          .add(versionData);

      _showSuccessSnackBar('Versi berhasil ditambahkan!');
      _clearForm();
      _loadVersions();
    } catch (e) {
      print('Error adding version: $e');
      _showErrorSnackBar('Gagal menambahkan versi: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteVersion(String versionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Hapus'),
        content: const Text('Apakah Anda yakin ingin menghapus versi ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('app_versions')
          .doc(versionId)
          .delete();

      _showSuccessSnackBar('Versi berhasil dihapus!');
      _loadVersions();
    } catch (e) {
      print('Error deleting version: $e');
      _showErrorSnackBar('Gagal menghapus versi: $e');
    }
  }

  void _clearForm() {
    _formKey.currentState?.reset();
    _versionController.clear();
    _versionCodeController.clear();
    _downloadUrlController.clear();
    _releaseNotesController.clear();
    _bugFixesController.clear();
    _newFeaturesController.clear();
    setState(() {
      _isForceUpdate = false;
    });
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen Versi'),
        backgroundColor: Colors.teal.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.teal.shade50,
              Colors.teal.shade100,
            ],
          ),
        ),
        child: Column(
          children: [
            // Current version info
            if (_currentVersionInfo != null) ...[
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.teal.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.teal.shade600,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Versi Saat Ini',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          Text(
                            'v${_currentVersionInfo!['version']} (${_currentVersionInfo!['buildNumber']})',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            // Add version form
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Form title
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.teal.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.add_circle_outline,
                                  color: Colors.teal.shade600,
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Tambah Versi Baru',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            
                            // Version name
                            TextFormField(
                              controller: _versionController,
                              decoration: InputDecoration(
                                labelText: 'Nama Versi (contoh: 1.0.1)',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                prefixIcon: const Icon(Icons.tag),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Nama versi harus diisi';
                                }
                                return null;
                              },
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Version code
                            TextFormField(
                              controller: _versionCodeController,
                              decoration: InputDecoration(
                                labelText: 'Kode Versi (contoh: 2)',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                prefixIcon: const Icon(Icons.code),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Kode versi harus diisi';
                                }
                                if (int.tryParse(value.trim()) == null) {
                                  return 'Kode versi harus berupa angka';
                                }
                                return null;
                              },
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Download URL
                            TextFormField(
                              controller: _downloadUrlController,
                              decoration: InputDecoration(
                                labelText: 'URL Download (opsional)',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                prefixIcon: const Icon(Icons.link),
                              ),
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Release notes
                            TextFormField(
                              controller: _releaseNotesController,
                              decoration: InputDecoration(
                                labelText: 'Catatan Rilis',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                prefixIcon: const Icon(Icons.description),
                              ),
                              maxLines: 3,
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Bug fixes
                            TextFormField(
                              controller: _bugFixesController,
                              decoration: InputDecoration(
                                labelText: 'Perbaikan Bug (satu per baris)',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                prefixIcon: const Icon(Icons.bug_report),
                              ),
                              maxLines: 3,
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // New features
                            TextFormField(
                              controller: _newFeaturesController,
                              decoration: InputDecoration(
                                labelText: 'Fitur Baru (satu per baris)',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                prefixIcon: const Icon(Icons.star),
                              ),
                              maxLines: 3,
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Force update checkbox
                            CheckboxListTile(
                              title: const Text('Pembaruan Wajib'),
                              subtitle: const Text('User tidak bisa melewati pembaruan ini'),
                              value: _isForceUpdate,
                              onChanged: (value) {
                                setState(() {
                                  _isForceUpdate = value ?? false;
                                });
                              },
                              controlAffinity: ListTileControlAffinity.leading,
                              activeColor: Colors.teal.shade600,
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Submit button
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _addVersion,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal.shade600,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                        ),
                                      )
                                    : const Text(
                                        'Tambah Versi',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Versions list
                      Text(
                        'Daftar Versi',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal.shade700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      ..._versions.map((version) => _buildVersionCard(version)).toList(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionCard(Map<String, dynamic> version) {
    final isLatest = _versions.indexOf(version) == 0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ExpansionTile(
        title: Row(
          children: [
            Text(
              'v${version['version_name']}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.teal.shade700,
              ),
            ),
            if (isLatest) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Terbaru',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Build: ${version['version_code']}'),
            if (version['force_update'] == true)
              Text(
                'Pembaruan Wajib',
                style: TextStyle(
                  color: Colors.orange.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () => _deleteVersion(version['id']),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (version['release_notes']?.isNotEmpty == true) ...[
                  _buildInfoSection('Catatan Rilis', version['release_notes']),
                  const SizedBox(height: 12),
                ],
                
                if (version['new_features']?.isNotEmpty == true) ...[
                  _buildListSection('Fitur Baru', version['new_features']),
                  const SizedBox(height: 12),
                ],
                
                if (version['bug_fixes']?.isNotEmpty == true) ...[
                  _buildListSection('Perbaikan Bug', version['bug_fixes']),
                  const SizedBox(height: 12),
                ],
                
                if (version['download_url']?.isNotEmpty == true) ...[
                  _buildInfoSection('URL Download', version['download_url']),
                  const SizedBox(height: 12),
                ],
                
                Text(
                  'Dibuat: ${(version['created_at'] as Timestamp).toDate().toString().substring(0, 19)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.teal.shade700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          content,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  Widget _buildListSection(String title, List<dynamic> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.teal.shade700,
          ),
        ),
        const SizedBox(height: 4),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 6),
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.teal.shade400,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.toString(),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
        )).toList(),
      ],
    );
  }
} 
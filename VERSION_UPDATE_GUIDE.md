# Panduan Fitur Pembaruan Versi

## Overview
Fitur pembaruan versi memungkinkan Anda untuk segera memperbaiki bug setelah rilis produksi didistribusikan. Sistem akan menampilkan notifikasi bahwa ada versi baru yang tersedia setelah membuka aplikasi.

## Fitur Utama

### 1. Pemeriksaan Otomatis
- Aplikasi akan memeriksa pembaruan secara otomatis saat startup
- Pemeriksaan dilakukan maksimal sekali per 24 jam untuk menghemat bandwidth
- Pemeriksaan manual tersedia melalui menu "Cek Pembaruan"

### 2. Tampilan Pembaruan yang Menarik
- UI modern dengan animasi yang smooth
- Informasi lengkap tentang pembaruan (versi, fitur baru, perbaikan bug)
- Perbandingan versi saat ini vs versi terbaru
- Opsi untuk melewati pembaruan (kecuali force update)

### 3. Manajemen Versi untuk Admin
- Panel admin untuk menambah versi baru
- Pengaturan force update untuk pembaruan wajib
- Riwayat semua versi yang pernah dirilis

## Cara Menggunakan

### Untuk Admin

#### 1. Menambah Versi Baru
1. Buka aplikasi sebagai admin
2. Buka drawer menu (hamburger menu)
3. Pilih "Manajemen Versi"
4. Isi form dengan informasi versi:
   - **Nama Versi**: Format semver (contoh: 1.0.1)
   - **Kode Versi**: Angka build (contoh: 2)
   - **URL Download**: Link untuk download APK (opsional)
   - **Catatan Rilis**: Deskripsi pembaruan
   - **Perbaikan Bug**: Daftar bug yang diperbaiki (satu per baris)
   - **Fitur Baru**: Daftar fitur baru (satu per baris)
   - **Pembaruan Wajib**: Centang jika user tidak boleh melewati pembaruan

#### 2. Contoh Data Versi
```json
{
  "version_name": "1.0.1",
  "version_code": 2,
  "download_url": "https://example.com/app-v1.0.1.apk",
  "release_notes": "Pembaruan untuk memperbaiki masalah sinkronisasi data",
  "force_update": false,
  "bug_fixes": [
    "Memperbaiki crash saat sinkronisasi offline",
    "Memperbaiki tampilan laporan yang tidak lengkap"
  ],
  "new_features": [
    "Menambahkan fitur export PDF",
    "Menambahkan notifikasi pembaruan"
  ]
}
```

### Untuk User

#### 1. Pemeriksaan Otomatis
- Pembaruan akan diperiksa otomatis saat membuka aplikasi
- Jika ada pembaruan, layar pembaruan akan muncul

#### 2. Pemeriksaan Manual
1. Buka drawer menu
2. Pilih "Cek Pembaruan"
3. Sistem akan memeriksa pembaruan terbaru

#### 3. Opsi Pembaruan
- **Update Sekarang**: Membuka halaman download
- **Lewati untuk saat ini**: Melewati pembaruan ini
- **Lanjutkan tanpa update**: Kembali ke aplikasi

## Struktur Database Firestore

### Collection: `app_versions`
```javascript
{
  "version_name": "string",        // Nama versi (contoh: "1.0.1")
  "version_code": number,          // Kode build (contoh: 2)
  "download_url": "string",        // URL download APK
  "release_notes": "string",       // Catatan rilis
  "force_update": boolean,         // Apakah pembaruan wajib
  "release_date": timestamp,       // Tanggal rilis
  "bug_fixes": ["string"],         // Array perbaikan bug
  "new_features": ["string"],      // Array fitur baru
  "created_by": "string",          // NUPTK admin yang membuat
  "created_at": timestamp          // Waktu pembuatan
}
```

## Konfigurasi

### 1. Update pubspec.yaml
Pastikan dependencies berikut sudah ditambahkan:
```yaml
dependencies:
  package_info_plus: ^8.0.2
  url_launcher: ^6.2.4
  http: ^1.1.2
```

### 2. Update Version Number
Untuk merilis versi baru, update di `pubspec.yaml`:
```yaml
version: 1.0.1+2  # Format: version_name+build_number
```

### 3. Firestore Rules
Pastikan rules Firestore mengizinkan akses ke collection `app_versions`:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /app_versions/{document} {
      allow read: if true;  // Semua user bisa baca
      allow write: if request.auth != null && 
                   get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }
  }
}
```

## Workflow Pembaruan

### 1. Bug Fix Workflow
1. **Deteksi Bug**: Bug ditemukan di versi produksi
2. **Perbaiki**: Perbaiki bug di development
3. **Test**: Test di environment staging
4. **Build**: Build APK baru dengan version code yang lebih tinggi
5. **Upload**: Upload APK ke server/CDN
6. **Tambah Versi**: Gunakan panel admin untuk menambah versi baru
7. **Distribusi**: User akan mendapat notifikasi saat membuka app

### 2. Force Update Workflow
1. **Identifikasi Masalah Kritis**: Bug yang mempengaruhi keamanan/fungsionalitas
2. **Set Force Update**: Centang "Pembaruan Wajib" saat menambah versi
3. **User Tidak Bisa Skip**: User harus update untuk melanjutkan menggunakan app

## Troubleshooting

### 1. Pembaruan Tidak Muncul
- Periksa koneksi internet
- Pastikan version code lebih tinggi dari versi saat ini
- Cek apakah user sudah skip versi tersebut

### 2. Error Saat Download
- Periksa URL download apakah valid
- Pastikan file APK tersedia di server
- Cek permission internet di AndroidManifest.xml

### 3. Force Update Tidak Berfungsi
- Pastikan field `force_update` diset ke `true`
- Restart aplikasi untuk memastikan perubahan terdeteksi

## Best Practices

### 1. Version Naming
- Gunakan semantic versioning (semver): MAJOR.MINOR.PATCH
- Contoh: 1.0.0, 1.0.1, 1.1.0, 2.0.0

### 2. Version Code
- Selalu increment version code untuk setiap rilis
- Version code harus lebih tinggi dari versi sebelumnya

### 3. Release Notes
- Tulis release notes yang jelas dan informatif
- Pisahkan bug fixes dan new features
- Gunakan bahasa yang mudah dipahami user

### 4. Testing
- Test fitur pembaruan di berbagai device
- Pastikan URL download berfungsi
- Test force update scenario

## Keamanan

### 1. Admin Access
- Hanya admin yang bisa menambah/edit versi
- Implementasi role-based access control

### 2. URL Validation
- Validasi URL download sebelum disimpan
- Gunakan HTTPS untuk download URL

### 3. Version Verification
- Verifikasi signature APK jika diperlukan
- Implementasi checksum verification

## Monitoring

### 1. Analytics
- Track berapa user yang update vs skip
- Monitor error rate saat download
- Track adoption rate per versi

### 2. Logs
- Log semua aktivitas pembaruan
- Monitor performance impact
- Track user feedback

## Support

Jika mengalami masalah dengan fitur pembaruan versi:
1. Periksa log aplikasi
2. Verifikasi konfigurasi Firestore
3. Test di device yang berbeda
4. Hubungi tim development 
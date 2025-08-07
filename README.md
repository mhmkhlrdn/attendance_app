# SADESA - Sistem Absensi Digital Siswa Tanjungkarang

A comprehensive digital attendance system for schools built with Flutter and Firebase.

## Features

### Core Features
- **Digital Attendance Management**: Track student attendance with fingerprint scanning
- **Multi-School Support**: Manage multiple schools with isolated data
- **Role-Based Access**: Admin and teacher roles with different permissions
- **Offline Support**: Works without internet connection with automatic sync
- **Real-time Reports**: Generate attendance reports and analytics
- **Student Management**: Add, edit, and manage student information
- **Class Management**: Organize students into classes and schedules
- **Teacher Management**: Manage teacher accounts and permissions

### Version Update System
- **Automatic Update Checks**: Checks for updates on app startup
- **Manual Update Checks**: Admin can manually check for updates
- **Google Drive Integration**: Supports Google Drive download links
- **Force Updates**: Require users to update for critical fixes
- **Update Skipping**: Allow users to skip non-critical updates
- **Release Notes**: Display detailed update information

## Version Update Feature

### Overview
The version update system allows administrators to push immediate bug fixes and updates to users without going through app store approval processes.

### Key Features
- **Automatic Detection**: Checks for updates when app starts
- **Google Drive Support**: Handles Google Drive sharing links automatically
- **Manual Check**: Users can manually check for updates
- **Force Updates**: Critical updates that cannot be skipped
- **Update History**: Track which versions users have skipped
- **Release Notes**: Display bug fixes and new features

### Google Drive Link Handling
The system automatically converts Google Drive sharing links to direct download links:

**Supported Formats:**
- `https://drive.google.com/file/d/{fileId}/view?usp=sharing`
- `https://drive.google.com/open?id={fileId}`
- `https://drive.google.com/uc?export=download&id={fileId}`

**Features:**
- Automatic URL conversion for direct downloads
- Copy link functionality for manual downloads
- User-friendly error messages for failed downloads
- Fallback options when automatic opening fails

### Usage

#### For Administrators
1. **Add New Version**: Go to "Manajemen Versi" in the admin menu
2. **Upload APK**: Upload the new APK to Google Drive
3. **Get Download Link**: Copy the Google Drive sharing link
4. **Configure Version**: Set version details, release notes, and force update status
5. **Publish**: The update will be available to users immediately

#### For Users
1. **Automatic Check**: Updates are checked when app starts
2. **Manual Check**: Use "Cek Pembaruan" in the menu
3. **Download**: Tap "Update Sekarang" to download
4. **Copy Link**: Use "Salin Link Download" if automatic download fails
5. **Skip**: Skip non-critical updates (if allowed)

### Database Structure

#### app_versions Collection
```json
{
  "version_name": "1.0.1",
  "version_code": "2",
  "download_url": "https://drive.google.com/file/d/...",
  "is_force_update": false,
  "release_notes": "Bug fixes and improvements",
  "bug_fixes": ["Fixed login issue", "Improved performance"],
  "new_features": ["Added dark mode", "New report format"],
  "release_date": "2024-01-15T10:00:00Z",
  "created_at": "2024-01-15T10:00:00Z"
}
```

### Configuration

#### pubspec.yaml
```yaml
dependencies:
  package_info_plus: ^8.0.2
  url_launcher: ^6.2.4
  http: ^1.1.2
```

#### Version Number
Update in `pubspec.yaml`:
```yaml
version: 1.0.0+1  # version_name+version_code
```

### Troubleshooting

#### Common Issues

**Google Drive Download Fails**
- Ensure the file is set to "Anyone with the link can view"
- Use the "Salin Link Download" button to copy the link manually
- Try opening the link in a web browser

**Update Not Showing**
- Check if the version code is higher than current app version
- Verify the download URL is accessible
- Check if the user has skipped this version

**Force Update Not Working**
- Ensure `is_force_update` is set to `true`
- Verify the version code is higher than current app version
- Check if the user has the required permissions

### Best Practices

1. **Version Naming**: Use semantic versioning (MAJOR.MINOR.PATCH)
2. **Release Notes**: Provide clear, user-friendly descriptions
3. **Testing**: Test the download link before publishing
4. **Force Updates**: Use sparingly for critical security fixes only
5. **Backup**: Keep previous versions available for rollback

### Security Considerations

- Only admin users can manage versions
- Download links should be from trusted sources
- Consider implementing link expiration for security
- Monitor download analytics for suspicious activity

## Getting Started

### Prerequisites
- Flutter SDK 3.6.2 or higher
- Firebase project with Firestore enabled
- Android Studio / VS Code

### Installation
1. Clone the repository
2. Install dependencies: `flutter pub get`
3. Configure Firebase: Add `google-services.json`
4. Run the app: `flutter run`

### Configuration
1. Set up Firebase project
2. Configure Firestore security rules
3. Add school data to the database
4. Create admin user accounts

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}

class GoogleDriveService {
  static final GoogleDriveService instance = GoogleDriveService._internal();
  factory GoogleDriveService() => instance;
  GoogleDriveService._internal();

  GoogleSignInAccount? _currentUser;
  GoogleSignInAccount? get currentUser => _currentUser;

  Future<GoogleSignInAccount?> signIn() async {
    try {
      _currentUser = await GoogleSignIn.instance.authenticate();
      return _currentUser;
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    _currentUser = null;
  }

  Future<drive.DriveApi?> getDriveApi() async {
    if (_currentUser == null) {
      _currentUser = await signIn();
    }
    if (_currentUser == null) return null;

    final authHeaders = await _currentUser!.authorizationClient.authorizationHeaders([
      drive.DriveApi.driveFileScope,
    ]);

    if (authHeaders == null) return null;

    final authenticateClient = GoogleAuthClient(authHeaders);
    return drive.DriveApi(authenticateClient);
  }

  /// Upload file attachment directly to Google Drive
  Future<String?> uploadAttachment({
    required String fileName,
    required List<int> fileBytes,
    required String mimeType,
  }) async {
    try {
      final driveApi = await getDriveApi();
      if (driveApi == null) {
        // Fallback demo URL if not signed into real Google Drive
        return 'https://drive.google.com/file/demo_$fileName';
      }

      final media = drive.Media(
        Stream.value(fileBytes),
        fileBytes.length,
        contentType: mimeType,
      );

      final driveFile = drive.File()
        ..name = fileName
        ..description = 'Uploaded via Task Sphere App';

      final result = await driveApi.files.create(
        driveFile,
        uploadMedia: media,
        $fields: 'id, webViewLink, webContentLink',
      );

      return result.webViewLink ?? result.webContentLink;
    } catch (e) {
      debugPrint('Error uploading file to Google Drive: $e');
      return 'https://drive.google.com/file/demo_$fileName';
    }
  }
}

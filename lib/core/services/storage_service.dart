import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Uploads and serves task attachments from the private Supabase Storage
/// bucket `task-attachments`. Files are stored at
/// `{workspace_id}/{task_id}/{timestamp}_{filename}` and access is governed
/// by RLS policies on storage.objects.
class SupabaseStorageService {
  static final SupabaseStorageService instance = SupabaseStorageService._internal();
  factory SupabaseStorageService() => instance;
  SupabaseStorageService._internal();

  static const bucketName = 'task-attachments';

  bool get isAvailable => SupabaseService.instance.client != null;

  SupabaseClient? get _client => SupabaseService.instance.client;

  /// Returns the storage path on success, or null when unavailable/failed.
  Future<String?> uploadAttachment({
    required String workspaceId,
    required String taskId,
    required String fileName,
    required Uint8List fileBytes,
    required String mimeType,
  }) async {
    final client = _client;
    if (client == null) return null;
    try {
      final path =
          '$workspaceId/$taskId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
      await client.storage.from(bucketName).uploadBinary(
            path,
            fileBytes,
            fileOptions: FileOptions(contentType: mimeType),
          );
      return path;
    } catch (e) {
      debugPrint('Attachment upload error: $e');
      return null;
    }
  }

  /// Generates a short-lived signed URL for an attachment path.
  Future<String?> createSignedUrl(String path) async {
    final client = _client;
    if (client == null) return null;
    try {
      return await client.storage.from(bucketName).createSignedUrl(path, 3600);
    } catch (e) {
      debugPrint('Signed URL error: $e');
      return null;
    }
  }

  Future<void> deleteAttachment(String path) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.storage.from(bucketName).remove([path]);
    } catch (e) {
      debugPrint('Attachment delete error: $e');
    }
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_sphere/core/services/storage_service.dart';

void main() {
  group('sanitizeFileName', () {
    test('replaces spaces with underscores (macOS screenshot names)', () {
      expect(
        SupabaseStorageService.sanitizeFileName(
          'Screenshot 2026-08-31 at 12.01.26 AM.png',
        ),
        'Screenshot_2026-08-31_at_12.01.26_AM.png',
      );
    });

    test('keeps letters, digits, dots, underscores and dashes', () {
      expect(
        SupabaseStorageService.sanitizeFileName('my_report_v2.final.docx'),
        'my_report_v2.final.docx',
      );
    });

    test('replaces unsafe characters like slashes, colons and hashes', () {
      expect(
        SupabaseStorageService.sanitizeFileName('a/b:c?d#e%.png'),
        'a_b_c_d_e_.png',
      );
    });

    test('never returns an empty key', () {
      expect(SupabaseStorageService.sanitizeFileName('!!!'), isNotEmpty);
    });
  });

  test('uploadAttachment returns null when no Supabase client is available',
      () async {
    final path = await SupabaseStorageService.instance.uploadAttachment(
      workspaceId: 'w',
      taskId: 't',
      fileName: 'a b.png',
      fileBytes: Uint8List(0),
      mimeType: 'image/png',
    );
    expect(path, isNull);
  });
}

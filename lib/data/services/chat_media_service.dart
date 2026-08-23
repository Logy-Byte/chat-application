import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/chat_message.dart';
import '../../injection/locator.dart';
import '../../ui/core/controllers/preferences_controller.dart';
import 'encrypted_attachment_codec.dart';

class ChatMediaService {
  ChatMediaService({
    SupabaseClient? client,
    ChatyPreferencesController? preferences,
    EncryptedAttachmentCodec? codec,
  }) : _client = client ?? Supabase.instance.client,
       _preferences = preferences ?? locator<ChatyPreferencesController>(),
       _codec = codec ?? EncryptedAttachmentCodec();

  static const String bucket = 'chat-media';
  static const int storageLimitMb = 50;
  static const String encryptedContentType = 'application/octet-stream';

  final SupabaseClient _client;
  final ChatyPreferencesController _preferences;
  final EncryptedAttachmentCodec _codec;
  final Uuid _uuid = const Uuid();

  static final Map<String, Future<File>> _localFileCache =
      <String, Future<File>>{};

  Future<MessageAttachment?> pickAndUpload({
    required String conversationId,
    required String type,
  }) async {
    final picked = await FilePicker.pickFile(type: _pickerType(type));
    if (picked == null) return null;
    final sourcePath = picked.path;
    if (sourcePath == null || sourcePath.isEmpty) {
      throw Exception('The selected file is not accessible on this device.');
    }
    return uploadFile(
      conversationId: conversationId,
      type: type,
      sourcePath: sourcePath,
      displayName: picked.name,
    );
  }

  Future<List<MessageAttachment>> pickAndUploadMultiple({
    required String conversationId,
    required String type,
  }) async {
    final limit = _preferences
        .gbDouble('Img_share_limit', fallback: 30)
        .clamp(1, 100)
        .round();
    final picked = await FilePicker.pickFiles(
      type: _pickerType(type),
      allowMultiple: true,
    );
    if (picked.isEmpty) return <MessageAttachment>[];
    if (picked.length > limit) {
      throw Exception(
        'You selected ${picked.length} files; your configured send limit is $limit.',
      );
    }
    final result = <MessageAttachment>[];
    for (final item in picked) {
      final path = item.path;
      if (path == null || path.isEmpty) continue;
      result.add(
        await uploadFile(
          conversationId: conversationId,
          type: type,
          sourcePath: path,
          displayName: item.name,
        ),
      );
    }
    return result;
  }

  Future<MessageAttachment> uploadFile({
    required String conversationId,
    required String type,
    required String sourcePath,
    String? displayName,
    int durationSeconds = 0,
  }) async {
    var file = File(sourcePath);
    if (!await file.exists()) {
      throw Exception('The selected file no longer exists.');
    }
    var rawName = displayName ?? sourcePath.split(Platform.pathSeparator).last;
    var mimeType = lookupMimeType(sourcePath) ?? _fallbackMimeForType(type);
    File? generatedSource;

    if (type == 'image' && mimeType != 'image/gif') {
      final quality = _preferences
          .gbDouble('Img_highres_seek', fallback: 85)
          .clamp(10, 100)
          .round();
      if (quality < 100) {
        try {
          final temp = await getTemporaryDirectory();
          final targetPath = '${temp.path}/chaty_${_uuid.v4()}.jpg';
          final compressed = await FlutterImageCompress.compressAndGetFile(
            file.absolute.path,
            targetPath,
            quality: quality,
            minWidth: 2560,
            minHeight: 2560,
            keepExif: false,
          );
          if (compressed != null) {
            final candidate = File(compressed.path);
            if (await candidate.exists() && await candidate.length() > 0) {
              file = candidate;
              generatedSource = candidate;
              final dot = rawName.lastIndexOf('.');
              rawName = '${dot > 0 ? rawName.substring(0, dot) : rawName}.jpg';
              mimeType = 'image/jpeg';
            }
          }
        } catch (_) {}
      }
    }

    final size = await file.length();
    if (size <= 0) throw Exception('The selected file is empty.');
    final maxBytes = _maxBytes(type);
    if (size > maxBytes) {
      await _deleteQuietly(generatedSource);
      final limitMb = (maxBytes / (1024 * 1024)).round();
      throw Exception('This $type exceeds the $limitMb MB storage limit.');
    }

    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      await _deleteQuietly(generatedSource);
      throw Exception('Authentication required.');
    }

    final attachmentId = _uuid.v4();
    final temp = await getTemporaryDirectory();
    final encryptedFile = File(
      '${temp.path}/chaty_encrypted_${_uuid.v4()}.bin',
    );
    final objectPath = '${authUser.id}/$conversationId/${_uuid.v4()}.bin';

    try {
      final crypto = await _codec.encryptFile(
        source: file,
        destination: encryptedFile,
        conversationId: conversationId,
        attachmentId: attachmentId,
        originalMimeType: mimeType,
        originalFileName: rawName,
      );

      await _client.storage
          .from(bucket)
          .upload(
            objectPath,
            encryptedFile,
            fileOptions: const FileOptions(
              cacheControl: 'private, no-store',
              upsert: false,
              contentType: encryptedContentType,
            ),
          );

      return MessageAttachment(
        id: attachmentId,
        type: type,
        name: rawName,
        size: _formatBytes(size),
        url: objectPath,
        durationSeconds: durationSeconds,
        encryptionVersion: EncryptedAttachmentCodec.version,
        encryptionAlgorithm: EncryptedAttachmentCodec.algorithm,
        encryptionKeyBase64: crypto.keyBase64,
        encryptionNonceBase64: crypto.nonceBase64,
        encryptionMacBase64: crypto.macBase64,
        originalMimeType: crypto.originalMimeType,
        originalSizeBytes: crypto.originalSizeBytes,
      );
    } catch (error) {
      // If upload failed after encryption, make a best-effort cleanup of a
      // potentially created object. RLS allows only the sender to delete it.
      try {
        await _client.storage.from(bucket).remove(<String>[objectPath]);
      } catch (_) {}
      rethrow;
    } finally {
      await _deleteQuietly(encryptedFile);
      await _deleteQuietly(generatedSource);
    }
  }

  int _maxBytes(String type) {
    final configured = type == 'audio'
        ? _preferences.gbDouble(
            'abo_saleh_audio_limit_check',
            fallback: storageLimitMb.toDouble(),
          )
        : _preferences.gbDouble(
            'Up_size_limit',
            fallback: storageLimitMb.toDouble(),
          );
    final effectiveMb = configured.clamp(1, storageLimitMb).round();
    return effectiveMb * 1024 * 1024;
  }

  /// Resolves an attachment into a local cleartext temporary file.
  ///
  /// New attachments are downloaded as opaque ciphertext and authenticated
  /// before any consumer sees plaintext. Legacy unencrypted attachments are
  /// still downloaded for backward compatibility but are never labelled E2EE.
  Future<File> resolveToLocalFile({
    required String conversationId,
    required MessageAttachment attachment,
  }) {
    final path = attachment.url;
    if (path == null || path.trim().isEmpty) {
      throw Exception('Attachment path is missing.');
    }
    final cacheKey = attachment.isEncrypted
        ? '${attachment.id}:${attachment.encryptionMacBase64}'
        : 'legacy:${attachment.id}:$path';
    return _localFileCache.putIfAbsent(
      cacheKey,
      () => _downloadAndResolve(
        conversationId: conversationId,
        attachment: attachment,
      ),
    );
  }

  Future<File> _downloadAndResolve({
    required String conversationId,
    required MessageAttachment attachment,
  }) async {
    final objectPath = attachment.url!;
    final temp = await getTemporaryDirectory();
    final encryptedDownload = File(
      '${temp.path}/chaty_download_${_uuid.v4()}.bin',
    );
    final clearName = _safeFileName(attachment.name);
    final clearFile = File(
      '${temp.path}/chaty_clear_${attachment.id}_${_uuid.v4()}_$clearName',
    );

    try {
      await _downloadObjectToFile(objectPath, encryptedDownload);
      if (!attachment.isEncrypted) {
        await encryptedDownload.rename(clearFile.path);
        return clearFile;
      }
      return await _codec.decryptFile(
        source: encryptedDownload,
        destination: clearFile,
        conversationId: conversationId,
        attachment: attachment,
      );
    } catch (_) {
      await _deleteQuietly(clearFile);
      rethrow;
    } finally {
      await _deleteQuietly(encryptedDownload);
    }
  }

  Future<void> _downloadObjectToFile(String objectPath, File target) async {
    final signedUrl = await createSignedUrl(objectPath, expiresInSeconds: 120);
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(signedUrl));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw HttpException(
          'Attachment download failed with HTTP ${response.statusCode}.',
        );
      }
      await target.parent.create(recursive: true);
      await response.pipe(target.openWrite(mode: FileMode.writeOnly));
      if (!await target.exists() || await target.length() <= 0) {
        throw FileSystemException('Downloaded attachment is empty.');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<String> createSignedUrl(
    String objectPath, {
    int expiresInSeconds = 900,
  }) async {
    if (objectPath.trim().isEmpty) {
      throw Exception('Attachment path is missing.');
    }
    return _client.storage
        .from(bucket)
        .createSignedUrl(objectPath, expiresInSeconds);
  }

  Future<void> deleteOwnAttachment(String objectPath) async {
    if (objectPath.trim().isEmpty) return;
    await _client.storage.from(bucket).remove(<String>[objectPath]);
    _localFileCache.clear();
  }

  static FileType _pickerType(String type) {
    return switch (type) {
      'image' => FileType.image,
      'video' => FileType.video,
      'audio' => FileType.audio,
      _ => FileType.any,
    };
  }

  static String _safeFileName(String source) {
    final cleaned = source
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (cleaned.isEmpty) return 'attachment';
    return cleaned.length > 120
        ? cleaned.substring(cleaned.length - 120)
        : cleaned;
  }

  static String _fallbackMimeForType(String type) {
    return switch (type) {
      'image' => 'image/jpeg',
      'video' => 'video/mp4',
      'audio' => 'audio/mp4',
      _ => 'application/octet-stream',
    };
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  static Future<void> _deleteQuietly(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

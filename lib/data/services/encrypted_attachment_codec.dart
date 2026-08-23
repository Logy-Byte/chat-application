import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../../domain/models/chat_message.dart';

/// Streaming authenticated encryption for Chaty message attachments.
///
/// The file key is never uploaded to Supabase Storage. It is serialized only
/// into the MessageAttachment that is itself carried inside an MLS application
/// message. Storage therefore receives an opaque ciphertext blob.
class EncryptedAttachmentCodec {
  EncryptedAttachmentCodec({Xchacha20? cipher})
      : _cipher = cipher ?? Xchacha20.poly1305Aead();

  static const int version = 1;
  static const String algorithm = 'xchacha20-poly1305-stream-v1';

  final Xchacha20 _cipher;

  Future<AttachmentEncryptionResult> encryptFile({
    required File source,
    required File destination,
    required String conversationId,
    required String attachmentId,
    required String originalMimeType,
    required String originalFileName,
  }) async {
    if (!await source.exists()) {
      throw const AttachmentCryptoException('Attachment source does not exist.');
    }
    final clearSize = await source.length();
    if (clearSize <= 0) {
      throw const AttachmentCryptoException('Attachment source is empty.');
    }

    final secretKey = await _cipher.newSecretKey();
    final keyBytes = await secretKey.extractBytes();
    final nonce = _cipher.newNonce();
    final aad = _aad(conversationId, attachmentId);
    final macCompleter = Completer<Mac>();

    await destination.parent.create(recursive: true);
    final sink = destination.openWrite(mode: FileMode.writeOnly);
    try {
      final encrypted = _cipher.encryptStream(
        source.openRead(),
        secretKey: secretKey,
        nonce: nonce,
        aad: aad,
        onMac: (mac) {
          if (!macCompleter.isCompleted) macCompleter.complete(mac);
        },
      );
      await sink.addStream(encrypted);
      await sink.flush();
      await sink.close();
      final mac = await macCompleter.future;
      final cipherSize = await destination.length();
      if (cipherSize != clearSize) {
        await _deleteQuietly(destination);
        throw const AttachmentCryptoException(
          'Encrypted attachment length invariant failed.',
        );
      }
      return AttachmentEncryptionResult(
        keyBase64: base64Encode(keyBytes),
        nonceBase64: base64Encode(nonce),
        macBase64: base64Encode(mac.bytes),
        originalMimeType: originalMimeType,
        originalFileName: originalFileName,
        originalSizeBytes: clearSize,
        cipherSizeBytes: cipherSize,
      );
    } catch (error) {
      try {
        await sink.close();
      } catch (_) {}
      await _deleteQuietly(destination);
      if (error is AttachmentCryptoException) rethrow;
      throw AttachmentCryptoException('Attachment encryption failed: $error');
    }
  }

  Future<File> decryptFile({
    required File source,
    required File destination,
    required String conversationId,
    required MessageAttachment attachment,
  }) async {
    if (!attachment.isEncrypted) {
      throw const AttachmentCryptoException(
        'Attachment does not contain encrypted-file metadata.',
      );
    }
    if (attachment.encryptionAlgorithm != algorithm ||
        attachment.encryptionVersion != version) {
      throw AttachmentCryptoException(
        'Unsupported attachment cipher ${attachment.encryptionAlgorithm} '
        'v${attachment.encryptionVersion}.',
      );
    }
    if (!await source.exists()) {
      throw const AttachmentCryptoException('Encrypted attachment is missing.');
    }

    late final List<int> keyBytes;
    late final List<int> nonce;
    late final List<int> macBytes;
    try {
      keyBytes = base64Decode(attachment.encryptionKeyBase64!);
      nonce = base64Decode(attachment.encryptionNonceBase64!);
      macBytes = base64Decode(attachment.encryptionMacBase64!);
    } catch (_) {
      throw const AttachmentCryptoException(
        'Encrypted attachment metadata is malformed.',
      );
    }
    if (keyBytes.length != 32 || nonce.length != _cipher.nonceLength) {
      throw const AttachmentCryptoException(
        'Encrypted attachment key or nonce has an invalid length.',
      );
    }

    final secretKey = SecretKey(keyBytes);
    final aad = _aad(conversationId, attachment.id);
    await destination.parent.create(recursive: true);
    final sink = destination.openWrite(mode: FileMode.writeOnly);
    try {
      final clear = _cipher.decryptStream(
        source.openRead(),
        secretKey: secretKey,
        nonce: nonce,
        mac: Mac(macBytes),
        aad: aad,
      );
      await sink.addStream(clear);
      await sink.flush();
      await sink.close();
      final clearSize = await destination.length();
      final expectedSize = attachment.originalSizeBytes;
      if (expectedSize != null && clearSize != expectedSize) {
        await _deleteQuietly(destination);
        throw const AttachmentCryptoException(
          'Decrypted attachment size invariant failed.',
        );
      }
      return destination;
    } catch (error) {
      try {
        await sink.close();
      } catch (_) {}
      await _deleteQuietly(destination);
      if (error is AttachmentCryptoException) rethrow;
      throw AttachmentCryptoException(
        'Attachment authentication/decryption failed: $error',
      );
    }
  }

  List<int> _aad(String conversationId, String attachmentId) => utf8.encode(
        'chaty-attachment|v$version|conversation=$conversationId|attachment=$attachmentId',
      );

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

class AttachmentEncryptionResult {
  const AttachmentEncryptionResult({
    required this.keyBase64,
    required this.nonceBase64,
    required this.macBase64,
    required this.originalMimeType,
    required this.originalFileName,
    required this.originalSizeBytes,
    required this.cipherSizeBytes,
  });

  final String keyBase64;
  final String nonceBase64;
  final String macBase64;
  final String originalMimeType;
  final String originalFileName;
  final int originalSizeBytes;
  final int cipherSizeBytes;
}

class AttachmentCryptoException implements Exception {
  const AttachmentCryptoException(this.message);
  final String message;
  @override
  String toString() => message;
}

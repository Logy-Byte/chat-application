import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Owns registration/revocation of *real* platform push tokens.
///
/// This service deliberately never manufactures a token. FCM/APNs registration
/// identifiers are credentials issued by the platform provider and a random
/// UUID is not a substitute. Until the platform integration supplies a token,
/// Chaty remains unregistered for remote push delivery instead of persisting a
/// fake linked-device token to production.
class PushTokenService extends ChangeNotifier {
  static const String _pushTokenStorageKey = 'chaty.device_push_token.v1';
  static const String _registeredUserIdKey = 'chaty.registered_push_user_id.v1';

  final SupabaseClient _client;
  final FlutterSecureStorage _secureStorage;

  String? _currentToken;
  bool _isRegistered = false;

  PushTokenService({
    SupabaseClient? client,
    FlutterSecureStorage? secureStorage,
  }) : _client = client ?? Supabase.instance.client,
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  String? get currentToken => _currentToken;
  bool get isRegistered => _isRegistered;
  bool get hasPlatformToken => _currentToken?.isNotEmpty == true;

  String get platformName {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  /// Restores an already-issued provider token, if one exists.
  ///
  /// The native/FCM/APNs integration must call [registerPlatformToken] when it
  /// obtains a new token. Missing provider configuration therefore fails
  /// closed rather than creating a fake registration.
  Future<void> initialize() async {
    final session = _client.auth.currentSession;
    final token = await _secureStorage.read(key: _pushTokenStorageKey);
    _currentToken = token?.trim().isEmpty == true ? null : token?.trim();

    if (session == null || _currentToken == null) {
      _isRegistered = false;
      notifyListeners();
      return;
    }

    final registeredUser = await _secureStorage.read(
      key: _registeredUserIdKey,
    );
    if (registeredUser != session.user.id) {
      await registerToken(_currentToken!);
    } else {
      _isRegistered = true;
      notifyListeners();
    }
  }

  /// Entry point for a token issued by FCM/APNs or another real push provider.
  Future<void> registerPlatformToken(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(token, 'token', 'Platform token is empty.');
    }
    await registerToken(normalized);
  }

  Future<void> registerToken(String pushToken) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final normalized = pushToken.trim();
    if (normalized.isEmpty) return;

    _currentToken = normalized;
    await _secureStorage.write(
      key: _pushTokenStorageKey,
      value: normalized,
    );

    try {
      await _client.from('linked_devices').upsert(<String, dynamic>{
        'user_id': user.id,
        'device_id': normalized,
        'device_name': '$platformName Chaty Device',
        'platform': platformName,
        'location': '',
        'last_active_at': DateTime.now().toUtc().toIso8601String(),
        'revoked_at': null,
      }, onConflict: 'user_id,device_id');

      await _secureStorage.write(
        key: _registeredUserIdKey,
        value: user.id,
      );
      _isRegistered = true;
      notifyListeners();
    } catch (error, stackTrace) {
      _isRegistered = false;
      debugPrint(
        'PushTokenService: platform-token registration failed: '
        '$error\n$stackTrace',
      );
      notifyListeners();
      rethrow;
    }
  }

  Future<void> onTokenRefresh(String newToken) async {
    final normalized = newToken.trim();
    if (normalized.isEmpty || normalized == _currentToken) return;
    await registerPlatformToken(normalized);
  }

  /// Revokes the current device before authentication is torn down. This must
  /// run while `auth.uid()` is still available to the linked-device RLS policy.
  Future<void> revokeTokenOnLogout({bool clearProviderToken = false}) async {
    final user = _client.auth.currentUser;
    final token = _currentToken;

    if (user != null && token != null) {
      try {
        await _client
            .from('linked_devices')
            .update(<String, dynamic>{
              'revoked_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('user_id', user.id)
            .eq('device_id', token);
      } catch (error, stackTrace) {
        debugPrint(
          'PushTokenService: device revocation failed: $error\n$stackTrace',
        );
        rethrow;
      }
    }

    await _secureStorage.delete(key: _registeredUserIdKey);
    if (clearProviderToken) {
      await _secureStorage.delete(key: _pushTokenStorageKey);
      _currentToken = null;
    }
    _isRegistered = false;
    notifyListeners();
  }

  /// Used after account deletion/app reset. It does not claim to invalidate the
  /// provider-side token; it removes Chaty's local copy and registration owner.
  Future<void> clearLocalRegistration() async {
    await _secureStorage.delete(key: _registeredUserIdKey);
    await _secureStorage.delete(key: _pushTokenStorageKey);
    _currentToken = null;
    _isRegistered = false;
    notifyListeners();
  }
}

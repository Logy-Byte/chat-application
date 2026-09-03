import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

class FirebaseMessagingService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> initialize() async {
    // Request permissions for iOS
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted permission');
    } else {
      debugPrint('User declined or has not accepted permission');
    }

    // Set background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Foreground message handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');

      if (message.notification != null) {
        debugPrint('Message also contained a notification: ${message.notification}');
      }
    });

    // Handle token refresh
    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      debugPrint("FCM Token Refreshed: $newToken");
      _registerTokenWithBackend(newToken);
    });

    // Get initial token
    try {
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        debugPrint("Initial FCM Token: $token");
        await _registerTokenWithBackend(token);
      }
    } catch (e) {
      debugPrint("Failed to get FCM token: $e");
    }
  }

  Future<void> _registerTokenWithBackend(String token) async {
    try {
      String? authToken = await _storage.read(key: 'jwt_token'); // Guessing the key, might need to adjust
      if (authToken == null) {
        debugPrint("No auth token available, skipping FCM token registration.");
        return;
      }
      
      String apiUrl = dotenv.env['API_URL'] ?? 'https://api.test.saas.logybyte.in/api/v1';

      String deviceType = "unknown";
      if (kIsWeb) {
        deviceType = "web";
      } else if (Platform.isAndroid) {
        deviceType = "android";
      } else if (Platform.isIOS) {
        deviceType = "ios";
      }

      final response = await http.post(
        Uri.parse('$apiUrl/app-users/me/devices'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'fcm_token': token,
          'device_type': deviceType
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint("Successfully registered FCM token with backend.");
      } else {
        debugPrint("Failed to register FCM token: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      debugPrint("Error registering FCM token with backend: $e");
    }
  }
}

final firebaseMessagingService = FirebaseMessagingService();

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'backend_config.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/models/conversation.dart';
import '../../domain/models/chat_message.dart';

class ApiBackendService extends ChangeNotifier {
  static final ApiBackendService _instance = ApiBackendService._internal();
  factory ApiBackendService() => _instance;
  ApiBackendService._internal();

  bool _isInitialized = false;
  UserProfile? _currentUser;
  String? _token;
  WebSocketChannel? _channel;

  List<Conversation> _conversations = [];
  final Map<String, List<ChatMessage>> _messages = {};

  bool get isInitialized => _isInitialized;
  bool get isAuthenticated => _token != null && _currentUser != null;
  UserProfile? get currentUser => _currentUser;
  List<Conversation> get conversations => _conversations;

  List<ChatMessage> getMessages(String chatId) => _messages[chatId] ?? [];

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    notifyListeners();
  }

  Future<UserProfile> login({required String identifier, required String password}) async {
    final response = await http.post(
      Uri.parse('${ApiBackendConfig.restApiBaseUrl}/auth/token'),
      headers: {
        'Content-Type': 'application/json',
        'x-tenant-id': ApiBackendConfig.tenantId,
      },
      body: jsonEncode({'username': identifier, 'password': password}),
    );
    return _parseAuthResponse(response);
  }

  Future<UserProfile> register({required String email, required String username, required String password}) async {
    final response = await http.post(
      Uri.parse('${ApiBackendConfig.restApiBaseUrl}/auth/register'),
      headers: {
        'Content-Type': 'application/json',
        'x-tenant-id': ApiBackendConfig.tenantId,
      },
      body: jsonEncode({
        'email': email,
        'username': username,
        'password': password,
      }),
    );
    return _parseAuthResponse(response);
  }

  Future<UserProfile> oauthLogin({required String provider, required String token}) async {
    final response = await http.post(
      Uri.parse('${ApiBackendConfig.restApiBaseUrl}/auth/oauth'),
      headers: {
        'Content-Type': 'application/json',
        'x-tenant-id': ApiBackendConfig.tenantId,
      },
      body: jsonEncode({
        'provider': provider,
        'token': token,
      }),
    );
    return _parseAuthResponse(response);
  }

  UserProfile _parseAuthResponse(http.Response response) {
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body)['data'] ?? jsonDecode(response.body);
      _token = data['token'];
      _currentUser = UserProfile(
        id: data['user']['id'],
        displayName: data['user']['display_name'],
        username: data['user']['username'],
        avatarInitials: 'XX',
        avatarColorHex: '0xFF6366F1',
        about: '',
        presence: PresenceState.online,
        lastSeenAt: DateTime.now(),
        isVerified: false,
        email: data['user']['email'] ?? '',
        phone: '',
        safetyNumber: '',
      );
      _connectWebSocket();
      notifyListeners();
      return _currentUser!;
    } else {
      throw Exception('Authentication failed');
    }
  }

  void _connectWebSocket() {
    if (_token == null) return;
    try {
      final wsUrl = Uri.parse(ApiBackendConfig.getWebSocketUrl(_currentUser!.id));
      _channel = WebSocketChannel.connect(wsUrl);

      _channel?.stream.listen((message) {
        debugPrint('Received message: $message');
        notifyListeners();
      }, onError: (error) {
        debugPrint('WebSocket Error: $error');
      }, onDone: () {
        debugPrint('WebSocket Disconnected');
      });
    } catch (e) {
      debugPrint('Error connecting to WebSocket: $e');
    }
  }

  Future<void> loadConversations() async {
    if (_token == null) return;
    final response = await http.get(
      Uri.parse('${ApiBackendConfig.restApiBaseUrl}/api/chat/rooms'),
      headers: {
        'Authorization': 'Bearer $_token',
        'x-tenant-id': ApiBackendConfig.tenantId,
      },
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      debugPrint('Loaded conversations: $data');
      // Update local state here
    }
  }

  Future<void> loadMessages(String chatId) async {
    if (_token == null) return;
    final response = await http.get(
      Uri.parse('${ApiBackendConfig.restApiBaseUrl}/api/chat/rooms/$chatId/messages'),
      headers: {
        'Authorization': 'Bearer $_token',
        'x-tenant-id': ApiBackendConfig.tenantId,
      },
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      debugPrint('Loaded messages for chat $chatId: $data');
      // Update local state here
    }
  }

  void sendMessage(String chatId, String content) {
    if (_channel != null) {
      final payload = {
        'type': 'send_message',
        'room_id': chatId,
        'content': content,
      };
      _channel!.sink.add(jsonEncode(payload));
    } else {
      debugPrint('Cannot send message: WebSocket is disconnected');
    }
  }

  Future<void> signOut() async {
    _token = null;
    _currentUser = null;
    _channel?.sink.close();
    _channel = null;
    notifyListeners();
  }

  Future<void> setPresence(PresenceState state) async {
    if (_token == null) return;
    // TODO: Implement presence update via REST or WebSocket
    debugPrint('Setting presence to $state');
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
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
  IO.Socket? _socket;

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
      Uri.parse('${ApiBackendConfig.restApiBaseUrl}/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': identifier, 'password': password}),
    );
    return _parseAuthResponse(response);
  }

  Future<UserProfile> register({required String email, required String username, required String password}) async {
    final response = await http.post(
      Uri.parse('${ApiBackendConfig.restApiBaseUrl}/auth/register'),
      headers: {'Content-Type': 'application/json'},
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
      headers: {'Content-Type': 'application/json'},
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
    _socket = IO.io(ApiBackendConfig.webSocketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'extraHeaders': {'Authorization': 'Bearer $_token'}
    });

    _socket?.connect();

    _socket?.on('receive_message', (data) {
      // Handle new message
      debugPrint('Received message: $data');
      notifyListeners();
    });
  }

  Future<void> loadConversations() async {
    if (_token == null) return;
    final response = await http.get(
      Uri.parse('${ApiBackendConfig.restApiBaseUrl}/chats'),
      headers: {'Authorization': 'Bearer $_token'},
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
      Uri.parse('${ApiBackendConfig.restApiBaseUrl}/chats/$chatId/messages'),
      headers: {'Authorization': 'Bearer $_token'},
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      debugPrint('Loaded messages for chat $chatId: $data');
      // Update local state here
    }
  }

  Future<void> signOut() async {
    _token = null;
    _currentUser = null;
    _socket?.disconnect();
    _socket = null;
    notifyListeners();
  }

  Future<void> setPresence(PresenceState state) async {
    if (_token == null) return;
    // TODO: Implement presence update via REST or WebSocket
    debugPrint('Setting presence to $state');
  }
}

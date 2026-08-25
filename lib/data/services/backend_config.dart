import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiBackendConfig {
  static String get restApiBaseUrl => dotenv.env['REST_API_BASE_URL'] ?? 'http://localhost:8000';

  static String get webSocketUrl => dotenv.env['WEBSOCKET_URL'] ?? 'ws://localhost:8000/ws/school';
}

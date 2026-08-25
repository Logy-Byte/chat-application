class ApiBackendConfig {
  static const String restApiBaseUrl = String.fromEnvironment(
    'REST_API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  static const String webSocketUrl = String.fromEnvironment(
    'WEBSOCKET_URL',
    defaultValue: 'ws://localhost:8000/ws/school',
  );
}

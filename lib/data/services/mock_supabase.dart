import 'dart:async';

class Supabase {
  static final Supabase instance = Supabase();
  final SupabaseClient client = SupabaseClient();
}

class SupabaseClient {
  final GoTrueClient auth = GoTrueClient();
  final FunctionsClient functions = FunctionsClient();
  final RealtimeClient realtime = RealtimeClient();
  final StorageClient storage = StorageClient();

  PostgrestQueryBuilder from(String table) {
    return PostgrestQueryBuilder();
  }

  RealtimeChannel channel(String name, {Map<String, dynamic>? opts}) {
    return RealtimeChannel();
  }

  Future<String> removeChannel(RealtimeChannel channel) async { return 'ok'; }
  
  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params}) async {
    return null;
  }
}

class StorageClient {
  StorageFileApi from(String id) => StorageFileApi();
}

class StorageFileApi {
  Future<String> upload(String path, dynamic file, {FileOptions? fileOptions}) async => '';
  Future<String> uploadBinaryFile(String path, dynamic data, {FileOptions? fileOptions}) async => '';
  String getPublicUrl(String path) => '';
  Future<List<dynamic>> remove(List<String> paths) async => [];
  Future<dynamic> download(String path) async => null;
  Future<String> createSignedUrl(String path, int expiresIn) async => '';
}

class FileOptions {
  final String? cacheControl;
  final String? contentType;
  final bool? upsert;
  const FileOptions({this.cacheControl, this.contentType, this.upsert});
}

class GoTrueClient {
  final StreamController<AuthState> _authStateController = StreamController<AuthState>.broadcast();
  Stream<AuthState> get onAuthStateChange => _authStateController.stream;

  Session? get currentSession => null;
  User? get currentUser => null;

  Future<AuthResponse> verifyOTP({String? type, String? token, String? phone, String? email, OtpType? otpType, String? redirectTo}) async {
    return AuthResponse();
  }
  
  Future<void> resetPasswordForEmail(String email, {String? redirectTo}) async {}
  Future<void> updateUser(UserAttributes attributes) async {}
  Future<void> signOut() async {}
  Future<AuthResponse> signUp({String? email, String? password, String? phone, String? emailRedirectTo, Map<String, dynamic>? data}) async => AuthResponse();
  Future<AuthResponse> signInWithPassword({String? email, String? password, String? phone}) async => AuthResponse();
}

enum OtpType { signup, invite, magiclink, recovery, emailchange, phonechange }

class FunctionsClient {
  Future<FunctionResponse> invoke(String functionName, {Map<String, dynamic>? body}) async {
    return FunctionResponse();
  }
}

class RealtimeClient {
  void setAuth(String? token) {}
}

class SupabaseStreamBuilder extends Stream<List<Map<String, dynamic>>> {
  @override
  StreamSubscription<List<Map<String, dynamic>>> listen(
    void Function(List<Map<String, dynamic>> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return const Stream<List<Map<String, dynamic>>>.empty().listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  SupabaseStreamBuilder order(String column, {bool ascending = false}) {
    return this;
  }
  
  SupabaseStreamBuilder limit(int count) {
    return this;
  }
}

class PostgrestQueryBuilder {
  PostgrestFilterBuilder select([String columns = '*']) {
    return PostgrestFilterBuilder();
  }
  PostgrestFilterBuilder insert(dynamic data) {
    return PostgrestFilterBuilder();
  }
  PostgrestFilterBuilder update(Map<String, dynamic> data) {
    return PostgrestFilterBuilder();
  }
  PostgrestFilterBuilder delete() {
    return PostgrestFilterBuilder();
  }
  PostgrestFilterBuilder upsert(dynamic data, {String? onConflict}) {
    return PostgrestFilterBuilder();
  }
  SupabaseStreamBuilder stream({required List<String> primaryKey}) {
    return SupabaseStreamBuilder();
  }
}

class PostgrestFilterBuilder implements Future<List<Map<String, dynamic>>> {
  PostgrestFilterBuilder eq(String column, dynamic value) {
    return this;
  }
  PostgrestFilterBuilder neq(String column, dynamic value) {
    return this;
  }
  PostgrestFilterBuilder in_(String column, List<dynamic> values) {
    return this;
  }
  PostgrestFilterBuilder inFilter(String column, List<dynamic> values) {
    return this;
  }
  PostgrestFilterBuilder contains(String column, dynamic value) {
    return this;
  }
  PostgrestFilterBuilder order(String column, {bool ascending = false}) {
    return this;
  }
  PostgrestFilterBuilder limit(int count) {
    return this;
  }
  PostgrestFilterBuilder select([String columns = '*']) {
    return this;
  }
  PostgrestFilterBuilder isFilter(String column, dynamic value) {
    return this;
  }
  PostgrestFilterBuilder ilike(String column, String pattern) {
    return this;
  }
  PostgrestTransformBuilder single() {
    return PostgrestTransformBuilder();
  }
  PostgrestTransformBuilder maybeSingle() {
    return PostgrestTransformBuilder();
  }
  Future<List<Map<String, dynamic>>> execute() async {
    return [];
  }

  @override
  Stream<List<Map<String, dynamic>>> asStream() {
    return Stream.value([]);
  }

  @override
  Future<List<Map<String, dynamic>>> catchError(Function onError, {bool Function(Object error)? test}) async {
    return [];
  }

  @override
  Future<R> then<R>(FutureOr<R> Function(List<Map<String, dynamic>> value) onValue, {Function? onError}) async {
    return onValue([]);
  }

  @override
  Future<List<Map<String, dynamic>>> timeout(Duration timeLimit, {FutureOr<List<Map<String, dynamic>>> Function()? onTimeout}) async {
    return [];
  }

  @override
  Future<List<Map<String, dynamic>>> whenComplete(FutureOr<void> Function() action) async {
    await action();
    return [];
  }
}

class PostgrestTransformBuilder implements Future<dynamic> {
  @override
  Stream<dynamic> asStream() {
    return Stream.value(null);
  }

  @override
  Future<dynamic> catchError(Function onError, {bool Function(Object error)? test}) async {
    return null;
  }

  @override
  Future<R> then<R>(FutureOr<R> Function(dynamic value) onValue, {Function? onError}) async {
    return onValue(null);
  }

  @override
  Future<dynamic> timeout(Duration timeLimit, {FutureOr<dynamic> Function()? onTimeout}) async {
    return null;
  }

  @override
  Future<dynamic> whenComplete(FutureOr<void> Function() action) async {
    await action();
    return null;
  }
  
  dynamic operator [](String key) => null;
}

enum RealtimeSubscribeStatus { subscribed, closed, channelError, timedOut }

enum PostgresChangeEvent { all, insert, update, delete }

class RealtimeChannel {
  RealtimeChannel on(String event, {Map<String, dynamic>? filter, required Function(dynamic payload) callback}) {
    return this;
  }
  
  RealtimeChannel onPresenceJoin(Function(dynamic payload) callback) {
    return this;
  }
  
  RealtimeChannel onPresenceLeave(Function(dynamic payload) callback) {
    return this;
  }
  
  RealtimeChannel onPresenceSync(Function() callback) {
    return this;
  }

  RealtimeChannel onPostgresChanges({required PostgresChangeEvent event, required String schema, String? table, String? filter, required Function(dynamic payload) callback}) {
    return this;
  }
  
  Future<dynamic> track(Map<String, dynamic> payload) async {
    return null;
  }
  
  Future<dynamic> untrack() async {
    return null;
  }
  
  Future<dynamic> send({required String type, required String event, required Map<String, dynamic> payload}) async {
    return null;
  }
  
  RealtimeChannel subscribe([Function(RealtimeSubscribeStatus status, [dynamic error])? callback]) {
    if (callback != null) {
      callback(RealtimeSubscribeStatus.subscribed);
    }
    return this;
  }
}

class AuthState {
  final AuthChangeEvent event;
  final Session? session;
  AuthState(this.event, this.session);
}

enum AuthChangeEvent { signedIn, signedOut, userUpdated, passwordRecovery, tokenRefreshed }

class Session {
  final User user;
  final String accessToken;
  final String? refreshToken;
  final int? expiresAt;
  Session(this.user, this.accessToken, this.refreshToken, {this.expiresAt});
}

class User {
  final String id;
  final String email;
  final String? phone;
  final Map<String, dynamic>? userMetadata;
  User({required this.id, required this.email, this.phone, this.userMetadata});
}

class AuthResponse {
  final Session? session;
  final User? user;
  AuthResponse({this.session, this.user});
}

class UserAttributes {
  final String? password;
  UserAttributes({this.password});
}

class FunctionResponse {
  final dynamic data;
  final int? status;
  FunctionResponse({this.data, this.status});
}

class PostgrestException implements Exception {
  final String message;
  final String? code;
  final String? details;
  final String? hint;
  PostgrestException({required this.message, this.code, this.details, this.hint});
}

class AuthException implements Exception {
  final String message;
  final int? statusCode;
  AuthException(this.message, {this.statusCode});
}

class StorageException implements Exception {
  final String message;
  StorageException(this.message);
}

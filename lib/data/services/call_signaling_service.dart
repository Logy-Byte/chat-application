import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/call_state.dart';
import '../../domain/models/other_models.dart';
import '../../injection/locator.dart';
import '../repositories/mock_data_store.dart';
import 'backend_service.dart';
import 'rich_chat_realtime_service.dart';

/// Production WebRTC transport for Chaty calls.
///
/// The existing [RichChatRealtimeService] remains responsible for the
/// privacy-gated ringing invite. This service owns the actual media session:
/// SDP/ICE persistence is authorized by Supabase RLS and media flows over
/// WebRTC DTLS-SRTP. A TURN server can be supplied at build time for networks
/// where direct ICE connectivity is unavailable.
class CallSignalingService extends ChangeNotifier {
  CallSignalingService({
    SupabaseClient? client,
    required this.dataStore,
    required this.backend,
  }) : _client = client ?? Supabase.instance.client;

  static const String _turnUrl = String.fromEnvironment('CHATY_TURN_URL');
  static const String _turnUsername = String.fromEnvironment(
    'CHATY_TURN_USERNAME',
  );
  static const String _turnCredential = String.fromEnvironment(
    'CHATY_TURN_CREDENTIAL',
  );

  final SupabaseClient _client;
  final MockDataStore dataStore;
  final ChatyBackendService backend;
  final Uuid _uuid = const Uuid();

  ChatyCallSession? _currentSession;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  MediaStream? _screenShareStream;
  MediaStreamTrack? _cameraVideoTrack;
  RealtimeChannel? _callRealtimeChannel;
  StreamSubscription<CallResponseEvent>? _richResponseSubscription;
  Timer? _ringTimeoutTimer;
  Timer? _durationTimer;
  int _callDurationSeconds = 0;
  bool _remoteDescriptionApplied = false;
  bool _canPersistIce = false;
  bool _isScreenSharing = false;
  bool _disposed = false;
  String? _pendingConversationId;
  String? _pendingOfferSdp;
  Completer<void>? _offerReady;
  final List<RTCIceCandidate> _pendingLocalCandidates = <RTCIceCandidate>[];
  final Set<String> _appliedRemoteCandidateKeys = <String>{};

  ChatyCallSession? get currentSession => _currentSession;
  int get callDurationSeconds => _callDurationSeconds;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  bool get isScreenSharing => _isScreenSharing;
  bool get hasTurnConfigured => _turnUrl.trim().isNotEmpty;

  bool get isInActiveCall {
    final state = _currentSession?.state;
    return state == CallSessionState.connecting ||
        state == CallSessionState.connected ||
        state == CallSessionState.reconnecting;
  }

  Map<String, dynamic> get _rtcConfiguration {
    final servers = <Map<String, dynamic>>[
      <String, dynamic>{
        'urls': <String>[
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
    ];
    if (_turnUrl.trim().isNotEmpty) {
      servers.add(<String, dynamic>{
        'urls': _turnUrl.trim(),
        if (_turnUsername.isNotEmpty) 'username': _turnUsername,
        if (_turnCredential.isNotEmpty) 'credential': _turnCredential,
      });
    }
    return <String, dynamic>{
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
    };
  }

  /// Begins local media preparation for an outgoing call that has already
  /// been announced by [RichChatRealtimeService.placeCall]. The call ID from
  /// that privacy-gated invite becomes authoritative when the recipient
  /// accepts, preventing the old double-invite / mismatched-call-ID bug.
  Future<void> initiateCall({
    required String remoteUserId,
    required String remoteDisplayName,
    String? remoteAvatarInitials,
    String? remoteAvatarColorHex,
    required bool isVideo,
    String? conversationId,
  }) async {
    final myId = _client.auth.currentUser?.id;
    if (myId == null) {
      throw StateError('Authentication is required before starting a call.');
    }
    if (_currentSession != null && !_isTerminal(_currentSession!.state)) {
      throw StateError('Another call is already active.');
    }

    final remoteProfile = dataStore.getUserById(remoteUserId);
    if (remoteProfile == null) {
      throw StateError('The selected contact is not available.');
    }

    await _resetTransport(clearSession: true);
    final resolvedConversationId =
        conversationId ??
        (await dataStore.getOrCreateDirectConversation(remoteProfile)).id;
    _pendingConversationId = resolvedConversationId;
    _offerReady = Completer<void>();
    _currentSession = ChatyCallSession(
      callId: 'pending_${_uuid.v4()}',
      remoteUserId: remoteUserId,
      remoteDisplayName: remoteDisplayName,
      remoteAvatarInitials: remoteAvatarInitials,
      remoteAvatarColorHex: remoteAvatarColorHex,
      isVideo: isVideo,
      isOutgoing: true,
      state: CallSessionState.ringing,
      startedAt: DateTime.now(),
      audioRoute: isVideo ? AudioRouteType.speaker : AudioRouteType.earpiece,
    );
    notifyListeners();

    _richResponseSubscription = locator<RichChatRealtimeService>()
        .callResponses
        .listen((event) => unawaited(_handlePrivacyGateResponse(event)));
    _armRingTimeout();

    try {
      await _preparePeerConnection(isVideo: isVideo);
      final offer = await _peerConnection!.createOffer(<String, dynamic>{});
      await _peerConnection!.setLocalDescription(offer);
      final sdp = offer.sdp;
      if (sdp == null || sdp.isEmpty) {
        throw StateError('WebRTC did not produce a valid call offer.');
      }
      _pendingOfferSdp = sdp;
      if (!(_offerReady?.isCompleted ?? true)) _offerReady!.complete();
    } catch (error) {
      if (!(_offerReady?.isCompleted ?? true)) {
        _offerReady!.completeError(error);
      }
      await _failCurrentCall();
      rethrow;
    }
  }

  Future<void> _handlePrivacyGateResponse(CallResponseEvent event) async {
    final session = _currentSession;
    if (session == null || !session.isOutgoing || _isTerminal(session.state)) {
      return;
    }
    switch (event.response) {
      case 'accepted':
        _ringTimeoutTimer?.cancel();
        try {
          await (_offerReady?.future ?? Future<void>.value()).timeout(
            const Duration(seconds: 10),
          );
          await _activateAcceptedOutgoingCall(event.callId);
        } catch (error, stackTrace) {
          debugPrint('Unable to activate accepted call: $error\n$stackTrace');
          await _failCurrentCall();
        }
        break;
      case 'declined':
        _ringTimeoutTimer?.cancel();
        _currentSession = session.copyWith(
          state: CallSessionState.declined,
          endedAt: DateTime.now(),
        );
        notifyListeners();
        await _resetTransport(clearSession: false);
        break;
      case 'busy':
        _ringTimeoutTimer?.cancel();
        _currentSession = session.copyWith(
          state: CallSessionState.busy,
          endedAt: DateTime.now(),
        );
        notifyListeners();
        await _resetTransport(clearSession: false);
        break;
      case 'cancelled':
        _ringTimeoutTimer?.cancel();
        _currentSession = session.copyWith(
          state: CallSessionState.ended,
          endedAt: DateTime.now(),
        );
        notifyListeners();
        await _resetTransport(clearSession: false);
        break;
      default:
        break;
    }
  }

  Future<void> _activateAcceptedOutgoingCall(String callId) async {
    final session = _currentSession;
    final myId = _client.auth.currentUser?.id;
    final conversationId = _pendingConversationId;
    final offerSdp = _pendingOfferSdp;
    if (session == null ||
        myId == null ||
        conversationId == null ||
        offerSdp == null ||
        callId.isEmpty) {
      throw StateError('Outgoing call state is incomplete.');
    }

    await _client.from('call_sessions').insert(<String, dynamic>{
      'id': callId,
      'conversation_id': conversationId,
      'caller_id': myId,
      'callee_id': session.remoteUserId,
      'kind': session.isVideo ? 'video' : 'voice',
      'status': 'ringing',
      'offer_sdp': offerSdp,
      'started_at': session.startedAt.toUtc().toIso8601String(),
    });

    _currentSession = ChatyCallSession(
      callId: callId,
      remoteUserId: session.remoteUserId,
      remoteDisplayName: session.remoteDisplayName,
      remoteAvatarInitials: session.remoteAvatarInitials,
      remoteAvatarColorHex: session.remoteAvatarColorHex,
      isVideo: session.isVideo,
      isOutgoing: true,
      state: CallSessionState.connecting,
      startedAt: session.startedAt,
      audioRoute: session.audioRoute,
      isMuted: session.isMuted,
      isCameraOff: session.isCameraOff,
      isFrontCamera: session.isFrontCamera,
    );
    _canPersistIce = true;
    await _subscribeToCall(callId);
    await _flushPendingLocalCandidates(callId);
    notifyListeners();

    // Realtime delivery is best-effort; this short authoritative poll closes
    // the race where the callee answers before our subscription is confirmed.
    unawaited(_waitForRemoteAnswer(callId));
  }

  /// Used by the ongoing-call screen opened after the app-level incoming
  /// ringing overlay has been accepted. The caller creates the protected
  /// call_sessions row immediately after receiving that acceptance, so this
  /// method waits briefly for that authoritative offer and then answers it.
  Future<void> acceptLatestIncomingCall() async {
    if (_currentSession != null && !_isTerminal(_currentSession!.state)) return;
    final myId = _client.auth.currentUser?.id;
    if (myId == null) throw StateError('Authentication is required.');

    final earliest = DateTime.now()
        .subtract(const Duration(minutes: 2))
        .toUtc()
        .toIso8601String();
    for (var attempt = 0; attempt < 40; attempt++) {
      final rows = await _client
          .from('call_sessions')
          .select()
          .eq('callee_id', myId)
          .eq('status', 'ringing')
          .gte('started_at', earliest)
          .order('started_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        await _acceptIncomingRow(Map<String, dynamic>.from(rows.first));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError('The incoming call offer did not arrive in time.');
  }

  Future<void> _acceptIncomingRow(Map<String, dynamic> row) async {
    final myId = _client.auth.currentUser?.id;
    final callId = row['id']?.toString() ?? '';
    final callerId = row['caller_id']?.toString() ?? '';
    final offerSdp = row['offer_sdp']?.toString() ?? '';
    final status = row['status']?.toString() ?? '';
    if (myId == null ||
        callId.isEmpty ||
        callerId.isEmpty ||
        row['callee_id']?.toString() != myId ||
        status != 'ringing' ||
        offerSdp.isEmpty) {
      throw StateError('This incoming call is no longer valid.');
    }

    await _resetTransport(clearSession: true);
    final caller = dataStore.getUserById(callerId);
    final isVideo = row['kind']?.toString() == 'video';
    _currentSession = ChatyCallSession(
      callId: callId,
      remoteUserId: callerId,
      remoteDisplayName: caller?.displayName ?? 'Chaty contact',
      remoteAvatarInitials: caller?.avatarInitials,
      remoteAvatarColorHex: caller?.avatarColorHex,
      isVideo: isVideo,
      isOutgoing: false,
      state: CallSessionState.connecting,
      startedAt: DateTime.tryParse(row['started_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      audioRoute: isVideo ? AudioRouteType.speaker : AudioRouteType.earpiece,
    );
    notifyListeners();

    try {
      await _preparePeerConnection(isVideo: isVideo);
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(offerSdp, 'offer'),
      );
      _remoteDescriptionApplied = true;
      final answer = await _peerConnection!.createAnswer(<String, dynamic>{});
      await _peerConnection!.setLocalDescription(answer);
      final answerSdp = answer.sdp;
      if (answerSdp == null || answerSdp.isEmpty) {
        throw StateError('WebRTC did not produce a valid call answer.');
      }

      await _subscribeToCall(callId);
      await _client.rpc(
        'accept_call_session',
        params: <String, dynamic>{
          'p_call_id': callId,
          'p_answer_sdp': answerSdp,
        },
      );
      _canPersistIce = true;
      await _flushPendingLocalCandidates(callId);
      await _loadExistingRemoteCandidates(callId);
    } catch (error) {
      await _failCurrentCall();
      rethrow;
    }
  }

  Future<void> acceptCall() => acceptLatestIncomingCall();

  Future<void> declineCall() async {
    final session = _currentSession;
    if (session == null || session.callId.startsWith('pending_')) return;
    try {
      await _client.rpc(
        'decline_call_session',
        params: <String, dynamic>{'p_call_id': session.callId},
      );
    } finally {
      _currentSession = session.copyWith(
        state: CallSessionState.declined,
        endedAt: DateTime.now(),
      );
      notifyListeners();
      await _resetTransport(clearSession: false);
    }
  }

  Future<void> endCall({String reason = 'ended'}) async {
    final session = _currentSession;
    if (session == null) return;
    _ringTimeoutTimer?.cancel();
    _stopDurationTimer();

    if (!session.callId.startsWith('pending_')) {
      try {
        await _client.rpc(
          'end_call_session',
          params: <String, dynamic>{'p_call_id': session.callId},
        );
      } catch (_) {
        // The peer may already have ended the row. Local teardown still runs.
      }
      _logCallRecord(
        session.isOutgoing
            ? CallDirection.outgoing
            : (_callDurationSeconds > 0
                  ? CallDirection.incoming
                  : CallDirection.missed),
        _callDurationSeconds,
      );
    }

    _currentSession = session.copyWith(
      state: reason == 'no_answer'
          ? CallSessionState.missed
          : CallSessionState.ended,
      endedAt: DateTime.now(),
    );
    notifyListeners();
    await _resetTransport(clearSession: false);
  }

  void toggleMute() {
    final session = _currentSession;
    if (session == null) return;
    final muted = !session.isMuted;
    for (final track in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
    _currentSession = session.copyWith(isMuted: muted);
    notifyListeners();
  }

  void toggleCamera() {
    final session = _currentSession;
    if (session == null || !session.isVideo) return;
    final cameraOff = !session.isCameraOff;
    for (final track in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !cameraOff;
    }
    for (final track
        in _screenShareStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !cameraOff;
    }
    _currentSession = session.copyWith(isCameraOff: cameraOff);
    notifyListeners();
  }

  void switchCamera() {
    final session = _currentSession;
    final track = _cameraVideoTrack;
    if (session == null || track == null || _isScreenSharing) return;
    unawaited(
      Helper.switchCamera(track, null, _localStream).then((_) {
        if (_disposed || _currentSession == null) return;
        _currentSession = _currentSession!.copyWith(
          isFrontCamera: !_currentSession!.isFrontCamera,
        );
        notifyListeners();
      }),
    );
  }

  void setAudioRoute(AudioRouteType route) {
    if (_currentSession == null) return;
    _currentSession = _currentSession!.copyWith(audioRoute: route);
    switch (route) {
      case AudioRouteType.speaker:
        unawaited(Helper.setSpeakerphoneOn(true));
        break;
      case AudioRouteType.bluetooth:
        unawaited(Helper.setSpeakerphoneOnButPreferBluetooth());
        break;
      case AudioRouteType.earpiece:
      case AudioRouteType.wiredHeadset:
        unawaited(Helper.setSpeakerphoneOn(false));
        break;
    }
    notifyListeners();
  }

  Future<void> startScreenShare() async {
    final session = _currentSession;
    final peer = _peerConnection;
    if (session == null || !session.isVideo || peer == null || _isScreenSharing) {
      return;
    }
    final display = await navigator.mediaDevices.getDisplayMedia(
      <String, dynamic>{'video': true, 'audio': false},
    );
    final displayTracks = display.getVideoTracks();
    if (displayTracks.isEmpty) {
      await display.dispose();
      throw StateError('No screen-capture track was returned.');
    }
    final senders = await peer.getSenders();
    RTCRtpSender? videoSender;
    for (final sender in senders) {
      if (sender.track?.kind == 'video') {
        videoSender = sender;
        break;
      }
    }
    if (videoSender == null) {
      await display.dispose();
      throw StateError('No active video sender is available for screen share.');
    }
    await videoSender.replaceTrack(displayTracks.first);
    _screenShareStream = display;
    _isScreenSharing = true;
    notifyListeners();
  }

  Future<void> stopScreenShare() async {
    final peer = _peerConnection;
    final cameraTrack = _cameraVideoTrack;
    if (!_isScreenSharing || peer == null || cameraTrack == null) return;
    final senders = await peer.getSenders();
    RTCRtpSender? videoSender;
    for (final sender in senders) {
      if (sender.track?.kind == 'video') {
        videoSender = sender;
        break;
      }
    }
    if (videoSender != null) await videoSender.replaceTrack(cameraTrack);
    final stream = _screenShareStream;
    _screenShareStream = null;
    _isScreenSharing = false;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
    }
    notifyListeners();
  }

  Future<void> _preparePeerConnection({required bool isVideo}) async {
    _peerConnection = await createPeerConnection(_rtcConfiguration);
    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      final callId = _currentSession?.callId;
      if (callId == null || !_canPersistIce || callId.startsWith('pending_')) {
        _pendingLocalCandidates.add(candidate);
        return;
      }
      unawaited(_persistCandidate(callId, candidate));
    };
    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        if (!_disposed) notifyListeners();
      }
    };
    _peerConnection!.onConnectionState = (state) {
      if (_disposed || _currentSession == null) return;
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          if (_currentSession!.state != CallSessionState.connected) {
            _currentSession = _currentSession!.copyWith(
              state: CallSessionState.connected,
              connectedAt: DateTime.now(),
            );
            _startDurationTimer();
            notifyListeners();
          }
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _currentSession = _currentSession!.copyWith(
            state: CallSessionState.reconnecting,
          );
          notifyListeners();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _currentSession = _currentSession!.copyWith(
            state: CallSessionState.failed,
            endedAt: DateTime.now(),
          );
          notifyListeners();
          break;
        default:
          break;
      }
    };

    _localStream = await navigator.mediaDevices.getUserMedia(
      <String, dynamic>{
        'audio': <String, dynamic>{
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': isVideo
            ? <String, dynamic>{
                'facingMode': 'user',
                'width': <String, dynamic>{'ideal': 1280},
                'height': <String, dynamic>{'ideal': 720},
                'frameRate': <String, dynamic>{'ideal': 30, 'max': 30},
              }
            : false,
      },
    );
    final videoTracks = _localStream!.getVideoTracks();
    _cameraVideoTrack = videoTracks.isEmpty ? null : videoTracks.first;
    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }
    await Helper.setSpeakerphoneOn(isVideo);
    if (!_disposed) notifyListeners();
  }

  Future<void> _subscribeToCall(String callId) async {
    final old = _callRealtimeChannel;
    _callRealtimeChannel = null;
    if (old != null) {
      try {
        await _client.removeChannel(old);
      } catch (_) {}
    }

    final channel = _client.channel('chaty_webrtc_v1_$callId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'call_sessions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: callId,
          ),
          callback: (payload) {
            final row = payload.eventType == PostgresChangeEvent.delete
                ? payload.oldRecord
                : payload.newRecord;
            unawaited(_handleCallRow(Map<String, dynamic>.from(row)));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'call_ice_candidates',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'call_id',
            value: callId,
          ),
          callback: (payload) {
            unawaited(
              _handleRemoteIceRow(
                Map<String, dynamic>.from(payload.newRecord),
              ),
            );
          },
        )
        .subscribe();
    _callRealtimeChannel = channel;
  }

  Future<void> _handleCallRow(Map<String, dynamic> row) async {
    final session = _currentSession;
    if (session == null || row['id']?.toString() != session.callId) return;
    final status = row['status']?.toString() ?? '';
    if (status == 'accepted') {
      if (session.isOutgoing) await _applyRemoteAnswer(row);
      return;
    }
    if (status == 'declined' || status == 'ended' || status == 'failed') {
      _ringTimeoutTimer?.cancel();
      _stopDurationTimer();
      _currentSession = session.copyWith(
        state: status == 'declined'
            ? CallSessionState.declined
            : status == 'failed'
            ? CallSessionState.failed
            : CallSessionState.ended,
        endedAt: DateTime.now(),
      );
      notifyListeners();
      await _resetTransport(clearSession: false);
    }
  }

  Future<void> _waitForRemoteAnswer(String callId) async {
    for (var attempt = 0; attempt < 40; attempt++) {
      if (_disposed || _currentSession?.callId != callId) return;
      try {
        final raw = await _client
            .from('call_sessions')
            .select('id,status,answer_sdp')
            .eq('id', callId)
            .single();
        final row = Map<String, dynamic>.from(raw);
        if (row['status']?.toString() == 'accepted' &&
            (row['answer_sdp']?.toString().isNotEmpty ?? false)) {
          await _applyRemoteAnswer(row);
          return;
        }
        if (row['status']?.toString() == 'ended' ||
            row['status']?.toString() == 'declined' ||
            row['status']?.toString() == 'failed') {
          await _handleCallRow(row);
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> _applyRemoteAnswer(Map<String, dynamic> row) async {
    if (_remoteDescriptionApplied || _peerConnection == null) return;
    final answerSdp = row['answer_sdp']?.toString() ?? '';
    if (answerSdp.isEmpty) return;
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(answerSdp, 'answer'),
    );
    _remoteDescriptionApplied = true;
    if (_currentSession != null) {
      _currentSession = _currentSession!.copyWith(
        state: CallSessionState.connecting,
      );
      notifyListeners();
    }
    await _loadExistingRemoteCandidates(row['id']?.toString() ?? '');
  }

  Future<void> _persistCandidate(
    String callId,
    RTCIceCandidate candidate,
  ) async {
    final myId = _client.auth.currentUser?.id;
    final value = candidate.candidate;
    if (myId == null || value == null || value.isEmpty) return;
    try {
      await _client.from('call_ice_candidates').insert(<String, dynamic>{
        'call_id': callId,
        'sender_id': myId,
        'candidate': value,
        'sdp_mid': candidate.sdpMid,
        'sdp_mline_index': candidate.sdpMLineIndex,
      });
    } catch (error, stackTrace) {
      debugPrint('Unable to persist WebRTC ICE candidate: $error\n$stackTrace');
    }
  }

  Future<void> _flushPendingLocalCandidates(String callId) async {
    final pending = List<RTCIceCandidate>.from(_pendingLocalCandidates);
    _pendingLocalCandidates.clear();
    for (final candidate in pending) {
      await _persistCandidate(callId, candidate);
    }
  }

  Future<void> _loadExistingRemoteCandidates(String callId) async {
    if (callId.isEmpty || _peerConnection == null) return;
    final rows = await _client
        .from('call_ice_candidates')
        .select()
        .eq('call_id', callId)
        .order('id');
    for (final item in rows) {
      await _handleRemoteIceRow(Map<String, dynamic>.from(item));
    }
  }

  Future<void> _handleRemoteIceRow(Map<String, dynamic> row) async {
    final peer = _peerConnection;
    final myId = _client.auth.currentUser?.id;
    if (peer == null || myId == null || row['sender_id']?.toString() == myId) {
      return;
    }
    final candidateValue = row['candidate']?.toString() ?? '';
    if (candidateValue.isEmpty) return;
    final key = '${row['sender_id']}:${row['id']}:$candidateValue';
    if (!_appliedRemoteCandidateKeys.add(key)) return;
    final indexValue = row['sdp_mline_index'];
    final index = indexValue is int
        ? indexValue
        : int.tryParse(indexValue?.toString() ?? '');
    try {
      await peer.addCandidate(
        RTCIceCandidate(candidateValue, row['sdp_mid']?.toString(), index),
      );
    } catch (error) {
      // Candidate delivery can race the remote-description application. Allow
      // the post-answer backfill to retry it instead of losing it forever.
      _appliedRemoteCandidateKeys.remove(key);
      debugPrint('Deferred WebRTC ICE candidate: $error');
    }
  }

  void _armRingTimeout() {
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = Timer(const Duration(seconds: 45), () {
      final state = _currentSession?.state;
      if (state == CallSessionState.ringing ||
          state == CallSessionState.initiating) {
        unawaited(endCall(reason: 'no_answer'));
      }
    });
  }

  void _startDurationTimer() {
    if (_durationTimer != null) return;
    _callDurationSeconds = 0;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _callDurationSeconds++;
      if (!_disposed) notifyListeners();
    });
  }

  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  void _logCallRecord(CallDirection direction, int durationSec) {
    final session = _currentSession;
    final myId = _client.auth.currentUser?.id;
    if (session == null || myId == null) return;
    dataStore.addCallRecord(
      CallRecord(
        id: session.callId,
        callerId: session.isOutgoing ? myId : session.remoteUserId,
        participantIds: <String>[myId, session.remoteUserId],
        type: session.isVideo ? CallType.video : CallType.voice,
        direction: direction,
        durationSeconds: durationSec,
        timestamp: session.startedAt,
        isEncrypted: true,
      ),
    );
  }

  Future<void> _failCurrentCall() async {
    final session = _currentSession;
    if (session != null) {
      _currentSession = session.copyWith(
        state: CallSessionState.failed,
        endedAt: DateTime.now(),
      );
      notifyListeners();
    }
    await _resetTransport(clearSession: false);
  }

  bool _isTerminal(CallSessionState state) {
    return state == CallSessionState.declined ||
        state == CallSessionState.busy ||
        state == CallSessionState.missed ||
        state == CallSessionState.ended ||
        state == CallSessionState.failed;
  }

  Future<void> _resetTransport({required bool clearSession}) async {
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;
    _stopDurationTimer();
    _callDurationSeconds = 0;
    _remoteDescriptionApplied = false;
    _canPersistIce = false;
    _pendingConversationId = null;
    _pendingOfferSdp = null;
    _offerReady = null;
    _pendingLocalCandidates.clear();
    _appliedRemoteCandidateKeys.clear();

    await _richResponseSubscription?.cancel();
    _richResponseSubscription = null;

    final callChannel = _callRealtimeChannel;
    _callRealtimeChannel = null;
    if (callChannel != null) {
      try {
        await _client.removeChannel(callChannel);
      } catch (_) {}
    }

    final share = _screenShareStream;
    _screenShareStream = null;
    _isScreenSharing = false;
    if (share != null) {
      for (final track in share.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await share.dispose();
      } catch (_) {}
    }

    final local = _localStream;
    _localStream = null;
    _cameraVideoTrack = null;
    if (local != null) {
      for (final track in local.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await local.dispose();
      } catch (_) {}
    }

    _remoteStream = null;
    final peer = _peerConnection;
    _peerConnection = null;
    if (peer != null) {
      try {
        await peer.close();
      } catch (_) {}
      try {
        await peer.dispose();
      } catch (_) {}
    }
    try {
      await Helper.clearAndroidCommunicationDevice();
    } catch (_) {}
    if (clearSession) _currentSession = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ringTimeoutTimer?.cancel();
    _stopDurationTimer();
    unawaited(_resetTransport(clearSession: true));
    super.dispose();
  }
}

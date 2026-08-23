import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/call_state.dart';
import '../../domain/models/other_models.dart';
import '../repositories/mock_data_store.dart';
import 'backend_service.dart';

/// Production call transport for Chaty.
///
/// Supabase is used only for authenticated signaling/state persistence. Media
/// flows peer-to-peer through WebRTC (or through an explicitly configured TURN
/// relay when direct ICE connectivity is not possible).
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

  RealtimeChannel? _personalSignalChannel;
  RealtimeChannel? _callRealtimeChannel;
  Timer? _ringTimeoutTimer;
  Timer? _durationTimer;
  int _callDurationSeconds = 0;
  bool _remoteDescriptionApplied = false;
  bool _isScreenSharing = false;
  bool _disposed = false;
  final List<RTCIceCandidate> _pendingLocalCandidates = <RTCIceCandidate>[];
  final Set<String> _appliedRemoteCandidateKeys = <String>{};

  ChatyCallSession? get currentSession => _currentSession;
  int get callDurationSeconds => _callDurationSeconds;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  bool get isScreenSharing => _isScreenSharing;
  bool get hasTurnConfigured => _turnUrl.trim().isNotEmpty;

  bool get isInActiveCall =>
      _currentSession != null &&
      (_currentSession!.state == CallSessionState.connecting ||
          _currentSession!.state == CallSessionState.connected ||
          _currentSession!.state == CallSessionState.reconnecting);

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

  /// Starts a real outgoing voice/video call.
  ///
  /// [conversationId] should be supplied by chat surfaces. Call-history
  /// redials may omit it; in that case Chaty resolves/creates the direct
  /// conversation through the existing production backend before signaling.
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
    if (_currentSession != null &&
        _currentSession!.state != CallSessionState.ended &&
        _currentSession!.state != CallSessionState.declined &&
        _currentSession!.state != CallSessionState.failed) {
      throw StateError('Another call is already active.');
    }

    final remoteProfile = dataStore.getUserById(remoteUserId);
    if (remoteProfile == null) {
      throw StateError('The selected contact is not available.');
    }
    final resolvedConversationId =
        conversationId ??
        (await dataStore.getOrCreateDirectConversation(remoteProfile)).id;

    await _resetTransport(clearSession: true);
    final callId = _uuid.v4();
    _currentSession = ChatyCallSession(
      callId: callId,
      remoteUserId: remoteUserId,
      remoteDisplayName: remoteDisplayName,
      remoteAvatarInitials: remoteAvatarInitials,
      remoteAvatarColorHex: remoteAvatarColorHex,
      isVideo: isVideo,
      isOutgoing: true,
      state: CallSessionState.initiating,
      startedAt: DateTime.now(),
      audioRoute: isVideo ? AudioRouteType.speaker : AudioRouteType.earpiece,
    );
    notifyListeners();

    try {
      await _preparePeerConnection(isVideo: isVideo);
      final offer = await _peerConnection!.createOffer(<String, dynamic>{});
      await _peerConnection!.setLocalDescription(offer);
      final sdp = offer.sdp;
      if (sdp == null || sdp.isEmpty) {
        throw StateError('WebRTC did not produce a valid call offer.');
      }

      await _client.from('call_sessions').insert(<String, dynamic>{
        'id': callId,
        'conversation_id': resolvedConversationId,
        'caller_id': myId,
        'callee_id': remoteUserId,
        'kind': isVideo ? 'video' : 'voice',
        'status': 'ringing',
        'offer_sdp': sdp,
        'started_at': DateTime.now().toUtc().toIso8601String(),
      });

      await _subscribeToCall(callId);
      await _flushPendingLocalCandidates(callId);
      _subscribePersonalSignals(myId);
      await _sendBroadcast(
        remoteUserId,
        event: 'chaty_call_invite',
        payload: <String, dynamic>{
          'call_id': callId,
          'from': myId,
          'from_name': backend.currentUser?.displayName ?? remoteDisplayName,
          'is_video': isVideo,
        },
      );

      _currentSession = _currentSession?.copyWith(
        state: CallSessionState.ringing,
      );
      notifyListeners();
      _armRingTimeout();
    } catch (error) {
      await _failCurrentCall();
      rethrow;
    }
  }

  /// Accepts the app-level incoming-call invite after the privacy gate has
  /// already allowed it. The authoritative SDP is fetched from the protected
  /// call_sessions row, never trusted from the broadcast payload.
  Future<void> acceptIncomingInvite({
    required String callId,
    required String fromUserId,
    required String fromDisplayName,
    String? fromAvatarInitials,
    String? fromAvatarColorHex,
    required bool isVideo,
  }) async {
    final myId = _client.auth.currentUser?.id;
    if (myId == null) throw StateError('Authentication is required.');

    final raw = await _client
        .from('call_sessions')
        .select()
        .eq('id', callId)
        .single();
    final row = Map<String, dynamic>.from(raw);
    if (row['callee_id']?.toString() != myId ||
        row['caller_id']?.toString() != fromUserId ||
        row['status']?.toString() != 'ringing') {
      throw StateError('This call is no longer available.');
    }
    final offerSdp = row['offer_sdp']?.toString() ?? '';
    if (offerSdp.isEmpty) throw StateError('Incoming call offer is invalid.');

    await _resetTransport(clearSession: true);
    _currentSession = ChatyCallSession(
      callId: callId,
      remoteUserId: fromUserId,
      remoteDisplayName: fromDisplayName,
      remoteAvatarInitials: fromAvatarInitials,
      remoteAvatarColorHex: fromAvatarColorHex,
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
      await _flushPendingLocalCandidates(callId);
      await _loadExistingRemoteCandidates(callId);
      _subscribePersonalSignals(myId);
    } catch (error) {
      await _failCurrentCall();
      rethrow;
    }
  }

  Future<void> declineIncomingInvite(String callId) async {
    try {
      await _client.rpc(
        'decline_call_session',
        params: <String, dynamic>{'p_call_id': callId},
      );
    } finally {
      if (_currentSession?.callId == callId) {
        await _resetTransport(clearSession: true);
      }
    }
  }

  /// Compatibility path for the dedicated incoming-call screen. New incoming
  /// calls should enter through [acceptIncomingInvite], which binds WebRTC to
  /// the authoritative persisted offer before opening the ongoing-call UI.
  Future<void> acceptCall() async {
    final session = _currentSession;
    if (session == null || session.state != CallSessionState.incoming) return;
    throw StateError(
      'Incoming WebRTC calls must be accepted from the verified invite flow.',
    );
  }

  Future<void> declineCall() async {
    final session = _currentSession;
    if (session == null) return;
    await declineIncomingInvite(session.callId);
  }

  Future<void> endCall({String reason = 'ended'}) async {
    final session = _currentSession;
    if (session == null) return;
    _ringTimeoutTimer?.cancel();
    _stopDurationTimer();

    try {
      await _client.rpc(
        'end_call_session',
        params: <String, dynamic>{'p_call_id': session.callId},
      );
    } catch (_) {
      // A peer may have already ended the row. Local teardown must still run.
    }
    try {
      await _sendBroadcast(
        session.remoteUserId,
        event: 'chaty_call_response',
        payload: <String, dynamic>{
          'call_id': session.callId,
          'response': reason == 'no_answer' ? 'cancelled' : 'ended',
        },
      );
    } catch (_) {}

    _logCallRecord(
      session.isOutgoing
          ? CallDirection.outgoing
          : (_callDurationSeconds > 0
                ? CallDirection.incoming
                : CallDirection.missed),
      _callDurationSeconds,
    );
    _currentSession = session.copyWith(
      state: CallSessionState.ended,
      endedAt: DateTime.now(),
    );
    notifyListeners();
    await _resetTransport(clearSession: false);
  }

  Future<void> sendCallReaction(String emoji) async {
    final session = _currentSession;
    if (session == null || session.state != CallSessionState.connected) return;
    await _sendBroadcast(
      session.remoteUserId,
      event: 'chaty_call_reaction',
      payload: <String, dynamic>{
        'call_id': session.callId,
        'reaction': emoji,
      },
    );
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
    if (_screenShareStream != null) {
      for (final track in _screenShareStream!.getVideoTracks()) {
        track.enabled = !cameraOff;
      }
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
      case AudioRouteType.bluetooth:
        unawaited(Helper.setSpeakerphoneOnButPreferBluetooth());
      case AudioRouteType.earpiece:
      case AudioRouteType.wiredHeadset:
        unawaited(Helper.setSpeakerphoneOn(false));
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
    final videoSender = senders.where((sender) => sender.track?.kind == 'video').firstOrNull;
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
    final videoSender = senders.where((sender) => sender.track?.kind == 'video').firstOrNull;
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
      if (callId == null) return;
      if (_currentSession?.state == CallSessionState.initiating) {
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
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _currentSession = _currentSession!.copyWith(
            state: CallSessionState.reconnecting,
          );
          notifyListeners();
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _currentSession = _currentSession!.copyWith(
            state: CallSessionState.failed,
            endedAt: DateTime.now(),
          );
          notifyListeners();
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
    _cameraVideoTrack = _localStream!.getVideoTracks().firstOrNull;
    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }
    await Helper.setSpeakerphoneOn(isVideo);
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

  void _subscribePersonalSignals(String userId) {
    if (_personalSignalChannel != null) return;
    final channel = _client.channel('chaty_calls_v1_$userId');
    channel
        .onBroadcast(
          event: 'chaty_call_response',
          callback: (payload) {
            unawaited(
              _handleSignalResponse(Map<String, dynamic>.from(payload)),
            );
          },
        )
        .subscribe();
    _personalSignalChannel = channel;
  }

  Future<void> _handleSignalResponse(Map<String, dynamic> payload) async {
    final session = _currentSession;
    if (session == null || payload['call_id']?.toString() != session.callId) {
      return;
    }
    final response = payload['response']?.toString() ?? '';
    switch (response) {
      case 'accepted':
        await _applyRemoteAnswerFromDatabase(session.callId);
      case 'declined':
        _ringTimeoutTimer?.cancel();
        _currentSession = session.copyWith(
          state: CallSessionState.declined,
          endedAt: DateTime.now(),
        );
        notifyListeners();
      case 'busy':
        _ringTimeoutTimer?.cancel();
        _currentSession = session.copyWith(
          state: CallSessionState.busy,
          endedAt: DateTime.now(),
        );
        notifyListeners();
      case 'ended':
      case 'cancelled':
        _ringTimeoutTimer?.cancel();
        _stopDurationTimer();
        _currentSession = session.copyWith(
          state: CallSessionState.ended,
          endedAt: DateTime.now(),
        );
        notifyListeners();
        await _resetTransport(clearSession: false);
    }
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

  Future<void> _applyRemoteAnswerFromDatabase(String callId) async {
    if (_remoteDescriptionApplied) return;
    final raw = await _client
        .from('call_sessions')
        .select('id,status,answer_sdp')
        .eq('id', callId)
        .single();
    await _applyRemoteAnswer(Map<String, dynamic>.from(raw));
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
      // Candidate delivery can race remote-description application. Remove the
      // dedupe key so the post-answer backfill can safely retry it.
      _appliedRemoteCandidateKeys.remove(key);
      debugPrint('Deferred WebRTC ICE candidate: $error');
    }
  }

  void _armRingTimeout() {
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = Timer(const Duration(seconds: 40), () {
      final state = _currentSession?.state;
      if (state == CallSessionState.ringing ||
          state == CallSessionState.initiating ||
          state == CallSessionState.connecting) {
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

  Future<void> _sendBroadcast(
    String toUserId, {
    required String event,
    required Map<String, dynamic> payload,
  }) async {
    final completer = Completer<void>();
    final channel = _client.channel('chaty_calls_v1_$toUserId');
    try {
      channel.subscribe((status, error) {
        if (completer.isCompleted) return;
        if (status == RealtimeSubscribeStatus.subscribed) {
          completer.complete();
        } else if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut) {
          completer.completeError(error ?? StateError('channel $status'));
        }
      });
      await completer.future.timeout(const Duration(seconds: 6));
      await channel.sendBroadcastMessage(event: event, payload: payload);
    } finally {
      try {
        await _client.removeChannel(channel);
      } catch (_) {}
    }
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

  Future<void> _resetTransport({required bool clearSession}) async {
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;
    _stopDurationTimer();
    _callDurationSeconds = 0;
    _remoteDescriptionApplied = false;
    _pendingLocalCandidates.clear();
    _appliedRemoteCandidateKeys.clear();

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
    final personal = _personalSignalChannel;
    _personalSignalChannel = null;
    if (personal != null) unawaited(_client.removeChannel(personal));
    unawaited(_resetTransport(clearSession: true));
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../data/services/call_signaling_service.dart';
import '../../domain/models/call_state.dart';
import '../../injection/locator.dart';
import '../../ui/core/design_system/design_system.dart';
import '../../ui/core/widgets/app_avatar.dart';
import '../camera/effects/effect_engine.dart';
import '../camera/effects/widgets/effect_picker_sheet.dart';

/// Full-screen production call surface backed by the WebRTC transport.
class OngoingCallScreen extends StatefulWidget {
  final ThemeConfig theme;

  const OngoingCallScreen({super.key, required this.theme});

  @override
  State<OngoingCallScreen> createState() => _OngoingCallScreenState();
}

class _OngoingCallScreenState extends State<OngoingCallScreen> {
  final CallSignalingService _calls = locator<CallSignalingService>();
  final EffectEngine _effects = locator<EffectEngine>();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  bool _renderersReady = false;
  bool _bootstrapping = true;
  bool _controlsVisible = true;
  bool _focusMode = false;
  String? _error;
  Offset _pipOffset = const Offset(20, 86);
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _calls.addListener(_onCallChanged);
    unawaited(_initialize());
    _scheduleHide();
  }

  Future<void> _initialize() async {
    try {
      await _remoteRenderer.initialize();
      await _localRenderer.initialize();
      if (!mounted) return;
      _renderersReady = true;
      _syncRenderers();

      // Outgoing call setup starts immediately before navigation. Give it one
      // event-loop turn to publish its local session before treating this as an
      // accepted incoming call.
      if (_calls.currentSession == null) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      if (_calls.currentSession == null) {
        await _calls.acceptLatestIncomingCall();
      }
      if (!mounted) return;
      _syncRenderers();
      setState(() {
        _bootstrapping = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _bootstrapping = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  void _onCallChanged() {
    _syncRenderers();
    final state = _calls.currentSession?.state;
    final terminal = state == CallSessionState.ended ||
        state == CallSessionState.declined ||
        state == CallSessionState.busy ||
        state == CallSessionState.missed ||
        state == CallSessionState.failed;
    if (terminal && mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _syncRenderers() {
    if (!_renderersReady) return;
    final local = _calls.localStream;
    final remote = _calls.remoteStream;
    if (!identical(_localRenderer.srcObject, local)) {
      _localRenderer.srcObject = local;
    }
    if (!identical(_remoteRenderer.srcObject, remote)) {
      _remoteRenderer.srcObject = remote;
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_focusMode) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  Future<void> _end() async {
    await _calls.endCall();
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _toggleShare() async {
    try {
      if (_calls.isScreenSharing) {
        await _calls.stopScreenShare();
      } else {
        await _calls.startScreenShare();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  @override
  void dispose() {
    _calls.removeListener(_onCallChanged);
    _hideTimer?.cancel();
    unawaited(_remoteRenderer.dispose());
    unawaited(_localRenderer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final session = _calls.currentSession;

    if (session == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: _error == null && _bootstrapping
                ? const CircularProgressIndicator()
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.call_end_rounded,
                          size: 54,
                          color: colors.error,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Unable to connect the call',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.foregroundSecondary),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_end());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _remoteSurface(session, colors),
              if (session.isVideo && !_focusMode) _localPreview(session, colors),
              _header(session),
              _controls(session, colors),
              if (!_calls.hasTurnConfigured &&
                  session.state != CallSessionState.connected)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 82,
                  left: 24,
                  right: 24,
                  child: IgnorePointer(
                    child: Text(
                      'Direct WebRTC path only — TURN relay is not configured',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _remoteSurface(ChatyCallSession session, AppColors colors) {
    final hasVideo = session.isVideo &&
        _renderersReady &&
        _calls.remoteStream != null &&
        _remoteRenderer.srcObject != null;
    if (!hasVideo) return _voiceBackdrop(session, colors);

    return _effects.renderEffect(
      child: ColoredBox(
        color: Colors.black,
        child: RTCVideoView(
          _remoteRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        ),
      ),
    );
  }

  Widget _localPreview(ChatyCallSession session, AppColors colors) {
    final canRender = _renderersReady &&
        !session.isCameraOff &&
        _calls.localStream != null &&
        _localRenderer.srcObject != null;

    return Positioned(
      left: _pipOffset.dx,
      top: _pipOffset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          final size = MediaQuery.of(context).size;
          setState(() {
            _pipOffset = Offset(
              (_pipOffset.dx + details.delta.dx).clamp(
                12.0,
                (size.width - 132).clamp(12.0, double.infinity),
              ),
              (_pipOffset.dy + details.delta.dy).clamp(
                60.0,
                (size.height - 218).clamp(60.0, double.infinity),
              ),
            );
          });
        },
        child: Container(
          width: 120,
          height: 160,
          decoration: BoxDecoration(
            color: colors.surfaceSecondary,
            borderRadius: BorderRadius.circular(ChatyRadius.lg),
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(ChatyRadius.lg),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (canRender)
                  RTCVideoView(
                    _localRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    mirror: session.isFrontCamera && !_calls.isScreenSharing,
                  )
                else
                  ColoredBox(
                    color: colors.surfaceSecondary,
                    child: Icon(
                      Icons.videocam_off_rounded,
                      color: colors.foregroundSecondary,
                    ),
                  ),
                if (!_calls.isScreenSharing)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: IconButton.filledTonal(
                      tooltip: 'Switch camera',
                      onPressed: _calls.switchCamera,
                      icon: const Icon(Icons.flip_camera_ios_rounded, size: 16),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(34, 34),
                        maximumSize: const Size(34, 34),
                      ),
                    ),
                  ),
                if (_calls.isScreenSharing)
                  const Positioned(
                    left: 7,
                    bottom: 7,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xAA000000),
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Text(
                          'Screen',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ChatyCallSession session) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      top: _controlsVisible ? 0 : -112,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          10,
          MediaQuery.of(context).padding.top + 6,
          10,
          14,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.78), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'End call',
              onPressed: () => unawaited(_end()),
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    session.remoteDisplayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _status(session),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: _focusMode ? 'Show controls' : 'Focus mode',
              onPressed: () => setState(() => _focusMode = !_focusMode),
              icon: Icon(
                _focusMode
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls(ChatyCallSession session, AppColors colors) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      bottom: _controlsVisible ? 0 : -156,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          16,
          22,
          16,
          MediaQuery.of(context).padding.bottom + 22,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.88), Colors.transparent],
          ),
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            _control(
              label: session.isMuted ? 'Unmute' : 'Mute',
              icon: session.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              active: session.isMuted,
              activeColor: colors.error,
              onTap: _calls.toggleMute,
            ),
            if (session.isVideo)
              _control(
                label: session.isCameraOff ? 'Camera on' : 'Camera off',
                icon: session.isCameraOff
                    ? Icons.videocam_off_rounded
                    : Icons.videocam_rounded,
                active: session.isCameraOff,
                activeColor: colors.error,
                onTap: _calls.toggleCamera,
              ),
            if (session.isVideo)
              _control(
                label: _calls.isScreenSharing ? 'Stop sharing' : 'Share screen',
                icon: _calls.isScreenSharing
                    ? Icons.stop_screen_share_rounded
                    : Icons.screen_share_rounded,
                active: _calls.isScreenSharing,
                activeColor: colors.primary,
                onTap: () => unawaited(_toggleShare()),
              ),
            if (session.isVideo)
              _control(
                label: 'Video effects',
                icon: Icons.auto_awesome_rounded,
                active: _effects.activeEffect.id != 'none',
                activeColor: colors.primary,
                onTap: () => EffectPickerSheet.show(context),
              ),
            _control(
              label: session.audioRoute == AudioRouteType.speaker
                  ? 'Use earpiece'
                  : 'Use speaker',
              icon: session.audioRoute == AudioRouteType.speaker
                  ? Icons.volume_up_rounded
                  : Icons.hearing_rounded,
              active: session.audioRoute == AudioRouteType.speaker,
              activeColor: colors.primary,
              onTap: () => _calls.setAudioRoute(
                session.audioRoute == AudioRouteType.speaker
                    ? AudioRouteType.earpiece
                    : AudioRouteType.speaker,
              ),
            ),
            _control(
              label: 'End call',
              icon: Icons.call_end_rounded,
              active: true,
              activeColor: colors.error,
              onTap: () => unawaited(_end()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _control({
    required String label,
    required IconData icon,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onTap,
          radius: 32,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? activeColor.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.16),
              border: Border.all(
                color: active
                    ? activeColor
                    : Colors.white.withValues(alpha: 0.22),
              ),
            ),
            child: Icon(
              icon,
              color: active ? activeColor : Colors.white,
              size: 23,
            ),
          ),
        ),
      ),
    );
  }

  Widget _voiceBackdrop(ChatyCallSession session, AppColors colors) {
    return ColoredBox(
      color: colors.surfaceElevated,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppAvatar(
              initials: session.remoteAvatarInitials ??
                  (session.remoteDisplayName.isEmpty
                      ? 'U'
                      : session.remoteDisplayName[0].toUpperCase()),
              colorHex: session.remoteAvatarColorHex,
              size: 110,
            ),
            const SizedBox(height: 20),
            Text(
              session.remoteDisplayName,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.foreground,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _status(session),
              style: TextStyle(
                color: colors.foregroundSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _status(ChatyCallSession session) {
    switch (session.state) {
      case CallSessionState.idle:
        return 'Preparing…';
      case CallSessionState.initiating:
        return 'Starting…';
      case CallSessionState.ringing:
        return 'Ringing…';
      case CallSessionState.incoming:
        return 'Incoming call';
      case CallSessionState.connecting:
        return 'Connecting…';
      case CallSessionState.connected:
        final seconds = _calls.callDurationSeconds;
        final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
        final remainder = (seconds % 60).toString().padLeft(2, '0');
        return '$minutes:$remainder';
      case CallSessionState.reconnecting:
        return 'Reconnecting…';
      case CallSessionState.declined:
        return 'Declined';
      case CallSessionState.busy:
        return 'Busy';
      case CallSessionState.missed:
        return 'No answer';
      case CallSessionState.ended:
        return 'Ended';
      case CallSessionState.failed:
        return 'Call failed';
    }
  }
}

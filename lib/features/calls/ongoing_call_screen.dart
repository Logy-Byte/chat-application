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

/// Production ongoing voice/video call surface backed by real WebRTC streams.
class OngoingCallScreen extends StatefulWidget {
  final ThemeConfig theme;

  const OngoingCallScreen({super.key, required this.theme});

  @override
  State<OngoingCallScreen> createState() => _OngoingCallScreenState();
}

class _OngoingCallScreenState extends State<OngoingCallScreen> {
  final CallSignalingService _callService = locator<CallSignalingService>();
  final EffectEngine _effectEngine = locator<EffectEngine>();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  bool _controlsVisible = true;
  bool _focusMode = false;
  bool _renderersReady = false;
  bool _bootstrapping = true;
  String? _bootstrapError;
  Timer? _autoHideTimer;
  Offset _localPipOffset = const Offset(20, 80);

  @override
  void initState() {
    super.initState();
    _callService.addListener(_handleCallStateChanged);
    unawaited(_initialize());
    _startAutoHideTimer();
  }

  Future<void> _initialize() async {
    try {
      await Future.wait<void>(<Future<void>>[
        _remoteRenderer.initialize(),
        _localRenderer.initialize(),
      ]);
      if (!mounted) return;
      _renderersReady = true;
      _syncRenderers();

      // Outgoing calls normally have a session by now. Incoming calls reach
      // this screen from the app-level privacy-gated ringing overlay; their
      // authoritative SDP row is created immediately after the caller receives
      // the acceptance, so wait briefly and answer that row here.
      if (_callService.currentSession == null) {
        await _callService.acceptLatestIncomingCall();
      }
      if (!mounted) return;
      _syncRenderers();
      setState(() {
        _bootstrapping = false;
        _bootstrapError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _bootstrapping = false;
        _bootstrapError = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  void _handleCallStateChanged() {
    _syncRenderers();
    final session = _callService.currentSession;
    if (session == null) return;
    if (session.state == CallSessionState.ended ||
        session.state == CallSessionState.declined ||
        session.state == CallSessionState.busy ||
        session.state == CallSessionState.missed ||
        session.state == CallSessionState.failed) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  void _syncRenderers() {
    if (!_renderersReady) return;
    final remote = _callService.remoteStream;
    final local = _callService.localStream;
    if (!identical(_remoteRenderer.srcObject, remote)) {
      _remoteRenderer.srcObject = remote;
    }
    if (!identical(_localRenderer.srcObject, local)) {
      _localRenderer.srcObject = local;
    }
  }

  void _startAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_focusMode) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControlsVisibility() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _startAutoHideTimer();
  }

  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _stateLabel(ChatyCallSession session) {
    switch (session.state) {
      case CallSessionState.initiating:
        return 'Starting…';
      case CallSessionState.ringing:
        return 'Ringing…';
      case CallSessionState.incoming:
        return 'Incoming call';
      case CallSessionState.connecting:
        return 'Connecting…';
      case CallSessionState.reconnecting:
        return 'Reconnecting…';
      case CallSessionState.connected:
        return _formatDuration(_callService.callDurationSeconds);
      case CallSessionState.declined:
        return 'Declined';
      case CallSessionState.busy:
        return 'Busy';
      case CallSessionState.missed:
        return 'No answer';
      case CallSessionState.failed:
        return 'Call failed';
      case CallSessionState.ended:
        return 'Call ended';
      case CallSessionState.idle:
        return 'Preparing…';
    }
  }

  Future<void> _toggleScreenShare() async {
    try {
      if (_callService.isScreenSharing) {
        await _callService.stopScreenShare();
      } else {
        await _callService.startScreenShare();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Bad state: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _endAndClose() async {
    await _callService.endCall();
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _callService.removeListener(_handleCallStateChanged);
    _autoHideTimer?.cancel();
    unawaited(_remoteRenderer.dispose());
    unawaited(_localRenderer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (_bootstrapping && _callService.currentSession == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Securing call…',
                style: TextStyle(color: colors.foreground),
              ),
            ],
          ),
        ),
      );
    }

    if (_bootstrapError != null && _callService.currentSession == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.call_end_rounded, size: 56, color: colors.error),
                  const SizedBox(height: 16),
                  const Text(
                    'Unable to connect the call',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _bootstrapError!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.foregroundSecondary),
                  ),
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

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_callService, _effectEngine]),
      builder: (context, _) {
        _syncRenderers();
        final session = _callService.currentSession;
        if (session == null) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_endAndClose());
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: GestureDetector(
              onTap: _toggleControlsVisibility,
              behavior: HitTestBehavior.opaque,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildRemoteSurface(session, colors),
                  if (session.isVideo && !_focusMode)
                    _buildLocalPreview(session, colors),
                  _buildHeader(session),
                  _buildBottomControls(session, colors),
                  if (!_callService.hasTurnConfigured &&
                      session.state != CallSessionState.connected)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 86,
                      left: 20,
                      right: 20,
                      child: IgnorePointer(
                        child: Text(
                          'Direct connection only — TURN relay is not configured',
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
      },
    );
  }

  Widget _buildRemoteSurface(ChatyCallSession session, AppColors colors) {
    final hasRemoteVideo =
        session.isVideo &&
        _callService.remoteStream != null &&
        _remoteRenderer.srcObject != null;
    if (!hasRemoteVideo) return _buildVoiceCallBackdrop(session, colors);

    return _effectEngine.renderEffect(
      child: ColoredBox(
        color: Colors.black,
        child: RTCVideoView(
          _remoteRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          mirror: false,
        ),
      ),
    );
  }

  Widget _buildLocalPreview(ChatyCallSession session, AppColors colors) {
    return Positioned(
      left: _localPipOffset.dx,
      top: _localPipOffset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          final size = MediaQuery.of(context).size;
          setState(() {
            _localPipOffset = Offset(
              (_localPipOffset.dx + details.delta.dx).clamp(
                16.0,
                size.width - 136.0,
              ),
              (_localPipOffset.dy + details.delta.dy).clamp(
                60.0,
                size.height - 220.0,
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
            border: Border.all(color: colors.border, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(ChatyRadius.lg),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!session.isCameraOff &&
                    _callService.localStream != null &&
                    _localRenderer.srcObject != null)
                  RTCVideoView(
                    _localRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    mirror: session.isFrontCamera && !_callService.isScreenSharing,
                    muted: true,
                  )
                else
                  ColoredBox(
                    color: colors.surfaceSecondary,
                    child: Icon(
                      Icons.videocam_off_rounded,
                      color: colors.foregroundSecondary,
                    ),
                  ),
                if (!_callService.isScreenSharing)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: _callService.switchCamera,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.flip_camera_ios_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                if (_callService.isScreenSharing)
                  const Positioned(
                    left: 6,
                    bottom: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xAA000000),
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        child: Text(
                          'Sharing screen',
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

  Widget _buildHeader(ChatyCallSession session) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      top: _controlsVisible ? 0 : -110,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          ChatySpacing.lg,
          ChatySpacing.xxl,
          ChatySpacing.lg,
          ChatySpacing.md,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.76),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'End call',
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () => unawaited(_endAndClose()),
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
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _stateLabel(session),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: _focusMode ? 'Show controls' : 'Focus mode',
              icon: Icon(
                _focusMode
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                color: Colors.white,
              ),
              onPressed: () => setState(() => _focusMode = !_focusMode),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls(ChatyCallSession session, AppColors colors) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      bottom: _controlsVisible ? 0 : -150,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          ChatySpacing.base,
          ChatySpacing.lg,
          ChatySpacing.base,
          ChatySpacing.xxl,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.86),
              Colors.transparent,
            ],
          ),
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildCallButton(
              tooltip: session.isMuted ? 'Unmute' : 'Mute',
              icon: session.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              isActive: session.isMuted,
              activeColor: colors.error,
              onTap: _callService.toggleMute,
            ),
            if (session.isVideo)
              _buildCallButton(
                tooltip: session.isCameraOff ? 'Turn camera on' : 'Turn camera off',
                icon: session.isCameraOff
                    ? Icons.videocam_off_rounded
                    : Icons.videocam_rounded,
                isActive: session.isCameraOff,
                activeColor: colors.error,
                onTap: _callService.toggleCamera,
              ),
            if (session.isVideo)
              _buildCallButton(
                tooltip: _callService.isScreenSharing
                    ? 'Stop sharing'
                    : 'Share screen',
                icon: _callService.isScreenSharing
                    ? Icons.stop_screen_share_rounded
                    : Icons.screen_share_rounded,
                isActive: _callService.isScreenSharing,
                activeColor: colors.primary,
                onTap: () => unawaited(_toggleScreenShare()),
              ),
            if (session.isVideo)
              _buildCallButton(
                tooltip: 'Video effects',
                icon: Icons.auto_awesome_rounded,
                isActive: _effectEngine.activeEffect.id != 'none',
                activeColor: colors.primary,
                onTap: () => EffectPickerSheet.show(context),
              ),
            _buildCallButton(
              tooltip: session.audioRoute == AudioRouteType.speaker
                  ? 'Use earpiece'
                  : 'Use speaker',
              icon: session.audioRoute == AudioRouteType.speaker
                  ? Icons.volume_up_rounded
                  : Icons.hearing_rounded,
              isActive: session.audioRoute == AudioRouteType.speaker,
              activeColor: colors.primary,
              onTap: () => _callService.setAudioRoute(
                session.audioRoute == AudioRouteType.speaker
                    ? AudioRouteType.earpiece
                    : AudioRouteType.speaker,
              ),
            ),
            _buildCallButton(
              tooltip: 'End call',
              icon: Icons.call_end_rounded,
              isActive: true,
              activeColor: colors.error,
              onTap: () => unawaited(_endAndClose()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceCallBackdrop(ChatyCallSession session, AppColors colors) {
    return Container(
      color: colors.surfaceElevated,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppAvatar(
              initials: session.remoteAvatarInitials ??
                  (session.remoteDisplayName.isNotEmpty
                      ? session.remoteDisplayName.substring(0, 1).toUpperCase()
                      : 'U'),
              colorHex: session.remoteAvatarColorHex,
              size: 110,
            ),
            const SizedBox(height: ChatySpacing.lg),
            Text(
              session.remoteDisplayName,
              style: TextStyle(
                color: colors.foreground,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: ChatySpacing.xs),
            Text(
              _stateLabel(session),
              style: TextStyle(
                color: colors.foregroundSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallButton({
    required String tooltip,
    required IconData icon,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkResponse(
          onTap: onTap,
          radius: 32,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: isActive
                  ? activeColor.withValues(alpha: 0.28)
                  : Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive
                    ? activeColor
                    : Colors.white.withValues(alpha: 0.22),
              ),
            ),
            child: Icon(
              icon,
              color: isActive ? activeColor : Colors.white,
              size: 23,
            ),
          ),
        ),
      ),
    );
  }
}

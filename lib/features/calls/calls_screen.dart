import 'package:flutter/material.dart';

import '../../data/repositories/mock_data_store.dart';
import '../../data/services/call_signaling_service.dart';
import '../../data/services/rich_chat_realtime_service.dart';
import '../../domain/models/other_models.dart';
import '../../domain/models/user_profile.dart';
import '../../injection/locator.dart';
import '../../ui/core/design_system/design_system.dart';
import '../../ui/core/widgets/app_avatar.dart';
import 'ongoing_call_screen.dart';

class CallsScreen extends StatelessWidget {
  final ThemeConfig theme;
  final MockDataStore dataStore;

  const CallsScreen({super.key, required this.theme, required this.dataStore});

  String _formatCallTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$hour:$min';
  }

  UserProfile? _remoteContact(CallRecord call) {
    final myId = dataStore.currentUser.id;
    final remoteId = call.participantIds.firstWhere(
      (id) => id != myId,
      orElse: () => call.callerId == myId ? '' : call.callerId,
    );
    return remoteId.isEmpty ? null : dataStore.getUserById(remoteId);
  }

  Future<void> _redial(
    BuildContext context,
    CallRecord call,
    UserProfile? contact,
  ) async {
    if (contact == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This contact is no longer available.')),
      );
      return;
    }

    final richRealtime = locator<RichChatRealtimeService>();
    final callService = locator<CallSignalingService>();
    final inviteId = 'call_${DateTime.now().microsecondsSinceEpoch}';
    try {
      await richRealtime.placeCall(
        calleeId: contact.id,
        callId: inviteId,
        isVideo: call.type == CallType.video,
      );
      await callService.initiateCall(
        remoteUserId: contact.id,
        remoteDisplayName: contact.displayName,
        remoteAvatarInitials: contact.avatarInitials,
        remoteAvatarColorHex: contact.avatarColorHex,
        isVideo: call.type == CallType.video,
      );
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OngoingCallScreen(theme: theme)),
      );
      final session = callService.currentSession;
      if (session == null || session.callId.startsWith('pending_')) {
        await richRealtime.cancelCall(inviteId);
      }
    } catch (error) {
      try {
        await richRealtime.cancelCall(inviteId);
      } catch (_) {}
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Bad state: ', ''),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final calls = dataStore.calls;
    final colors = context.colors;

    return ChatyScaffold(
      safeAreaTop: true,
      safeAreaBottom: false,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                ChatySpacing.base,
                ChatySpacing.md,
                ChatySpacing.base,
                ChatySpacing.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Calls',
                    style: ChatyTypography.headline(colors.foreground),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ChatySpacing.sm,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(ChatyRadius.full),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_rounded,
                          size: 13,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Secure media',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (calls.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ChatyEmptyState(
                icon: Icons.phone_callback_rounded,
                title: 'No recent calls',
                message:
                    'Voice and video calls with your accepted contacts will appear here.',
                iconColor: colors.primary,
                titleColor: colors.foreground,
                messageColor: colors.foregroundSecondary,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: ChatySpacing.base,
                vertical: ChatySpacing.sm,
              ),
              sliver: SliverToBoxAdapter(
                child: ChatyGroupedSection(
                  children: [
                    for (int i = 0; i < calls.length; i++) ...[
                      Builder(
                        builder: (context) {
                          final call = calls[i];
                          final contact = _remoteContact(call);
                          final isMissed =
                              call.direction == CallDirection.missed;
                          final isVideo = call.type == CallType.video;

                          return ChatyListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: ChatySpacing.base,
                              vertical: ChatySpacing.md,
                            ),
                            leading: AppAvatar(
                              initials: contact?.avatarInitials ?? 'U',
                              colorHex: contact?.avatarColorHex,
                              size: 42,
                            ),
                            title: Text(
                              contact?.displayName ?? 'Unavailable contact',
                              style: TextStyle(
                                color: isMissed
                                    ? colors.error
                                    : colors.foreground,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                letterSpacing: -0.2,
                              ),
                            ),
                            subtitle: Row(
                              children: [
                                Icon(
                                  call.direction == CallDirection.incoming
                                      ? Icons.call_received_rounded
                                      : call.direction == CallDirection.outgoing
                                      ? Icons.call_made_rounded
                                      : Icons.call_missed_rounded,
                                  size: 14,
                                  color: isMissed
                                      ? colors.error
                                      : colors.foregroundSecondary,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    '${_formatCallTime(call.timestamp)} • ${call.durationSeconds > 0 ? '${call.durationSeconds}s' : 'No answer'}',
                                    overflow: TextOverflow.ellipsis,
                                    style: ChatyTypography.caption(
                                      colors.foregroundSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            trailing: ChatyIconButton(
                              icon: isVideo
                                  ? Icons.videocam_rounded
                                  : Icons.call_rounded,
                              size: 38,
                              iconSize: 20,
                              backgroundColor: colors.surfaceSecondary,
                              color: colors.primary,
                              onPressed: contact == null
                                  ? null
                                  : () => _redial(context, call, contact),
                            ),
                            onTap: contact == null
                                ? null
                                : () => _redial(context, call, contact),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }
}

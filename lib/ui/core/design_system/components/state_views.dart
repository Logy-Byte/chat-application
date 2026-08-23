import 'package:flutter/material.dart';

import 'chaty_kit.dart';

/// Canonical centered loading state used by full-screen and large-panel loads.
class ChatyLoadingState extends StatelessWidget {
  final String message;

  const ChatyLoadingState({
    super.key,
    this.message = 'Loading…',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      // The visible label and progress indicator would otherwise merge back
      // into this node and make screen readers announce the same status twice.
      // This state has no interactive descendants, so one explicit live-region
      // label is the correct accessibility representation.
      excludeSemantics: true,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                strokeWidth: 2.5,
                color: scheme.primary,
              ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.68),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Canonical recoverable error state. Error text should be safe for end users;
/// raw server/stack details belong in structured debug logging instead.
class ChatyErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  const ChatyErrorState({
    super.key,
    this.title = 'Something went wrong',
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $message',
      child: ChatyEmptyState(
        icon: Icons.error_outline_rounded,
        title: title,
        message: message,
        iconColor: scheme.error,
        actionLabel: onRetry == null ? null : retryLabel,
        onAction: onRetry,
      ),
    );
  }
}

/// Canonical state for a real runtime permission denial. This is deliberately
/// distinct from an empty data set and from a network/server failure.
class ChatyPermissionDeniedState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onOpenSettings;

  const ChatyPermissionDeniedState({
    super.key,
    this.title = 'Permission required',
    required this.message,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$title. $message',
      child: ChatyEmptyState(
        icon: Icons.lock_outline_rounded,
        title: title,
        message: message,
        actionLabel: onOpenSettings == null ? null : 'Open settings',
        onAction: onOpenSettings,
      ),
    );
  }
}

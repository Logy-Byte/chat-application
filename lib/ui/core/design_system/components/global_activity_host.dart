import 'package:flutter/material.dart';

/// Canonical host for transient, globally visible Chaty activity surfaces.
///
/// The routed application remains the base child. Ongoing activities such as
/// calls, uploads, recording and reconnecting are rendered above it without
/// requiring each feature screen to own a separate overlay implementation.
class ChatyGlobalActivityHost extends StatelessWidget {
  const ChatyGlobalActivityHost({
    super.key,
    required this.child,
    this.primaryActivity,
    this.secondaryActivity,
    this.bottomActivity,
    this.ignoreActivityPointer = false,
  });

  final Widget child;
  final Widget? primaryActivity;
  final Widget? secondaryActivity;
  final Widget? bottomActivity;
  final bool ignoreActivityPointer;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (primaryActivity != null)
          Align(
            alignment: Alignment.topCenter,
            child: _ActivitySlot(
              ignorePointer: ignoreActivityPointer,
              child: primaryActivity!,
            ),
          ),
        if (secondaryActivity != null)
          Align(
            alignment: Alignment.center,
            child: _ActivitySlot(
              ignorePointer: ignoreActivityPointer,
              child: secondaryActivity!,
            ),
          ),
        if (bottomActivity != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: _ActivitySlot(
              ignorePointer: ignoreActivityPointer,
              child: bottomActivity!,
            ),
          ),
      ],
    );
  }
}

class _ActivitySlot extends StatelessWidget {
  const _ActivitySlot({required this.child, required this.ignorePointer});

  final Widget child;
  final bool ignorePointer;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: ignorePointer,
      child: RepaintBoundary(
        child: Semantics(
          container: true,
          liveRegion: true,
          child: child,
        ),
      ),
    );
  }
}

import 'package:chat/ui/core/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('loading state announces its progress message', (tester) async {
    await tester.pumpWidget(
      _host(const ChatyLoadingState(message: 'Loading messages…')),
    );
    expect(find.text('Loading messages…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(ChatyLoadingState)),
      matchesSemantics(
        label: 'Loading messages…',
        isLiveRegion: true,
        hasEnabledState: false,
      ),
    );
  });

  testWidgets('error state exposes a real retry action', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      _host(
        ChatyErrorState(
          message: 'Could not refresh this conversation.',
          onRetry: () => retried = true,
        ),
      ),
    );
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  testWidgets('permission state is distinct from an empty state', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      _host(
        ChatyPermissionDeniedState(
          message: 'Microphone access is required for voice notes.',
          onOpenSettings: () => opened = true,
        ),
      ),
    );
    expect(find.text('Permission required'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    expect(opened, isTrue);
  });
}

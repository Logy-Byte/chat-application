from pathlib import Path

mls = Path('lib/data/services/mls_e2ee_service.dart')
text = mls.read_text(encoding='utf-8')
if "import 'dart:async';" not in text:
    text = text.replace(
        "import 'dart:convert';",
        "import 'dart:async';\nimport 'dart:convert';",
        1,
    )
mls.write_text(text, encoding='utf-8')

detail = Path('lib/features/chats/chat_detail_screen.dart')
text = detail.read_text(encoding='utf-8')
settings_block = """    final messageTextSize = widget.preferencesController.gbDouble(
      'text_size_pick',
      fallback: 15,
    );
    final outgoingBubbleTextColor =
        widget.preferencesController.gbColor('ModChatBubbleText');
    final incomingBubbleTextColor =
        widget.preferencesController.gbColor('ModChatBubbleTextLeft');
    final outgoingTimestampColor =
        widget.preferencesController.gbColor('date_right_color');
    final incomingTimestampColor =
        widget.preferencesController.gbColor('date_left_color');
"""
while settings_block + settings_block in text:
    text = text.replace(settings_block + settings_block, settings_block, 1)

args_block = """            messageTextSize: messageTextSize,
            bubbleTextColor:
                isMine ? outgoingBubbleTextColor : incomingBubbleTextColor,
            timestampColor:
                isMine ? outgoingTimestampColor : incomingTimestampColor,
"""
while args_block + args_block in text:
    text = text.replace(args_block + args_block, args_block, 1)

checks = {
    "final messageTextSize = widget.preferencesController.gbDouble(": 1,
    "widget.preferencesController.gbColor('ModChatBubbleText');": 1,
    "widget.preferencesController.gbColor('ModChatBubbleTextLeft');": 1,
    "widget.preferencesController.gbColor('date_right_color');": 1,
    "widget.preferencesController.gbColor('date_left_color');": 1,
    'messageTextSize: messageTextSize,': 1,
}
for marker, expected in checks.items():
    actual = text.count(marker)
    if actual != expected:
        raise SystemExit(
            f'Phase 5 runtime consumer count mismatch for {marker}: '
            f'expected {expected}, got {actual}'
        )

detail.write_text(text, encoding='utf-8')

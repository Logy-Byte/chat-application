import 'package:flutter_test/flutter_test.dart';
import 'package:chat/ui/core/commands/chat_command_parser.dart';

void main() {
  group('Phase 5 chat command contract', () {
    test('/task preserves the assignment title argument', () {
      final parsed = ChatCommandParser.parse('/task Prepare launch checklist');
      expect(parsed.type, ChatCommandType.task);
      expect(parsed.isCommand, isTrue);
      expect(parsed.argument, 'Prepare launch checklist');
    });

    test('/task is case-insensitive and trims surrounding whitespace', () {
      final parsed = ChatCommandParser.parse('  /TaSk   Review security  ');
      expect(parsed.type, ChatCommandType.task);
      expect(parsed.argument, 'Review security');
    });

    test('ordinary slash-like text does not become a known task command', () {
      final parsed = ChatCommandParser.parse('please /task later');
      expect(parsed.type, ChatCommandType.unknown);
      expect(parsed.isCommand, isFalse);
    });

    test('unknown slash commands remain fail-safe', () {
      final parsed = ChatCommandParser.parse('/delete-everything now');
      expect(parsed.type, ChatCommandType.unknown);
      expect(parsed.argument, 'now');
    });
  });
}

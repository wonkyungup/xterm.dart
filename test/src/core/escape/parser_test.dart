import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

@GenerateNiceMocks([MockSpec<EscapeHandler>()])
import 'parser_test.mocks.dart';

void main() {
  group('EscapeParser', () {
    test('can parse window manipulation', () {
      final parser = EscapeParser(MockEscapeHandler());
      parser.write('\x1b[8;24;80t');
      verify(parser.handler.resize(80, 24));
    });

    test('ignores prefixed m (XTMODKEYS), not SGR', () {
      final parser = EscapeParser(MockEscapeHandler());
      parser.write('\x1b[>4;2m');
      parser.write('\x1b[?4m');
      verifyNever(parser.handler.setCursorUnderline());
      verifyNever(parser.handler.setCursorFaint());
    });

    test('still parses plain SGR underline', () {
      final parser = EscapeParser(MockEscapeHandler());
      parser.write('\x1b[4m');
      verify(parser.handler.setCursorUnderline());
    });
  });

  group('Terminal', () {
    test('text after vim XTMODKEYS is not underlined or faint', () {
      final terminal = Terminal();
      terminal.write('\x1b[>4;2mabc');
      final attrs = terminal.buffer.lines[0].getAttributes(0);
      expect(attrs & CellAttr.underline, 0);
      expect(attrs & CellAttr.faint, 0);
    });
  });
}

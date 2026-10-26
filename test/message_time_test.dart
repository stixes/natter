import 'package:flutter_test/flutter_test.dart';
import 'package:natter/ui/message_time.dart';

void main() {
  group('formatMessageTime', () {
    test('zero-pads a morning time', () {
      expect(formatMessageTime(DateTime(2026, 10, 25, 9, 5)), '09:05');
    });

    test('keeps the 24-hour clock in the afternoon', () {
      expect(formatMessageTime(DateTime(2026, 10, 25, 13, 7)), '13:07');
    });

    test('formats midnight', () {
      expect(formatMessageTime(DateTime(2026, 10, 25, 0, 5)), '00:05');
    });

    test('drops seconds, AM/PM, and the date', () {
      expect(formatMessageTime(DateTime(2026, 10, 25, 23, 59, 59)), '23:59');
    });
  });
}

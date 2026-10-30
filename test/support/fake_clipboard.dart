import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A clipboard a widget test can read back.
///
/// `Clipboard` is a static gateway onto a platform channel, so a test cannot
/// see what a tap put on the clipboard unless that channel is mocked. This
/// stands in for the platform side: it keeps the last text written and serves
/// it back, so an assertion reads the clipboard through `Clipboard.getData` -
/// the same API the app writes it with.
class FakeClipboard {
  FakeClipboard(this.tester);

  final WidgetTester tester;
  String? _text;
  int _writes = 0;

  /// Installs the platform-side handler; call it before pumping the widget
  /// that writes the clipboard.
  void install() {
    TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              _text =
                  (call.arguments as Map<Object?, Object?>)['text'] as String?;
              _writes++;
            case 'Clipboard.getData':
              final text = _text;
              return text == null ? null : <String, Object?>{'text': text};
            case 'Clipboard.hasStrings':
              return <String, Object?>{'value': _text != null};
          }
          return null;
        });
  }

  /// What sits on the clipboard now, read the way the app writes it.
  Future<String?> read() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  /// How many writes the app has made, so a test can prove a control that was
  /// tapped writes again rather than only swapping its icon.
  int get writes => _writes;
}

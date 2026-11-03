// The example must compile off the web too: parity hooks that use dart:js_interop
// sit behind a conditional import (lib/parity/parity_hooks*.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter_example/main.dart' as app;

void main() {
  test('main.dart compiles on the native VM', () => expect(app.main, isNotNull));
}

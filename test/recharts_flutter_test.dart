import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/recharts_flutter_platform_interface.dart';
import 'package:recharts_flutter/recharts_flutter_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockRechartsFlutterPlatform
    with MockPlatformInterfaceMixin
    implements RechartsFlutterPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final RechartsFlutterPlatform initialPlatform = RechartsFlutterPlatform.instance;

  test('$MethodChannelRechartsFlutter is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelRechartsFlutter>());
  });

  test('getPlatformVersion', () async {
    RechartsFlutter rechartsFlutterPlugin = RechartsFlutter();
    MockRechartsFlutterPlatform fakePlatform = MockRechartsFlutterPlatform();
    RechartsFlutterPlatform.instance = fakePlatform;

    expect(await rechartsFlutterPlugin.getPlatformVersion(), '42');
  });
}

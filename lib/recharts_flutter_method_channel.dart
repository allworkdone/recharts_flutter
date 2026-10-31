import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'recharts_flutter_platform_interface.dart';

/// An implementation of [RechartsFlutterPlatform] that uses method channels.
class MethodChannelRechartsFlutter extends RechartsFlutterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('recharts_flutter');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'recharts_flutter_method_channel.dart';

abstract class RechartsFlutterPlatform extends PlatformInterface {
  /// Constructs a RechartsFlutterPlatform.
  RechartsFlutterPlatform() : super(token: _token);

  static final Object _token = Object();

  static RechartsFlutterPlatform _instance = MethodChannelRechartsFlutter();

  /// The default instance of [RechartsFlutterPlatform] to use.
  ///
  /// Defaults to [MethodChannelRechartsFlutter].
  static RechartsFlutterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [RechartsFlutterPlatform] when
  /// they register themselves.
  static set instance(RechartsFlutterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}

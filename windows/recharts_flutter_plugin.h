#ifndef FLUTTER_PLUGIN_RECHARTS_FLUTTER_PLUGIN_H_
#define FLUTTER_PLUGIN_RECHARTS_FLUTTER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace recharts_flutter {

class RechartsFlutterPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  RechartsFlutterPlugin();

  virtual ~RechartsFlutterPlugin();

  // Disallow copy and assign.
  RechartsFlutterPlugin(const RechartsFlutterPlugin&) = delete;
  RechartsFlutterPlugin& operator=(const RechartsFlutterPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace recharts_flutter

#endif  // FLUTTER_PLUGIN_RECHARTS_FLUTTER_PLUGIN_H_

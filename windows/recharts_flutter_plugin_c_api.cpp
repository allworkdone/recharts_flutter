#include "include/recharts_flutter/recharts_flutter_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "recharts_flutter_plugin.h"

void RechartsFlutterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  recharts_flutter::RechartsFlutterPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

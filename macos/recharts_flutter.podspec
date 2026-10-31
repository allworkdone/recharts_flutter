#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint recharts_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'recharts_flutter'
  s.version          = '0.0.1'
  s.summary          = 'Recharts ported to Flutter: Line and Bar charts with Recharts-exact layout, animation and interaction.'
  s.description      = <<-DESC
Recharts ported to Flutter: Line and Bar charts with Recharts-exact layout, animation and interaction.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  s.source           = { :path => '.' }
  s.source_files = 'recharts_flutter/Sources/recharts_flutter/**/*'

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'recharts_flutter_privacy' => ['recharts_flutter/Sources/recharts_flutter/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end

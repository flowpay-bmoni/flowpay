#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint bmoni_embedded_sdk.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'bmoni_embedded_sdk'
  s.version          = '0.0.2'
  s.summary          = 'Bmoni Embedded SDK for Flutter.'
  s.description      = <<-DESC
Bmoni Embedded SDK for Flutter — Ethereum wallet provisioning and signing
backed by the Secure Enclave (iOS) and Android Keystore (Android).
                       DESC
  s.homepage         = 'https://github.com/bkey-inc/bmoni-embedded-sdk-flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Bkey Inc.' => 'bright@bkey.me' }
  s.source           = { :path => '.' }
  s.source_files = 'bmoni_embedded_sdk/Sources/bmoni_embedded_sdk/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Download the published BMONISigner xcframework so CocoaPods consumers
  # get the same binary that the Swift Package resolves at build time.
  bmoni_signer_url = 'https://internal-asset-distribution.s3.eu-north-1.amazonaws.com/BMONISigner.1.0.0.xcframework.zip'
  bmoni_signer_dir = 'Frameworks/BMONISigner'
  s.prepare_command = <<-CMD
    set -e
    if [ ! -d "#{bmoni_signer_dir}/BMONISigner.xcframework" ]; then
      mkdir -p "#{bmoni_signer_dir}"
      curl -L "#{bmoni_signer_url}" -o "#{bmoni_signer_dir}/BMONISigner.xcframework.zip"
      unzip -o "#{bmoni_signer_dir}/BMONISigner.xcframework.zip" -d "#{bmoni_signer_dir}"
      rm "#{bmoni_signer_dir}/BMONISigner.xcframework.zip"
    fi
  CMD
  s.vendored_frameworks = "#{bmoni_signer_dir}/BMONISigner.xcframework"
  s.preserve_paths = "#{bmoni_signer_dir}/BMONISigner.xcframework"

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'bmoni_embedded_sdk_privacy' => ['bmoni_embedded_sdk/Sources/bmoni_embedded_sdk/PrivacyInfo.xcprivacy']}
end

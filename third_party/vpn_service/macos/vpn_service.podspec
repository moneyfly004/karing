Pod::Spec.new do |s|
  s.name             = 'vpn_service'
  s.version          = '0.1.0'
  s.summary          = 'Compatibility VPN bridge for Karing.'
  s.description      = <<-DESC
Compatibility VPN bridge for Karing.
                       DESC
  s.homepage         = 'https://new.moneyfly.top'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'MoneyFly' => 'support@moneyfly.top' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.frameworks       = 'AppKit', 'NetworkExtension', 'SystemExtensions'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end

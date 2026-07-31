# TMAP SDK (앱 연동 Tapi + 지도) — 공식 배포 프레임워크를 로컬 pod 으로 물린다.
# 디바이스/시뮬레이터 프레임워크를 xcframework 로 합쳐 두었다.
Pod::Spec.new do |s|
  s.name             = 'TMapSDK'
  s.version          = '2.22'
  s.summary          = 'TMAP SDK for iOS'
  s.description      = 'TMAP 앱 연동(Tapi) — 경유지 포함 길안내 호출'
  s.homepage         = 'https://tmapapi.tmapmobility.com'
  s.license          = { :type => 'Commercial' }
  s.author           = { 'SK Telecom' => 'tmapapi@sktelecom.com' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '12.0'
  s.vendored_frameworks = 'TMapSDK.xcframework'
end

import Flutter
import UIKit
import google_mobile_ads

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // AdMob 네이티브 광고 — Flutter 측 factoryId="stationCard" 매칭.
    // 앱 카드 디자인으로 통합 렌더링.
    let factory = StationCardNativeAdFactory()
    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      self, factoryId: "stationCard", nativeAdFactory: factory)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    FLTGoogleMobileAdsPlugin.unregisterNativeAdFactory(self, factoryId: "stationCard")
    super.applicationWillTerminate(application)
  }
}

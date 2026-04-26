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

    // AdMob 네이티브 광고 — 두 layout 분리:
    //  - stationCardTop  : 강조형 (홈 상단)
    //  - stationCardList : 인라인 (리스트 3번째)
    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      self, factoryId: "stationCardTop",
      nativeAdFactory: StationCardTopNativeAdFactory())
    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      self, factoryId: "stationCardList",
      nativeAdFactory: StationCardListNativeAdFactory())
    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      self, factoryId: "stationCardListEv",
      nativeAdFactory: StationCardListEvNativeAdFactory())

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    FLTGoogleMobileAdsPlugin.unregisterNativeAdFactory(self, factoryId: "stationCardTop")
    FLTGoogleMobileAdsPlugin.unregisterNativeAdFactory(self, factoryId: "stationCardList")
    FLTGoogleMobileAdsPlugin.unregisterNativeAdFactory(self, factoryId: "stationCardListEv")
    super.applicationWillTerminate(application)
  }
}

import Flutter
import UIKit
import google_mobile_ads
import TMapSDK

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

    // TMAP 앱 연동(Tapi) — 경유지 포함 길안내.
    // URL 스킴(tmap://route)은 목적지 하나만 되고 경유지는 무시되므로 공식 SDK 를 쓴다.
    if let controller = window?.rootViewController as? FlutterViewController {
      FlutterMethodChannel(
        name: "com.dksw.charge/tmap",
        binaryMessenger: controller.binaryMessenger
      ).setMethodCallHandler { call, result in
        switch call.method {
        case "invokeRoute":
          let args = call.arguments as? [String: Any] ?? [:]
          let appKey = args["appKey"] as? String ?? ""
          let info = (args["routeInfo"] as? [String: Any] ?? [:])
            .mapValues { "\($0)" }
          TMapApi.setSKTMapAuthenticationWithDelegate(nil, apiKey: appKey)
          result(TMapApi.invokeRoute(info))
        case "isInstalled":
          result(UIApplication.shared.canOpenURL(URL(string: "tmap://")!))
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    FLTGoogleMobileAdsPlugin.unregisterNativeAdFactory(self, factoryId: "stationCardTop")
    FLTGoogleMobileAdsPlugin.unregisterNativeAdFactory(self, factoryId: "stationCardList")
    FLTGoogleMobileAdsPlugin.unregisterNativeAdFactory(self, factoryId: "stationCardListEv")
    super.applicationWillTerminate(application)
  }
}

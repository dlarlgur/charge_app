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
          // 인증은 비동기다. 끝나기 전에 invokeRoute 를 부르면 그냥 false 가 온다.
          TmapAuth.shared.authenticate(appKey) { ok, err in
            guard ok else {
              result(["ok": false, "reason": "auth:\(err ?? "")"])
              return
            }
            guard TMapApi.isTmapApplicationInstalled() else {
              result(["ok": false, "reason": "not_installed"])
              return
            }
            let done = TMapApi.invokeRoute(info)
            result(["ok": done, "reason": done ? nil : "invoke_false"])
          }
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

/// TMAP Tapi 앱키 인증.
///
/// `setSKTMapAuthenticationWithDelegate` 는 서버 왕복이라 비동기다. 인증이 끝나기 전에
/// `invokeRoute` 를 부르면 SDK 가 조용히 false 를 돌려주고, 앱은 경유지 없는 URL 스킴으로
/// 떨어진다. 그래서 콜백을 기다렸다가 실행하고, 한 번 성공하면 그대로 캐시한다.
final class TmapAuth: NSObject, TMapTapiDelegate {
  static let shared = TmapAuth()

  private var authed = false
  private var waiting: [(Bool, String?) -> Void] = []
  private var inFlight = false

  func authenticate(_ appKey: String, _ done: @escaping (Bool, String?) -> Void) {
    if authed { done(true, nil); return }
    waiting.append(done)
    guard !inFlight else { return }
    inFlight = true
    TMapApi.setSKTMapAuthenticationWithDelegate(self, apiKey: appKey)
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
      self?.settle(false, "auth timeout")
    }
  }

  private func settle(_ ok: Bool, _ err: String?) {
    guard inFlight else { return }
    inFlight = false
    authed = ok
    let pending = waiting
    waiting = []
    pending.forEach { $0(ok, err) }
  }

  func SKTMapApikeySucceed() {
    DispatchQueue.main.async { self.settle(true, nil) }
  }

  func SKTMapApikeyFailed(error: NSError?) {
    DispatchQueue.main.async {
      self.settle(false, error?.localizedDescription ?? "auth failed")
    }
  }
}

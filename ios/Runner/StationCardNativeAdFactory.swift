import Foundation
import GoogleMobileAds
import google_mobile_ads

/// AdMob 네이티브 광고를 앱 카드(GasStationCard / EvStationCard) 디자인으로 렌더링.
/// Flutter 측 `factoryId: "stationCard"` 와 매칭.
///
/// xib 대신 코드로 GADNativeAdView 를 구성. 같은 결과지만 유지보수 단순.
class StationCardNativeAdFactory: NSObject, FLTNativeAdFactory {

    func createNativeAd(_ nativeAd: GADNativeAd,
                        customOptions: [AnyHashable: Any]? = nil) -> GADNativeAdView? {
        let isDark = (UITraitCollection.current.userInterfaceStyle == .dark)

        // ─── 컬러 (Flutter AppColors 동일) ─────────────────────────────
        let cardBg = isDark
            ? UIColor(red: 0x12/255, green: 0x14/255, blue: 0x1A/255, alpha: 1.0)
            : UIColor.white
        let border = isDark
            ? UIColor.white.withAlphaComponent(0.14)
            : UIColor(red: 0xE8/255, green: 0xEC/255, blue: 0xF0/255, alpha: 1.0)
        let primary = isDark
            ? UIColor(red: 0xF1/255, green: 0xF5/255, blue: 0xF9/255, alpha: 1.0)
            : UIColor(red: 0x0F/255, green: 0x17/255, blue: 0x2A/255, alpha: 1.0)
        let secondary = isDark
            ? UIColor(red: 0x94/255, green: 0xA3/255, blue: 0xB8/255, alpha: 1.0)
            : UIColor(red: 0x64/255, green: 0x74/255, blue: 0x8B/255, alpha: 1.0)
        let brandBlue = UIColor(red: 0x3B/255, green: 0x82/255, blue: 0xF6/255, alpha: 1.0)
        let labelBg = isDark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor(red: 0xE8/255, green: 0xEC/255, blue: 0xF0/255, alpha: 1.0)

        // ─── Root NativeAdView ────────────────────────────────────────
        let adView = GADNativeAdView(frame: .zero)
        adView.translatesAutoresizingMaskIntoConstraints = false
        adView.backgroundColor = cardBg
        adView.layer.cornerRadius = 14
        adView.layer.borderWidth = 0.5
        adView.layer.borderColor = border.cgColor
        adView.layer.masksToBounds = true

        // ─── Icon ─────────────────────────────────────────────────────
        let iconWrap = UIView()
        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.backgroundColor = brandBlue.withAlphaComponent(0.10)
        iconWrap.layer.cornerRadius = 10

        let icon = UIImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFit
        iconWrap.addSubview(icon)

        // ─── AD label + headline row ──────────────────────────────────
        let adLabel = UILabel()
        adLabel.translatesAutoresizingMaskIntoConstraints = false
        adLabel.text = "AD"
        adLabel.font = UIFont.systemFont(ofSize: 9, weight: .heavy)
        adLabel.textColor = secondary
        adLabel.textAlignment = .center
        adLabel.backgroundColor = labelBg
        adLabel.layer.cornerRadius = 3
        adLabel.layer.masksToBounds = true
        let adLabelWrap = UIView()
        adLabelWrap.translatesAutoresizingMaskIntoConstraints = false
        adLabelWrap.addSubview(adLabel)

        let headline = UILabel()
        headline.translatesAutoresizingMaskIntoConstraints = false
        headline.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        headline.textColor = primary
        headline.numberOfLines = 1
        headline.lineBreakMode = .byTruncatingTail

        let topRow = UIStackView(arrangedSubviews: [adLabelWrap, headline])
        topRow.translatesAutoresizingMaskIntoConstraints = false
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = 6

        // ─── Body ─────────────────────────────────────────────────────
        let body = UILabel()
        body.translatesAutoresizingMaskIntoConstraints = false
        body.font = UIFont.systemFont(ofSize: 11, weight: .regular)
        body.textColor = secondary
        body.numberOfLines = 1
        body.lineBreakMode = .byTruncatingTail

        let middleStack = UIStackView(arrangedSubviews: [topRow, body])
        middleStack.translatesAutoresizingMaskIntoConstraints = false
        middleStack.axis = .vertical
        middleStack.alignment = .leading
        middleStack.spacing = 3

        // ─── CTA pill button ──────────────────────────────────────────
        let cta = UIButton(type: .system)
        cta.translatesAutoresizingMaskIntoConstraints = false
        cta.backgroundColor = brandBlue
        cta.setTitleColor(.white, for: .normal)
        cta.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        cta.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        cta.layer.cornerRadius = 16
        cta.layer.masksToBounds = true
        cta.isUserInteractionEnabled = false  // SDK 가 클릭 처리

        // ─── Layout ───────────────────────────────────────────────────
        adView.addSubview(iconWrap)
        adView.addSubview(middleStack)
        adView.addSubview(cta)

        NSLayoutConstraint.activate([
            // Icon
            iconWrap.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 14),
            iconWrap.centerYAnchor.constraint(equalTo: adView.centerYAnchor),
            iconWrap.widthAnchor.constraint(equalToConstant: 44),
            iconWrap.heightAnchor.constraint(equalToConstant: 44),
            icon.topAnchor.constraint(equalTo: iconWrap.topAnchor, constant: 6),
            icon.leadingAnchor.constraint(equalTo: iconWrap.leadingAnchor, constant: 6),
            icon.trailingAnchor.constraint(equalTo: iconWrap.trailingAnchor, constant: -6),
            icon.bottomAnchor.constraint(equalTo: iconWrap.bottomAnchor, constant: -6),

            // Middle stack
            middleStack.leadingAnchor.constraint(equalTo: iconWrap.trailingAnchor, constant: 12),
            middleStack.trailingAnchor.constraint(equalTo: cta.leadingAnchor, constant: -8),
            middleStack.centerYAnchor.constraint(equalTo: adView.centerYAnchor),
            adView.heightAnchor.constraint(greaterThanOrEqualTo: middleStack.heightAnchor, constant: 24),

            // AD label sizing
            adLabel.topAnchor.constraint(equalTo: adLabelWrap.topAnchor, constant: 1),
            adLabel.bottomAnchor.constraint(equalTo: adLabelWrap.bottomAnchor, constant: -1),
            adLabel.leadingAnchor.constraint(equalTo: adLabelWrap.leadingAnchor, constant: 5),
            adLabel.trailingAnchor.constraint(equalTo: adLabelWrap.trailingAnchor, constant: -5),

            // CTA
            cta.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -14),
            cta.centerYAnchor.constraint(equalTo: adView.centerYAnchor),
            cta.heightAnchor.constraint(equalToConstant: 32),

            // Card height
            adView.heightAnchor.constraint(greaterThanOrEqualToConstant: 76),
        ])

        // ─── Bind ad data ─────────────────────────────────────────────
        headline.text = nativeAd.headline
        adView.headlineView = headline

        if let bodyText = nativeAd.body, !bodyText.isEmpty {
            body.text = bodyText
            adView.bodyView = body
        } else if let advertiser = nativeAd.advertiser, !advertiser.isEmpty {
            body.text = advertiser
            adView.advertiserView = body
        } else {
            body.isHidden = true
        }

        if let ctaText = nativeAd.callToAction {
            cta.setTitle(ctaText, for: .normal)
            adView.callToActionView = cta
        } else {
            cta.isHidden = true
        }

        if let iconImg = nativeAd.icon?.image {
            icon.image = iconImg
            adView.iconView = icon
        } else if let firstImg = nativeAd.images?.first?.image {
            icon.image = firstImg
            adView.iconView = icon
        } else {
            iconWrap.isHidden = true
        }

        adView.nativeAd = nativeAd
        return adView
    }
}

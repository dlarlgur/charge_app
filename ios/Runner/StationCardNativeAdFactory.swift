import Foundation
import GoogleMobileAds
import google_mobile_ads

/// 공통 컬러 — Flutter AppColors 와 동일.
private struct AdColors {
    let cardBg: UIColor
    let border: UIColor
    let primary: UIColor
    let secondary: UIColor
    let labelBg: UIColor
    let brandBlue: UIColor

    static func current() -> AdColors {
        let isDark = (UITraitCollection.current.userInterfaceStyle == .dark)
        return AdColors(
            cardBg: isDark
                ? UIColor(red: 0x12/255, green: 0x14/255, blue: 0x1A/255, alpha: 1.0)
                : .white,
            border: isDark
                ? UIColor.white.withAlphaComponent(0.14)
                : UIColor(red: 0xE8/255, green: 0xEC/255, blue: 0xF0/255, alpha: 1.0),
            primary: isDark
                ? UIColor(red: 0xF1/255, green: 0xF5/255, blue: 0xF9/255, alpha: 1.0)
                : UIColor(red: 0x0F/255, green: 0x17/255, blue: 0x2A/255, alpha: 1.0),
            secondary: isDark
                ? UIColor(red: 0x94/255, green: 0xA3/255, blue: 0xB8/255, alpha: 1.0)
                : UIColor(red: 0x64/255, green: 0x74/255, blue: 0x8B/255, alpha: 1.0),
            labelBg: isDark
                ? UIColor.white.withAlphaComponent(0.08)
                : UIColor(red: 0xE8/255, green: 0xEC/255, blue: 0xF0/255, alpha: 1.0),
            brandBlue: UIColor(red: 0x3B/255, green: 0x82/255, blue: 0xF6/255, alpha: 1.0)
        )
    }
}

private func makeAdLabel(text: String = "AD", color: AdColors) -> UILabel {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.text = text
    label.font = UIFont.systemFont(ofSize: 9, weight: .heavy)
    label.textColor = color.secondary
    label.textAlignment = .center
    label.backgroundColor = color.labelBg
    label.layer.cornerRadius = 3
    label.layer.masksToBounds = true
    return label
}

private func makeCtaButton(color: AdColors) -> UIButton {
    let cta = UIButton(type: .system)
    cta.translatesAutoresizingMaskIntoConstraints = false
    cta.backgroundColor = color.brandBlue
    cta.setTitleColor(.white, for: .normal)
    cta.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .bold)
    cta.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
    cta.layer.cornerRadius = 14
    cta.layer.masksToBounds = true
    cta.isUserInteractionEnabled = false
    return cta
}

private func bind(_ adView: GADNativeAdView, _ nativeAd: GADNativeAd,
                  headline: UILabel, body: UILabel, cta: UIButton, icon: UIImageView) {
    headline.text = nativeAd.headline
    adView.headlineView = headline

    if let bodyText = nativeAd.body, !bodyText.isEmpty {
        body.text = bodyText
        adView.bodyView = body
        body.isHidden = false
    } else if let advertiser = nativeAd.advertiser, !advertiser.isEmpty {
        body.text = advertiser
        adView.advertiserView = body
        body.isHidden = false
    } else {
        body.isHidden = true
    }

    if let ctaText = nativeAd.callToAction {
        cta.setTitle(ctaText, for: .normal)
        adView.callToActionView = cta
        cta.isHidden = false
    } else {
        cta.isHidden = true
    }

    if let iconImg = nativeAd.icon?.image {
        icon.image = iconImg
        adView.iconView = icon
        icon.isHidden = false
    } else if let firstImg = nativeAd.images?.first?.image {
        icon.image = firstImg
        adView.iconView = icon
        icon.isHidden = false
    } else {
        icon.isHidden = true
    }

    adView.nativeAd = nativeAd
}

// ─── Top 배너 (강조형, ~108dp) ──────────────────────────────────────────
class StationCardTopNativeAdFactory: NSObject, FLTNativeAdFactory {
    func createNativeAd(_ nativeAd: GADNativeAd,
                        customOptions: [AnyHashable: Any]? = nil) -> GADNativeAdView? {
        let c = AdColors.current()

        let adView = GADNativeAdView(frame: .zero)
        adView.translatesAutoresizingMaskIntoConstraints = false
        adView.backgroundColor = c.cardBg
        adView.layer.cornerRadius = 14
        adView.layer.borderWidth = 0.5
        adView.layer.borderColor = c.border.cgColor
        adView.layer.masksToBounds = true

        // 큰 이미지 80x80
        let icon = UIImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFill
        icon.backgroundColor = c.brandBlue.withAlphaComponent(0.10)
        icon.layer.cornerRadius = 10
        icon.layer.masksToBounds = true

        let adLabel = makeAdLabel(color: c)
        let adLabelWrap = UIView()
        adLabelWrap.translatesAutoresizingMaskIntoConstraints = false
        adLabelWrap.addSubview(adLabel)

        let headline = UILabel()
        headline.translatesAutoresizingMaskIntoConstraints = false
        headline.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        headline.textColor = c.primary
        headline.numberOfLines = 1
        headline.lineBreakMode = .byTruncatingTail

        let body = UILabel()
        body.translatesAutoresizingMaskIntoConstraints = false
        body.font = UIFont.systemFont(ofSize: 11.5, weight: .regular)
        body.textColor = c.secondary
        body.numberOfLines = 2
        body.lineBreakMode = .byTruncatingTail

        let cta = makeCtaButton(color: c)
        let ctaContainer = UIView()
        ctaContainer.translatesAutoresizingMaskIntoConstraints = false
        ctaContainer.addSubview(cta)

        let rightStack = UIStackView(arrangedSubviews: [adLabelWrap, headline, body, ctaContainer])
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        rightStack.axis = .vertical
        rightStack.spacing = 4
        rightStack.alignment = .leading
        rightStack.setCustomSpacing(6, after: body)

        adView.addSubview(icon)
        adView.addSubview(rightStack)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: adView.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 80),
            icon.heightAnchor.constraint(equalToConstant: 80),

            rightStack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            rightStack.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -14),
            rightStack.centerYAnchor.constraint(equalTo: adView.centerYAnchor),

            adLabel.topAnchor.constraint(equalTo: adLabelWrap.topAnchor, constant: 1),
            adLabel.bottomAnchor.constraint(equalTo: adLabelWrap.bottomAnchor, constant: -1),
            adLabel.leadingAnchor.constraint(equalTo: adLabelWrap.leadingAnchor, constant: 5),
            adLabel.trailingAnchor.constraint(equalTo: adLabelWrap.trailingAnchor, constant: -5),

            cta.heightAnchor.constraint(equalToConstant: 28),
            cta.trailingAnchor.constraint(equalTo: ctaContainer.trailingAnchor),
            cta.topAnchor.constraint(equalTo: ctaContainer.topAnchor),
            cta.bottomAnchor.constraint(equalTo: ctaContainer.bottomAnchor),

            ctaContainer.widthAnchor.constraint(equalTo: rightStack.widthAnchor),

            adView.heightAnchor.constraint(greaterThanOrEqualToConstant: 108),
        ])

        bind(adView, nativeAd, headline: headline, body: body, cta: cta, icon: icon)
        return adView
    }
}

// ─── List 인라인 (스테이션 카드와 동일, ~64dp) ─────────────────────────
class StationCardListNativeAdFactory: NSObject, FLTNativeAdFactory {
    func createNativeAd(_ nativeAd: GADNativeAd,
                        customOptions: [AnyHashable: Any]? = nil) -> GADNativeAdView? {
        let c = AdColors.current()

        let adView = GADNativeAdView(frame: .zero)
        adView.translatesAutoresizingMaskIntoConstraints = false
        adView.backgroundColor = c.cardBg
        adView.layer.cornerRadius = 14
        adView.layer.borderWidth = 0.5
        adView.layer.borderColor = c.border.cgColor
        adView.layer.masksToBounds = true

        // 작은 아이콘 38x38
        let icon = UIImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFill
        icon.backgroundColor = c.brandBlue.withAlphaComponent(0.10)
        icon.layer.cornerRadius = 10
        icon.layer.masksToBounds = true

        let adLabel = makeAdLabel(color: c)
        let adLabelWrap = UIView()
        adLabelWrap.translatesAutoresizingMaskIntoConstraints = false
        adLabelWrap.addSubview(adLabel)

        let headline = UILabel()
        headline.translatesAutoresizingMaskIntoConstraints = false
        headline.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        headline.textColor = c.primary
        headline.numberOfLines = 1
        headline.lineBreakMode = .byTruncatingTail

        let topRow = UIStackView(arrangedSubviews: [adLabelWrap, headline])
        topRow.translatesAutoresizingMaskIntoConstraints = false
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = 6

        let body = UILabel()
        body.translatesAutoresizingMaskIntoConstraints = false
        body.font = UIFont.systemFont(ofSize: 11, weight: .regular)
        body.textColor = c.secondary
        body.numberOfLines = 1
        body.lineBreakMode = .byTruncatingTail

        let middleStack = UIStackView(arrangedSubviews: [topRow, body])
        middleStack.translatesAutoresizingMaskIntoConstraints = false
        middleStack.axis = .vertical
        middleStack.alignment = .leading
        middleStack.spacing = 3

        let cta = makeCtaButton(color: c)
        cta.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        cta.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)

        adView.addSubview(icon)
        adView.addSubview(middleStack)
        adView.addSubview(cta)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: adView.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 38),
            icon.heightAnchor.constraint(equalToConstant: 38),

            middleStack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            middleStack.trailingAnchor.constraint(equalTo: cta.leadingAnchor, constant: -8),
            middleStack.centerYAnchor.constraint(equalTo: adView.centerYAnchor),

            adLabel.topAnchor.constraint(equalTo: adLabelWrap.topAnchor, constant: 1),
            adLabel.bottomAnchor.constraint(equalTo: adLabelWrap.bottomAnchor, constant: -1),
            adLabel.leadingAnchor.constraint(equalTo: adLabelWrap.leadingAnchor, constant: 5),
            adLabel.trailingAnchor.constraint(equalTo: adLabelWrap.trailingAnchor, constant: -5),

            cta.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -14),
            cta.centerYAnchor.constraint(equalTo: adView.centerYAnchor),
            cta.heightAnchor.constraint(equalToConstant: 28),

            adView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
        ])

        bind(adView, nativeAd, headline: headline, body: body, cta: cta, icon: icon)
        return adView
    }
}

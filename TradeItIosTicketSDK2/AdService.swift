import UIKit

@objc public protocol AdService {
    func populate(
        adContainer: UIView,
        rootViewController: UIViewController,
        pageType: TradeItAdPageType,
        position: TradeItAdPosition,
        broker: String?,
        symbol: String?,
        instrumentType: String?,
        trackPageViewAsPageType: Bool
    )
}

@objc public enum TradeItAdPageType: Int {
    case homepage
    case watchlist
    case trading
    case portfolio
    case confirmation
    case welcome
    case link
    case general
    case brokerList
    case preview

    // Woe is me - Obj-C backwards compatibility
    @objc public static func labelFor(_ pageType: TradeItAdPageType) -> String {
        switch(pageType) {
        case .homepage: return "homepage"
        case .confirmation: return "confirmation"
        case .general: return "general"
        case .link: return "link"
        case .portfolio: return "portfolio"
        case .trading: return "trading"
        case .watchlist: return "watchlist"
        case .welcome: return "welcome"
        case .brokerList: return "brokerList"
        case .preview: return "preview"
        }
    }
}

@objc public enum TradeItAdPosition: Int {
    case top
    case bottom
    case content1
    case content2

    // Woe is me - Obj-C backwards compatibility
    @objc public static func labelFor(_ position: TradeItAdPosition) -> String {
        switch(position) {
        case .top: return "top"
        case .bottom: return "bot"
        case .content1: return "content1"
        case .content2: return "content2"
        }
    }
}

@objc public class DefaultAdService: NSObject, AdService {

    @objc public func populate(
        adContainer: UIView,
        rootViewController: UIViewController,
        pageType: TradeItAdPageType,
        position: TradeItAdPosition,
        broker: String?,
        symbol: String?,
        instrumentType: String?,
        trackPageViewAsPageType: Bool
    ) {
        adContainer.isHidden = true
        guard let constraint = (adContainer.constraints.filter { $0.firstAttribute == .height }.first) else { return }
        constraint.constant = 0
    }
}

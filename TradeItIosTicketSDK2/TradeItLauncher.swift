import UIKit
import SafariServices

protocol OAuthCompletionListener {
    func onOAuthCompleted(linkedBroker: TradeItLinkedBroker)
}

@objc public class TradeItLauncher: NSObject {
    let linkBrokerUIFlow = TradeItLinkBrokerUIFlow()
    let tradingUIFlow = TradeItTradingUIFlow()
    let fxTradingUIFlow = TradeItFxTradingUIFlow()
    let accountSelectionUIFlow = TradeItAccountSelectionUIFlow()
    let oAuthCompletionUIFlow = TradeItOAuthCompletionUIFlow()
    let viewControllerProvider = TradeItViewControllerProvider()
    var deviceManager = TradeItDeviceManager()
    let alertManager = TradeItAlertManager()

    static var accountSelectionCallback: ((TradeItLinkedBrokerAccount) -> Void)? // Ew, gross. No other way to do this.
    static var accountSelectionTitle: String? // Ew, gross. No other way to do this.

    override internal init() {
        TradeItSDK.uiConfigService.isEnabled = true
    }

    @objc public func handleOAuthCallback(
        onTopmostViewController topMostViewController: UIViewController,
        oAuthCallbackUrl: URL
    ) {
        print("=====> handleOAuthCallback: \(oAuthCallbackUrl.absoluteString)")

        let oAuthCallbackUrlParser = TradeItOAuthCallbackUrlParser(oAuthCallbackUrl: oAuthCallbackUrl)

        var originalViewController: UIViewController?

        // Check for the OAuth "popup" screen
        if topMostViewController is SFSafariViewController {
            originalViewController = topMostViewController.presentingViewController
        }

        // Check for the Broker Selection or Welcome screen
        if originalViewController?.childViewControllers.first is TradeItSelectBrokerViewController
            || originalViewController?.childViewControllers.first is TradeItWelcomeViewController {
            originalViewController = originalViewController?.presentingViewController
        }

        // If either the OAuth "popup" or broker selection screens are present, dismiss them before presenting
        // the OAuth completion screen
        if let originalViewController = originalViewController {
            originalViewController.dismiss(
                animated: true,
                completion: {
                    self.oAuthCompletionUIFlow.presentOAuthCompletionFlow(
                        fromViewController: originalViewController,
                        oAuthCallbackUrlParser: oAuthCallbackUrlParser
                    )
                }
            )
        } else {
            self.oAuthCompletionUIFlow.presentOAuthCompletionFlow(
                fromViewController: topMostViewController,
                oAuthCallbackUrlParser: oAuthCallbackUrlParser
            )
        }
    }

    @objc public func launchPortfolio(fromViewController viewController: UIViewController) {
        // If user has no linked brokers, set OAuth callback destination and show welcome flow instead
        if (TradeItSDK.linkedBrokerManager.linkedBrokers.count == 0) {
            var oAuthCallbackUrl = TradeItSDK.oAuthCallbackUrl

            if var urlComponents = URLComponents(
                url: oAuthCallbackUrl,
                resolvingAgainstBaseURL: false
            ) {
                urlComponents.addOrUpdateQueryStringValue(
                    forKey: OAuthCallbackQueryParamKeys.tradeItDestination.rawValue,
                    value: OAuthCallbackDestinationValues.portfolio.rawValue)

                oAuthCallbackUrl = urlComponents.url ?? oAuthCallbackUrl
            }

            self.linkBrokerUIFlow.presentLinkBrokerFlow(
                fromViewController: viewController,
                showWelcomeScreen: true,
                oAuthCallbackUrl: oAuthCallbackUrl
            )
        } else {
            deviceManager.authenticateUserWithTouchId(
                onSuccess: {
                    let navController = self.viewControllerProvider.provideNavigationController(withRootViewStoryboardId: .portfolioAccountsView)
                    viewController.present(navController, animated: true, completion: nil)
                }, onFailure: {
                    print("TouchId access denied")
                }
            )
        }
    }

    @objc public func launchPortfolio(
        fromViewController viewController: UIViewController,
        forLinkedBrokerAccount linkedBrokerAccount: TradeItLinkedBrokerAccount?
    ) {
        deviceManager.authenticateUserWithTouchId(
            onSuccess: {
                let navController = self.viewControllerProvider.provideNavigationController(withRootViewStoryboardId: .portfolioAccountDetailsView)

                guard let portfolioAccountDetailsViewController = navController.viewControllers.last as? TradeItPortfolioAccountDetailsViewController else { return }

                portfolioAccountDetailsViewController.automaticallyAdjustsScrollViewInsets = true
                portfolioAccountDetailsViewController.linkedBrokerAccount = linkedBrokerAccount

                viewController.present(navController, animated: true, completion: nil)
            }, onFailure: {
                print("TouchId access denied")
            }
        )
    }

    @objc public func launchPortfolio(
        fromViewController viewController: UIViewController,
        forAccountNumber accountNumber: String
    ) {
        let accounts = TradeItSDK.linkedBrokerManager.linkedBrokers.flatMap { $0.accounts }.filter { $0.accountNumber == accountNumber }

        if accounts.isEmpty {
            print("WARNING: No linked broker accounts found matching the account number " + accountNumber)
        } else {
            if accounts.count > 1 {
                print("WARNING: there are several linked broker accounts with the same account number... taking the first one")
            }

            self.launchPortfolio(fromViewController: viewController, forLinkedBrokerAccount: accounts[0])
        }
    }

    @objc public func launchTrading(
        fromViewController viewController: UIViewController,
        withOrder order: TradeItOrder = TradeItOrder()
    ) {
        // If user has no linked brokers, set OAuth callback destination and show welcome flow instead
        if (TradeItSDK.linkedBrokerManager.linkedBrokers.count == 0) {
            var oAuthCallbackUrl = TradeItSDK.oAuthCallbackUrl

            if var urlComponents = URLComponents(
                url: oAuthCallbackUrl,
                resolvingAgainstBaseURL: false
            ) {
                urlComponents.addOrUpdateQueryStringValue(
                    forKey: OAuthCallbackQueryParamKeys.tradeItDestination.rawValue,
                    value: OAuthCallbackDestinationValues.trading.rawValue)

                urlComponents.addOrUpdateQueryStringValue(
                    forKey: OAuthCallbackQueryParamKeys.tradeItOrderSymbol.rawValue,
                    value: order.symbol)

                if order.action != .unknown {
                    urlComponents.addOrUpdateQueryStringValue(
                        forKey: OAuthCallbackQueryParamKeys.tradeItOrderAction.rawValue,
                        value: order.action.rawValue)
                }

                oAuthCallbackUrl = urlComponents.url ?? oAuthCallbackUrl
            }

            self.linkBrokerUIFlow.presentLinkBrokerFlow(
                fromViewController: viewController,
                showWelcomeScreen: true,
                oAuthCallbackUrl: oAuthCallbackUrl
            )
        } else {
            deviceManager.authenticateUserWithTouchId(
                onSuccess: {
                    self.tradingUIFlow.presentTradingFlow(fromViewController: viewController, withOrder: order)
                },
                onFailure: {
                    print("TouchId access denied")
                }
            )
        }
    }

    @objc public func launchFxTrading(
        fromViewController viewController: UIViewController,
        withOrder order: TradeItFxOrder = TradeItFxOrder()
    ) {
        // If user has no linked brokers, set OAuth callback destination and show welcome flow instead
        if (TradeItSDK.linkedBrokerManager.linkedBrokers.count == 0) {
            var oAuthCallbackUrl = TradeItSDK.oAuthCallbackUrl

            if var urlComponents = URLComponents(
                url: oAuthCallbackUrl,
                resolvingAgainstBaseURL: false
                ) {
                urlComponents.addOrUpdateQueryStringValue(
                    forKey: OAuthCallbackQueryParamKeys.tradeItDestination.rawValue,
                    value: OAuthCallbackDestinationValues.fxTrading.rawValue)

                urlComponents.addOrUpdateQueryStringValue(
                    forKey: OAuthCallbackQueryParamKeys.tradeItOrderSymbol.rawValue,
                    value: order.symbol)

                oAuthCallbackUrl = urlComponents.url ?? oAuthCallbackUrl
            }

            self.linkBrokerUIFlow.presentLinkBrokerFlow(
                fromViewController: viewController,
                showWelcomeScreen: true,
                oAuthCallbackUrl: oAuthCallbackUrl
            )
        } else {
            deviceManager.authenticateUserWithTouchId(
                onSuccess: {
                    self.fxTradingUIFlow.presentTradingFlow(fromViewController: viewController, withOrder: order)
                },
                onFailure: {
                    print("TouchId access denied")
                }
            )
        }
    }

    @objc public func launchAccountManagement(fromViewController viewController: UIViewController) {
        deviceManager.authenticateUserWithTouchId(
            onSuccess: {
                let navController = self.viewControllerProvider.provideNavigationController(withRootViewStoryboardId: TradeItStoryboardID.brokerManagementView)

                viewController.present(navController, animated: true, completion: nil)
            },
            onFailure: {
                print("TouchId access denied")
            }
        )
    }

    @objc public func launchBrokerLinking(fromViewController viewController: UIViewController) {
        let showWelcomeScreen = TradeItSDK.linkedBrokerManager.linkedBrokers.count > 0

        self.launchBrokerLinking(
            fromViewController: viewController,
            showWelcomeScreen: showWelcomeScreen
        )
    }

    @objc public func launchRelinking(
        fromViewController viewController: UIViewController,
        forLinkedBroker linkedBroker: TradeItLinkedBroker
    ) {
        let oAuthCallbackUrl = TradeItSDK.oAuthCallbackUrl

        self.linkBrokerUIFlow.presentRelinkBrokerFlow(
            inViewController: viewController,
            linkedBroker: linkedBroker,
            oAuthCallbackUrl: oAuthCallbackUrl
        )
    }

    @objc public func launchBrokerLinking(
        fromViewController viewController: UIViewController,
        showWelcomeScreen: Bool=false,
        showOpenAccountButton: Bool=true
    ) {
        let oAuthCallbackUrl = TradeItSDK.oAuthCallbackUrl

        self.linkBrokerUIFlow.presentLinkBrokerFlow(
            fromViewController: viewController,
            showWelcomeScreen: showWelcomeScreen,
            showOpenAccountButton: showOpenAccountButton,
            oAuthCallbackUrl: oAuthCallbackUrl
        )
    }

    @objc public func launchBrokerCenter(fromViewController viewController: UIViewController) {
        guard let url = URL(string: TradeItSDK.brokerCenterService.getUrl()) else { return }
        let safariViewController = SFSafariViewController(url: url)
        viewController.present(safariViewController, animated: true, completion: nil)
    }

    @objc public func launchAccountSelection(
        fromViewController viewController: UIViewController,
        title: String? = nil,
        onSelected: @escaping (TradeItLinkedBrokerAccount) -> Void
    ) {
        if (TradeItSDK.linkedBrokerManager.linkedBrokers.count == 0) {
            var oAuthCallbackUrl = TradeItSDK.oAuthCallbackUrl

            if var urlComponents = URLComponents(
                url: oAuthCallbackUrl,
                resolvingAgainstBaseURL: false
            ) {
                urlComponents.addOrUpdateQueryStringValue(
                    forKey: OAuthCallbackQueryParamKeys.tradeItDestination.rawValue,
                    value: OAuthCallbackDestinationValues.accountSelection.rawValue
                )

                oAuthCallbackUrl = urlComponents.url ?? oAuthCallbackUrl
            }

            TradeItLauncher.accountSelectionCallback = onSelected
            TradeItLauncher.accountSelectionTitle = title

            self.linkBrokerUIFlow.presentLinkBrokerFlow(
                fromViewController: viewController,
                showWelcomeScreen: true,
                oAuthCallbackUrl: oAuthCallbackUrl
            )
        } else {
            self.accountSelectionUIFlow.presentAccountSelectionFlow(
                fromViewController: viewController,
                title: title,
                onSelected: { presentedNavController, linkedBrokerAccount in
                    presentedNavController.dismiss(animated: true, completion: nil)
                    onSelected(linkedBrokerAccount)
                }
            )
        }
    }
    
    @objc public func launchOrders(
        fromViewController viewController: UIViewController,
        forLinkedBrokerAccount linkedBrokerAccount: TradeItLinkedBrokerAccount
        ) {
        deviceManager.authenticateUserWithTouchId(
            onSuccess: {
                let navController = self.viewControllerProvider.provideNavigationController(withRootViewStoryboardId: .ordersView)
                
                guard let ordersViewController = navController.viewControllers.last as? TradeItOrdersViewController else { return }
                ordersViewController.linkedBrokerAccount = linkedBrokerAccount
                ordersViewController.enableThemeOnLoad = false
                ordersViewController.view.backgroundColor = UIColor.tradeItlightGreyHeaderBackgroundColor
                viewController.present(navController, animated: true, completion: nil)
            }, onFailure: {
                print("TouchId access denied")
            }
        )
    }

    @objc public func launchTransactions(
        fromViewController viewController: UIViewController,
        forLinkedBrokerAccount linkedBrokerAccount: TradeItLinkedBrokerAccount
        ) {
        deviceManager.authenticateUserWithTouchId(
            onSuccess: {
                let navController = self.viewControllerProvider.provideNavigationController(withRootViewStoryboardId: .transactionsView)

                guard let transactionsViewController = navController.viewControllers.last as? TradeItTransactionsViewController else { return }
                transactionsViewController.linkedBrokerAccount = linkedBrokerAccount
                transactionsViewController.enableThemeOnLoad = false
                transactionsViewController.view.backgroundColor = UIColor.tradeItlightGreyHeaderBackgroundColor
                viewController.present(navController, animated: true, completion: nil)
            }, onFailure: {
                print("TouchId access denied")
            }
        )
    }

}

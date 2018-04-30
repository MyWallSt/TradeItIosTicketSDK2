import UIKit

class TradeItEquityTradingUIFlow: NSObject, TradeItAccountSelectionViewControllerDelegate, TradeItSymbolSearchViewControllerDelegate, TradeItTradingTicketViewControllerDelegate, TradeItTradePreviewViewControllerDelegate, TradeItTradingConfirmationViewControllerDelegate {

    let viewControllerProvider: TradeItViewControllerProvider = TradeItViewControllerProvider()
    var order = TradeItOrder()
    var previewOrderResult: TradeItPreviewOrderResult?

    func pushTradingFlow(
        onNavigationController navController: UINavigationController,
        asRootViewController: Bool,
        withOrder order: TradeItOrder = TradeItOrder()
    ) {
        self.order = order

        let initialViewController = getInitialViewController(forOrder: order)

        if (asRootViewController) {
            navController.setViewControllers([initialViewController], animated: true)
        } else {
            navController.pushViewController(initialViewController, animated: true)
        }
    }

    func presentTradingFlow(
        fromViewController viewController: UIViewController,
        withOrder order: TradeItOrder = TradeItOrder()
    ) {
        self.order = order

        let initialViewController = getInitialViewController(forOrder: order)

        let navController = UINavigationController()
        navController.setViewControllers([initialViewController], animated: true)

        viewController.present(navController, animated: true, completion: nil)
    }

    // MARK: Private

    private func initializeLinkedAccount(forOrder order: TradeItOrder) {
        if order.linkedBrokerAccount == nil {
            let enabledAccounts = TradeItSDK.linkedBrokerManager.getAllEnabledAccounts()

            // If there is only one enabled account, auto-select it
            if enabledAccounts.count == 1 {
                order.linkedBrokerAccount = enabledAccounts.first
            }
        }
    }

    private func getInitialViewController(forOrder order: TradeItOrder) -> UIViewController {
        var initialStoryboardId: TradeItStoryboardID!

        self.initializeLinkedAccount(forOrder: order)

        if (order.linkedBrokerAccount == nil) {
            initialStoryboardId = TradeItStoryboardID.accountSelectionView
        } else if (order.symbol == nil) {
            initialStoryboardId = TradeItStoryboardID.symbolSearchView
        } else {
            initialStoryboardId = TradeItStoryboardID.tradingTicketView
        }

        let initialViewController = self.viewControllerProvider.provideViewController(forStoryboardId: initialStoryboardId)

        if let accountSelectionViewController = initialViewController as? TradeItAccountSelectionViewController {
            accountSelectionViewController.delegate = self
        } else if let symbolSearchViewController = initialViewController as? TradeItSymbolSearchViewController {
            symbolSearchViewController.delegate = self
        } else if let tradingTicketViewController = initialViewController as? TradeItTradingTicketViewController {
            tradingTicketViewController.delegate = self
            tradingTicketViewController.order = order
        }

        return initialViewController
    }

    // MARK: TradeItSymbolSearchViewControllerDelegate

    internal func symbolSearchViewController(
        _ symbolSearchViewController: TradeItSymbolSearchViewController,
        didSelectSymbol selectedSymbol: String
    ) {
        self.order.symbol = selectedSymbol

        let tradingTicketViewController = self.viewControllerProvider.provideViewController(forStoryboardId: TradeItStoryboardID.tradingTicketView) as! TradeItTradingTicketViewController

        tradingTicketViewController.delegate = self
        tradingTicketViewController.order = self.order

        symbolSearchViewController.navigationController?.setViewControllers([tradingTicketViewController], animated: true)
    }

    // MARK: TradeItAccountSelectionViewControllerDelegate

    internal func accountSelectionViewController(
        _ accountSelectionViewController: TradeItAccountSelectionViewController,
        didSelectLinkedBrokerAccount linkedBrokerAccount: TradeItLinkedBrokerAccount
    ) {
        self.order.linkedBrokerAccount = linkedBrokerAccount

        var nextStoryboardId: TradeItStoryboardID!

        if (order.symbol == nil) {
            nextStoryboardId = TradeItStoryboardID.symbolSearchView
        } else {
            nextStoryboardId = TradeItStoryboardID.tradingTicketView
        }

        let nextViewController = self.viewControllerProvider.provideViewController(forStoryboardId: nextStoryboardId)

        if let symbolSearchViewController = nextViewController as? TradeItSymbolSearchViewController {
            symbolSearchViewController.delegate = self
        } else if let tradingTicketViewController = nextViewController as? TradeItTradingTicketViewController {
            tradingTicketViewController.delegate = self
            tradingTicketViewController.order = self.order
        }

        accountSelectionViewController.navigationController?.setViewControllers([nextViewController], animated: true)
    }

    // MARK: TradeItTradingTicketViewControllerDelegate

    internal func orderSuccessfullyPreviewed(
        onTradingTicketViewController tradingTicketViewController: TradeItTradingTicketViewController,
        withPreviewOrderResult previewOrderResult: TradeItPreviewOrderResult,
        placeOrderCallback: @escaping TradeItPlaceOrderHandlers
    ) {
        self.previewOrderResult = previewOrderResult

        let nextViewController = self.viewControllerProvider.provideViewController(forStoryboardId: TradeItStoryboardID.tradingPreviewView)

        if let tradePreviewViewController = nextViewController as? TradeItTradePreviewViewController {
            tradePreviewViewController.delegate = self
            tradePreviewViewController.linkedBrokerAccount = tradingTicketViewController.order.linkedBrokerAccount
            tradePreviewViewController.previewOrderResult = previewOrderResult
            tradePreviewViewController.placeOrderCallback = placeOrderCallback
        }

        tradingTicketViewController.navigationController?.pushViewController(nextViewController, animated: true)
    }

    internal func invalidAccountSelected(
        onTradingTicketViewController tradingTicketViewController: TradeItTradingTicketViewController,
        withOrder order: TradeItOrder
    ) {
        guard let accountSelectionViewController = self.viewControllerProvider.provideViewController(
            forStoryboardId: TradeItStoryboardID.accountSelectionView
        ) as? TradeItAccountSelectionViewController else {
                print("TradeItSDK ERROR: Could not instantiate TradeItAccountSelectionViewController from storyboard!")
                return
        }

        guard let navigationController = tradingTicketViewController.navigationController else {
            print("TradeItSDK ERROR: Could not get UINavigationController from TradeItTradingTicketViewController!")
            return
        }

        self.order = order
        accountSelectionViewController.delegate = self
        navigationController.setViewControllers([accountSelectionViewController], animated: true)
    }
    
    // MARK: TradeItTradePreviewViewControllerDelegate

    internal func orderSuccessfullyPlaced(
        onTradePreviewViewController tradePreviewViewController: TradeItTradePreviewViewController,
        withPlaceOrderResult placeOrderResult: TradeItPlaceOrderResult
    ) {
        let nextViewController = self.viewControllerProvider.provideViewController(forStoryboardId: TradeItStoryboardID.tradingConfirmationView)

        if let tradingConfirmationViewController = nextViewController as? TradeItTradingConfirmationViewController {
            tradingConfirmationViewController.delegate = self
            tradingConfirmationViewController.confirmationMessage = buildConfirmationMessage(
                previewOrderResult: self.previewOrderResult,
                placeOrderResult: placeOrderResult
            )
            tradingConfirmationViewController.timestamp = placeOrderResult.timestamp
            tradingConfirmationViewController.orderNumber = placeOrderResult.orderNumber
            tradingConfirmationViewController.order = self.order

            // Analytics tracking only
            tradingConfirmationViewController.broker = order.linkedBrokerAccount?.linkedBroker?.brokerName
            tradingConfirmationViewController.symbol = order.symbol
            tradingConfirmationViewController.instrument = TradeItTradeInstrumentType.equities.rawValue
        }

        tradePreviewViewController.navigationController?.setViewControllers([nextViewController], animated: true)
    }

    // MARK: TradeItTradingConfirmationViewControllerDelegate

    internal func tradeButtonWasTapped(
        _ tradeItTradingConfirmationViewController: TradeItTradingConfirmationViewController
    ) {
        if let navigationController = tradeItTradingConfirmationViewController.navigationController {
            self.pushTradingFlow(onNavigationController: navigationController, asRootViewController: true)
        } else if let presentingViewController = tradeItTradingConfirmationViewController.presentingViewController {
            self.presentTradingFlow(fromViewController: presentingViewController)
        }
    }

    private func buildConfirmationMessage(
        previewOrderResult: TradeItPreviewOrderResult?,
        placeOrderResult: TradeItPlaceOrderResult?
    ) -> String {
        let orderDetails = previewOrderResult?.orderDetails
        let orderInfo = placeOrderResult?.orderInfo

        let actionText = orderInfo?.action ?? "[MISSING ACTION]"
        let symbolText = orderInfo?.symbol ?? "[MISSING SYMBOL]"
        let priceText = orderDetails?.orderPrice ?? "[MISSING PRICE]"
        var quantityText = "[MISSING QUANTITY]"

        if let quantity = orderInfo?.quantity {
            quantityText = NumberFormatter.formatQuantity(quantity)
        }

        return "Your order to \(actionText) \(quantityText) shares of \(symbolText) at \(priceText) has been successfully transmitted to your broker"
    }
}

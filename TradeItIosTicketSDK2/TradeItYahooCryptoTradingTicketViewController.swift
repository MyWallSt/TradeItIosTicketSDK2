import UIKit
import MBProgressHUD

class TradeItYahooCryptoTradingTicketViewController:
    TradeItYahooViewController,
    UITableViewDelegate,
    UITableViewDataSource,
    TradeItYahooAccountSelectionViewControllerDelegate
{
    @IBOutlet weak var tableView: TradeItDismissableKeyboardTableView!
    @IBOutlet weak var previewOrderButton: UIButton!
    @IBOutlet weak var tableViewBottomConstraint: NSLayoutConstraint!

    public weak var delegate: TradeItYahooCryptoTradingTicketViewControllerDelegate?

    internal var order = TradeItCryptoOrder()

    private let alertManager = TradeItAlertManager(linkBrokerUIFlow: TradeItYahooLinkBrokerUIFlow())
    private let viewProvider = TradeItViewControllerProvider(storyboardName: "TradeItYahoo")
    private var selectionViewController: TradeItYahooSelectionViewController!
    private var accountSelectionViewController: TradeItYahooAccountSelectionViewController!
    private let marketDataService = TradeItSDK.marketDataService
    private var keyboardOffsetContraintManager: TradeItKeyboardOffsetConstraintManager?
    private var cryptoQuote: TradeItCryptoQuoteResult?
    private var orderCapabilities: TradeItInstrumentOrderCapabilities?
    private var supportedOrderQuantityTypes: [OrderQuantityType] {
        get {
            return self.orderCapabilities?.supportedOrderQuantityTypes(forAction: self.order.action, priceType: self.order.type) ?? []
        }
    }

    private var ticketRows = [TicketRow]()

    private var selectedAccountChanged: Bool = true

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let selectionViewController = self.viewProvider.provideViewController(
            forStoryboardId: .yahooSelectionView
        ) as? TradeItYahooSelectionViewController else {
                assertionFailure("TradeItSDK ERROR: Could not instantiate TradeItYahooSelectionViewController from storyboard")
                return
        }

        self.selectionViewController = selectionViewController

        guard let accountSelectionViewController = self.viewProvider.provideViewController(
            forStoryboardId: .yahooAccountSelectionView
        ) as? TradeItYahooAccountSelectionViewController else {
                assertionFailure("TradeItSDK ERROR: Could not instantiate TradeItYahooAccountSelectionViewController from storyboard")
                return
        }

        accountSelectionViewController.delegate = self
        self.accountSelectionViewController = accountSelectionViewController

        self.keyboardOffsetContraintManager = TradeItKeyboardOffsetConstraintManager(
            bottomConstraint: self.tableViewBottomConstraint,
            viewController: self
        )

        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.tableView.tableFooterView = UIView()
        TradeItBundleProvider.registerYahooNibCells(forTableView: self.tableView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.fireViewEventNotification(view: .trading, title: self.title)

        guard self.order.linkedBrokerAccount?.isEnabled ?? false else {
            self.delegate?.invalidAccountSelected(
                onTradingTicketViewController: self,
                withOrder: self.order
            )
            return
        }

        if self.selectedAccountChanged {
            self.initializeTicket()
        } else {
            self.reloadTicketRows()
        }
    }

    // MARK: UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let ticketRow = self.ticketRows[indexPath.row]

        switch ticketRow {
        case .account:
            self.pushAccountSelection()
        case .orderAction:
            self.pushOrderCapabilitiesSelection(ticketRow: ticketRow, field: .actions, value: self.order.action.rawValue) { selection in
                self.order.action = TradeItOrderAction(value: selection)
            }

            self.fireViewEventNotification(view: .selectActionType, title: self.selectionViewController.title)
        case .orderType:
            self.pushOrderCapabilitiesSelection(ticketRow: ticketRow, field: .priceTypes, value: self.order.type.rawValue) { selection in
                self.order.type = TradeItOrderPriceType(value: selection)
            }

            self.fireViewEventNotification(view: .selectOrderType, title: self.selectionViewController.title)
        case .expiration:
            self.pushOrderCapabilitiesSelection(ticketRow: ticketRow, field: .expirationTypes, value: self.order.expiration.rawValue) { selection in
                self.order.expiration = TradeItOrderExpiration(value: selection)
            }

            self.fireViewEventNotification(view: .selectExpirationType, title: self.selectionViewController.title)
        case .marginType:
            self.selectionViewController.title = "Select " + ticketRow.getTitle(forOrder: self.order)
            self.selectionViewController.initialSelection = MarginPresenter.labelFor(value: self.order.userDisabledMargin)
            self.selectionViewController.selections = MarginPresenter.LABELS
            self.selectionViewController.onSelected = { selection in
                self.order.userDisabledMargin = MarginPresenter.valueFor(label: selection)
                _ = self.navigationController?.popViewController(animated: true)
            }
            self.navigationController?.pushViewController(selectionViewController, animated: true)
        default:
            return
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        struct StaticVars {
            static var rowHeights = [String:CGFloat]()
        }

        let ticketRow = self.ticketRows[indexPath.row]

        guard let height = StaticVars.rowHeights[ticketRow.cellReuseId] else {
            let cell = tableView.dequeueReusableCell(withIdentifier: ticketRow.cellReuseId)
            let height = cell?.bounds.size.height ?? tableView.rowHeight
            StaticVars.rowHeights[ticketRow.cellReuseId] = height
            return height
        }

        return height
    }

    // MARK: UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.ticketRows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return self.provideCell(rowIndex: indexPath.row)
    }

    // MARK: IBActions

    @IBAction func previewOrderButtonTapped(_ sender: UIButton) {
        self.fireButtonTapEventNotification(view: .trading, button: .previewOrder)

        guard let linkedBroker = self.order.linkedBrokerAccount?.linkedBroker
            else { return }

        let activityView = MBProgressHUD.showAdded(to: self.view, animated: true)
        activityView.label.text = "Authenticating"

        linkedBroker.authenticateIfNeeded(
            onSuccess: {
                activityView.label.text = "Previewing order"
                self.order.preview(
                    onSuccess: { previewOrderResult, placeOrderCallback in
                        activityView.hide(animated: true)
                        self.delegate?.orderSuccessfullyPreviewed(
                            onTradingTicketViewController: self,
                            withPreviewOrderResult: previewOrderResult,
                            placeOrderCallback: placeOrderCallback
                        )
                    },
                    onFailure: { errorResult in
                        activityView.hide(animated: true)
                        self.alertManager.showAlertWithAction(
                            error: errorResult,
                            withLinkedBroker: self.order.linkedBrokerAccount?.linkedBroker,
                            onViewController: self
                        )
                    }
                )
            },
            onSecurityQuestion: { securityQuestion, answerSecurityQuestion, cancelSecurityQuestion in
                activityView.hide(animated: true)
                self.alertManager.promptUserToAnswerSecurityQuestion(
                    securityQuestion,
                    onViewController: self,
                    onAnswerSecurityQuestion: answerSecurityQuestion,
                    onCancelSecurityQuestion: cancelSecurityQuestion
                )
            },
            onFailure: { errorResult in
                activityView.hide(animated: true)
                self.alertManager.showAlertWithAction(
                    error: errorResult,
                    withLinkedBroker: self.order.linkedBrokerAccount?.linkedBroker,
                    onViewController: self
                )
            }
        )
    }

    // MARK: TradeItYahooAccountSelectionViewControllerDelegate

    func accountSelectionViewController(
        _ accountSelectionViewController: TradeItYahooAccountSelectionViewController,
        didSelectLinkedBrokerAccount linkedBrokerAccount: TradeItLinkedBrokerAccount
    ) {
        self.order.linkedBrokerAccount = linkedBrokerAccount
        self.selectedAccountChanged = true
        _ = self.navigationController?.popViewController(animated: true)
    }

    // MARK: Private

    private func handleSelectedAccountChange() {
        if self.order.action == .buy {
            self.updateAccountOverview()
        } else {
            self.updateSharesOwned()
        }

        self.selectedAccountChanged = false
    }

    private func pushAccountSelection() {
        self.accountSelectionViewController.selectedLinkedBrokerAccount = self.order.linkedBrokerAccount
        self.navigationController?.pushViewController(self.accountSelectionViewController, animated: true)
    }

    private func updateAccountOverview() {
        self.order.linkedBrokerAccount?.getAccountOverview(
            onSuccess: { accountOverview in
                self.reload(row: .account)
            },
            onFailure: { error in
                self.alertManager.showAlertWithAction(
                    error: error,
                    withLinkedBroker: self.order.linkedBrokerAccount?.linkedBroker,
                    onViewController: self
                )
            }
        )
    }

    private func updateSharesOwned() {
        self.order.linkedBrokerAccount?.getPositions(
            onSuccess: { positions in
                self.reload(row: .account)
            },
            onFailure: { error in
                self.alertManager.showAlertWithAction(
                    error: error,
                    withLinkedBroker: self.order.linkedBrokerAccount?.linkedBroker,
                    onViewController: self
                )
            }
        )
    }

    private func setTitle() {
        var title = "Trade"

        if self.order.action != TradeItOrderAction.unknown
            , let actionType = self.orderCapabilities?.labelFor(field: .actions, value: self.order.action.rawValue) {
            title = actionType
        }

        if let symbol = self.order.symbol {
            title += " \(symbol)"
        }

        self.title = title
    }

    private func initializeTicket() {
        let activityView = MBProgressHUD.showAdded(to: self.view, animated: true)
        activityView.label.text = "Authenticating"

        self.order.linkedBrokerAccount?.linkedBroker?.authenticateIfNeeded(
            onSuccess: {
                activityView.hide(animated: true)
                guard let instrumentOrderCapabilities = (self.order.linkedBrokerAccount?.orderCapabilities.filter { $0.instrument == "crypto" })?.first else {
                    self.alertManager.showAlertWithMessageOnly(
                        onViewController: self,
                        withTitle: "Unsupported Account",
                        withMessage: "The selected account does not support trading crypto. Please choose another account.",
                        withActionTitle: "OK",
                        onAlertActionTapped: {
                            self.delegate?.invalidAccountSelected(
                                onTradingTicketViewController: self,
                                withOrder: self.order
                            )
                        }
                    )
                    return
                }
                self.orderCapabilities = instrumentOrderCapabilities
                self.setOrderDefaults()
                self.updateMarketData()
                self.handleSelectedAccountChange()
                self.reloadTicketRows()
            },
            onSecurityQuestion: { securityQuestion, onAnswerSecurityQuestion, onCancelSecurityQuestion in
                activityView.hide(animated: true)
                self.alertManager.promptUserToAnswerSecurityQuestion(
                    securityQuestion,
                    onViewController: self,
                    onAnswerSecurityQuestion: onAnswerSecurityQuestion,
                    onCancelSecurityQuestion: onCancelSecurityQuestion
                )
            },
            onFailure: { error in
                activityView.hide(animated: true)
                self.alertManager.showAlertWithAction(
                    error: error,
                    withLinkedBroker: self.order.linkedBrokerAccount?.linkedBroker,
                    onViewController: self
                )
            }
        )
    }


    private func setOrderDefaults() {
        self.order.action = TradeItOrderAction(value: self.orderCapabilities?.defaultValueFor(field: .actions, value: self.order.action.rawValue))
        self.order.type = TradeItOrderPriceType(value: self.orderCapabilities?.defaultValueFor(field: .priceTypes, value: self.order.type.rawValue))
        self.order.expiration = TradeItOrderExpiration(value: self.orderCapabilities?.defaultValueFor(field: .expirationTypes, value: self.order.expiration.rawValue))
        self.order.quantityType = self.supportedOrderQuantityTypes.first ?? .quoteCurrency
        self.order.userDisabledMargin = false
    }


    private func setReviewButtonEnablement() {
        if self.order.isValid() {
            self.previewOrderButton.enable()
        } else {
            self.previewOrderButton.disable()
        }
    }

    private func clearMarketData() {
        self.cryptoQuote = nil
        self.order.quoteLastPrice = nil
        self.reload(row: .marketPrice)
        self.reload(row: .estimatedChange)
    }
    
    private func updateMarketData() {
        if let symbol = self.order.symbol  {
            let request = TradeItCryptoQuoteRequest()
            request.accountNumber =   self.order.linkedBrokerAccount?.accountNumber
            request.pair = symbol
            
            self.order.linkedBrokerAccount?.cryptoMarketDataService?.getCryptoQuote(
                request,
                onSuccess: { quotesResult in
                    self.cryptoQuote = quotesResult
                    self.order.quoteLastPrice = TradeItQuotePresenter.numberToDecimalNumber(quotesResult.last)
                    self.reload(row: .marketPrice)
                    self.reload(row: .estimatedChange)
                },
                onFailure: { error in
                    self.clearMarketData()
                }
            )
        } else {
            self.clearMarketData()
        }
    }

    private func reloadTicketRows() {
        self.setTitle()
        self.setReviewButtonEnablement()

        var ticketRows: [TicketRow] = [
            .account,
            .orderAction,
            .orderType,
            .expiration,
            .quantity,
        ]

        if self.order.requiresLimitPrice() {
            ticketRows.append(.limitPrice)
        }

        if self.order.requiresStopPrice() {
            ticketRows.append(.stopPrice)
        }

        ticketRows.append(.marketPrice)

        if self.order.userCanDisableMargin() {
            ticketRows.append(.marginType)
        }

        ticketRows.append(.estimatedChange)

        self.ticketRows = ticketRows

        self.tableView.reloadData()
    }

    private func reload(row: TicketRow) {
        guard let indexOfRow = self.ticketRows.index(of: row) else {
            return
        }

        let indexPath = IndexPath.init(row: indexOfRow, section: 0)
        self.tableView.reloadRows(at: [indexPath], with: .automatic)
    }

    private func provideCell(rowIndex: Int) -> UITableViewCell {
        let ticketRow = self.ticketRows[rowIndex]

        let cell = tableView.dequeueReusableCell(withIdentifier: ticketRow.cellReuseId) ?? UITableViewCell()
        cell.textLabel?.text = ticketRow.getTitle(forOrder: self.order)
        cell.selectionStyle = .none

        guard let instrumentOrderCapabilities = self.orderCapabilities else { return cell }

        switch ticketRow {
        case .orderAction:
            cell.detailTextLabel?.text = instrumentOrderCapabilities.labelFor(field: .actions, value: self.order.action.rawValue)
        case .quantity:
            let cell = cell as? TradeItNumericToggleInputCell
            let quantitySymbol = self.order.quantitySymbol
            cell?.configure(
                onValueUpdated: { newValue in
                    self.order.quantity = newValue
                    self.reload(row: .estimatedChange)
                    self.setReviewButtonEnablement()
                },
                onQuantityTypeToggled: {
                    if self.supportedOrderQuantityTypes.isEmpty { return }

                    let currentIndex = self.supportedOrderQuantityTypes.index(of: self.order.quantityType ?? self.supportedOrderQuantityTypes.first ?? .baseCurrency) as Int? ?? 0
                    let nextIndex = (currentIndex + 1) % self.supportedOrderQuantityTypes.count
                    let nextOrderQuantityType = self.self.supportedOrderQuantityTypes[safe: nextIndex] ?? self.supportedOrderQuantityTypes.first ?? .baseCurrency

                    if self.order.quantityType != nextOrderQuantityType {
                        self.order.quantityType = nextOrderQuantityType

                        let quantitySymbol = self.order.quantitySymbol
                        self.order.quantity = nil
                        cell?.configureQuantityType(
                            quantitySymbol: quantitySymbol,
                            quantity: self.order.quantity,
                            maxDecimalPlaces: instrumentOrderCapabilities.maxDecimalPlacesFor(orderQuantityType: self.order.quantityType),
                            showToggle: self.supportedOrderQuantityTypes.count > 1
                        )
                    }
                }
            )
            cell?.configureQuantityType(
                quantitySymbol: quantitySymbol,
                quantity: self.order.quantity,
                maxDecimalPlaces: instrumentOrderCapabilities.maxDecimalPlacesFor(orderQuantityType: self.order.quantityType),
                showToggle: supportedOrderQuantityTypes.count > 1
            )
        case .limitPrice:
            let cell = cell as? TradeItNumericToggleInputCell
            cell?.configure(
                onValueUpdated: { newValue in
                    self.order.limitPrice = newValue
                    self.reload(row: .estimatedChange)
                    self.setReviewButtonEnablement()
                }
            )
            cell?.configureQuantityType(
                quantitySymbol: self.order.quoteSymbol,
                quantity: self.order.limitPrice,
                maxDecimalPlaces: instrumentOrderCapabilities.maxDecimalPlacesFor(orderQuantityType: .quoteCurrency)
            )
        case .stopPrice:
            let cell = cell as? TradeItNumericToggleInputCell
            cell?.configure(
                onValueUpdated: { newValue in
                    self.order.stopPrice = newValue
                    self.reload(row: .estimatedChange)
                    self.setReviewButtonEnablement()
                }
            )
            cell?.configureQuantityType(
                quantitySymbol: self.order.quoteSymbol,
                quantity: self.order.stopPrice,
                maxDecimalPlaces: instrumentOrderCapabilities.maxDecimalPlacesFor(orderQuantityType: .quoteCurrency)
            )
        case .marketPrice:
            guard let marketCell = cell as? TradeItSubtitleWithDetailsCellTableViewCell else { return cell }
            let quotePresenter = TradeItQuotePresenter(self.order.linkedBrokerAccount?.accountBaseCurrency)
            marketCell.configure(
                subtitleLabel: quotePresenter.formatTimestamp(cryptoQuote?.dateTime),
                detailsLabel: quotePresenter.formatCurrency(cryptoQuote?.last),
                subtitleDetailsLabel: "",
                subtitleDetailsLabelColor: UIColor.black
            )
        case .marginType:
            cell.detailTextLabel?.text = MarginPresenter.labelFor(value: self.order.userDisabledMargin)
        case .estimatedChange:
            var estimatedChangeText = "N/A"

            if let estimatedChange = order.estimatedChange() {
                estimatedChangeText = NumberFormatter.formatQuantity(estimatedChange)
            }

            cell.detailTextLabel?.text = estimatedChangeText
        case .orderType:
            cell.detailTextLabel?.text = instrumentOrderCapabilities.labelFor(field: .priceTypes, value: self.order.type.rawValue)
        case .expiration:
            cell.detailTextLabel?.text = instrumentOrderCapabilities.labelFor(field: .expirationTypes, value: self.order.expiration.rawValue)
        case .account:
            guard let detailCell = cell as? TradeItSelectionDetailCellTableViewCell else { return cell }
            detailCell.textLabel?.isHidden = true
            detailCell.configure(
                detailPrimaryText: self.order.linkedBrokerAccount?.getFormattedAccountName(),
                detailSecondaryText: accountSecondaryText(),
                altTitleText: ticketRow.getTitle(forOrder: self.order)
            )
        }

        return cell
    }

    private func accountSecondaryText() -> String? {
        if self.order.action == .buy {
            return buyingPowerText()
        } else {
            return sharesOwnedText()
        }
    }

    private func buyingPowerText() -> String? {
        guard let buyingPower = self.order.linkedBrokerAccount?.balance?.buyingPower else { return nil }
        let buyingPowerLabel = self.order.linkedBrokerAccount?.balance?.buyingPowerLabel?.capitalized ?? "Buying power"
        let buyingPowerValue = NumberFormatter.formatCurrency(buyingPower, currencyCode: self.order.linkedBrokerAccount?.accountBaseCurrency)
        return buyingPowerLabel + ": " + buyingPowerValue
    }

    private func sharesOwnedText() -> String? {
        guard let positions = self.order.linkedBrokerAccount?.positions, !positions.isEmpty else { return nil }

        let positionMatchingSymbol = positions.filter { portfolioPosition in
            TradeItPortfolioEquityPositionPresenter(portfolioPosition).getFormattedSymbol() == self.order.symbol
        }.first

        guard let sharesOwned = positionMatchingSymbol?.position?.quantity,
            let symbol = self.order.baseSymbol
            else { return "" }
        
        return "\(symbol) owned: \(NumberFormatter.formatQuantity(sharesOwned))"
    }

    private func pushOrderCapabilitiesSelection(
        ticketRow: TicketRow,
        field: TradeItInstrumentOrderCapabilityField,
        value: String?,
        onSelected: @escaping (String?) -> Void
    ) {
        guard let orderCapabilities = self.orderCapabilities else { return }
        self.selectionViewController.title = "Select " + ticketRow.getTitle(forOrder: self.order).lowercased()
        self.selectionViewController.initialSelection = orderCapabilities.labelFor(field: field, value: value)
        self.selectionViewController.selections = orderCapabilities.labelsFor(field: field)
        self.selectionViewController.onSelected = { selection in
            onSelected(orderCapabilities.valueFor(field: field, label: selection))
            _ = self.navigationController?.popViewController(animated: true)
        }

        self.navigationController?.pushViewController(selectionViewController, animated: true)
    }

    private func updateOrderQuantityTypeConstraints() {
        if !supportedOrderQuantityTypes.contains(self.order.quantityType) {
            self.order.quantity = nil
            self.order.quantityType = supportedOrderQuantityTypes.first ?? .shares
            self.reload(row: .quantity)
        }
    }

    enum TicketRow {
        case account
        case orderAction
        case orderType
        case quantity
        case expiration
        case limitPrice
        case stopPrice
        case marketPrice
        case marginType
        case estimatedChange

        var cellReuseId: String {
            var cellReuseId: CellReuseId

            switch self {
            case .orderAction, .orderType, .expiration, .marginType:
                cellReuseId = .selection
            case .estimatedChange:
                cellReuseId = .readOnly
            case .quantity, .limitPrice, .stopPrice:
                cellReuseId = .numericToggleInput
            case .marketPrice:
                cellReuseId = .marketData
            case .account:
                cellReuseId = .selectionDetail
            }

            return cellReuseId.rawValue
        }

        func getTitle(forOrder order: TradeItCryptoOrder) -> String {
            switch self {
            case .orderAction: return "Action"
            case .estimatedChange: return "Estimated \(order.quantitySymbol ?? "")"
            case .quantity: return "Amount"
            case .limitPrice: return "Limit"
            case .stopPrice: return "Stop"
            case .orderType: return "Order type"
            case .expiration: return "Time in force"
            case .marketPrice: return "Market price"
            case .account: return "Account"
            case .marginType: return "Type"
            }
        }
    }
}

@objc protocol TradeItYahooCryptoTradingTicketViewControllerDelegate {
    func orderSuccessfullyPreviewed(
        onTradingTicketViewController tradingTicketViewController: TradeItYahooCryptoTradingTicketViewController,
        withPreviewOrderResult previewOrderResult: TradeItCryptoPreviewTradeResult,
        placeOrderCallback: @escaping TradeItPlaceOrderHandlers
    )

    func invalidAccountSelected(
        onTradingTicketViewController tradingTicketViewController: TradeItYahooCryptoTradingTicketViewController,
        withOrder order: TradeItCryptoOrder
    )
}

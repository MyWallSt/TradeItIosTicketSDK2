import UIKit
import MBProgressHUD

class TradeItTradingTicketViewController: TradeItViewController, UITableViewDataSource, UITableViewDelegate, TradeItAccountSelectionViewControllerDelegate, TradeItSymbolSearchViewControllerDelegate {
    @IBOutlet weak var tableView: TradeItDismissableKeyboardTableView!
    @IBOutlet weak var previewOrderButton: UIButton!
    @IBOutlet weak var adContainer: UIView!
    @IBOutlet weak var tableViewBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var marketDataLabel: UILabel!

    public weak var delegate: TradeItTradingTicketViewControllerDelegate?

    internal var order = TradeItOrder()

    private var alertManager = TradeItAlertManager()
    private let viewProvider = TradeItViewControllerProvider()
    private var selectionViewController: TradeItSelectionViewController!
    private var accountSelectionViewController: TradeItAccountSelectionViewController!
    private var symbolSearchViewController: TradeItSymbolSearchViewController!
    private let marketDataService = TradeItSDK.marketDataService
    private let streamingMarketDataService = TradeItSDK.streamingMarketDataService
    private var keyboardOffsetContraintManager: TradeItKeyboardOffsetConstraintManager?
    private var quote: TradeItQuote?

    private var ticketRows = [TicketRow]()

    private var orderCapabilities: TradeItInstrumentOrderCapabilities?

    private var selectedAccountChanged: Bool = true
    
    private lazy var updateQuotePrice: (TradeItQuote) -> Void = { quote in
        self.quote = quote
        self.order.quoteLastPrice = TradeItQuotePresenter.numberToDecimalNumber(quote.lastPrice)
        self.reload(row: .marketPrice, animation: .none)
        self.reload(row: .estimatedCost, animation: .none)
    }
    private var supportedOrderQuantityTypes: [OrderQuantityType] {
        get {
            return self.orderCapabilities?.supportedOrderQuantityTypes(forAction: self.order.action, priceType: self.order.type) ?? []
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let selectionViewController = self.viewProvider.provideViewController(forStoryboardId: .tradingSelectionView) as? TradeItSelectionViewController else {
            assertionFailure("ERROR: Could not instantiate TradeItSelectionViewController from storyboard")
            return
        }
        self.selectionViewController = selectionViewController

        guard let accountSelectionViewController = self.viewProvider.provideViewController(forStoryboardId: .accountSelectionView) as? TradeItAccountSelectionViewController else {
            assertionFailure("ERROR: Could not instantiate TradeItAccountSelectionViewController from storyboard")
            return
        }
        accountSelectionViewController.delegate = self
        self.accountSelectionViewController = accountSelectionViewController

        guard let symbolSearchViewController = self.viewProvider.provideViewController(forStoryboardId: .symbolSearchView) as? TradeItSymbolSearchViewController else {
            assertionFailure("ERROR: Could not instantiate TradeItSymbolSearchViewController from storyboard")
            return
        }
        symbolSearchViewController.delegate = self
        self.symbolSearchViewController = symbolSearchViewController

        self.keyboardOffsetContraintManager = TradeItKeyboardOffsetConstraintManager(
            bottomConstraint: self.tableViewBottomConstraint,
            viewController: self
        )

        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.tableView.tableFooterView = UIView()
        TicketRow.registerNibCells(forTableView: self.tableView)

        if self.order.linkedBrokerAccount?.linkedBroker?.brokerName == "CIMB" {
            marketDataLabel.isHidden = true
        } else {
            marketDataLabel.isHidden = false
        }
        
        TradeItSDK.adService.populate(
            adContainer: adContainer,
            rootViewController: self,
            pageType: .trading,
            position: .bottom,
            broker: self.order.linkedBrokerAccount?.linkedBroker?.brokerName,
            symbol: self.order.symbol,
            instrumentType: TradeItTradeInstrumentType.equities.rawValue,
            trackPageViewAsPageType: true
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

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
        
        if let symbol = self.order.symbol {
            streamingMarketDataService?.startUpdatingQuote(forSymbol: symbol, onUpdate: updateQuotePrice, onFailure: self.clearMarketData)
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        streamingMarketDataService?.stopUpdatingQuote()
    }

    // MARK: UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let ticketRow = self.ticketRows[indexPath.row]

        switch ticketRow {
        case .symbol:
            self.navigationController?.pushViewController(self.symbolSearchViewController, animated: true)
        case .account:
            self.pushAccountSelection()
        case .orderAction:
            self.pushOrderCapabilitiesSelection(ticketRow: ticketRow, field: .actions, value: self.order.action.rawValue) { selection in
                self.order.action = TradeItOrderAction(value: selection)
                self.updateOrderQuantityTypeConstraints()
            }
        case .orderType:
            self.pushOrderCapabilitiesSelection(ticketRow: ticketRow, field: .priceTypes, value: self.order.type.rawValue) { selection in
                self.order.type = TradeItOrderPriceType(value: selection)
                let orderExpirationValue = self.orderCapabilities?.defaultValueFor(field: .expirationTypes, value: nil) ?? TradeItOrderActionPresenter.DEFAULT.rawValue
                self.order.expiration = TradeItOrderExpiration(value: orderExpirationValue)
                self.updateOrderQuantityTypeConstraints()
            }
        case .expiration:
            self.pushOrderCapabilitiesSelection(ticketRow: ticketRow, field: .expirationTypes, value: self.order.expiration.rawValue) { selection in
                self.order.expiration = TradeItOrderExpiration(value: selection)
            }
        case .marginType:
            self.selectionViewController.title = "Select " + ticketRow.getTitle(forOrder: self.order).lowercased()
            self.selectionViewController.initialSelection = MarginPresenter.labelFor(value: self.order.userDisabledMargin)
            self.selectionViewController.selections = MarginPresenter.LABELS
            self.selectionViewController.onSelected = { selection in
                self.order.userDisabledMargin = MarginPresenter.valueFor(label: selection)
                _ = self.navigationController?.popViewController(animated: true)
            }
            self.navigationController?.pushViewController(selectionViewController, animated: true)
        case .quantity:
            self.pushOrderQuantityTypeSelection()
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
        guard let linkedBroker = self.order.linkedBrokerAccount?.linkedBroker
            else { return }

        let activityView = MBProgressHUD.showAdded(to: self.view, animated: true)
        activityView.label.text = "Authenticating"

        linkedBroker.authenticateIfNeeded(
            onSuccess: {
                activityView.label.text = "Previewing Order"
                self.order.preview(
                    onSuccess: { previewOrderResult, placeOrderCallback in
                        activityView.hide(animated: true)
                        self.delegate?.orderSuccessfullyPreviewed(
                            onTradingTicketViewController: self,
                            withPreviewOrderResult: previewOrderResult,
                            placeOrderCallback: placeOrderCallback
                        )
                    }, onFailure: { errorResult in
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

    // MARK: TradeItAccountSelectionViewControllerDelegate

    func accountSelectionViewController(
        _ accountSelectionViewController: TradeItAccountSelectionViewController,
        didSelectLinkedBrokerAccount linkedBrokerAccount: TradeItLinkedBrokerAccount
    ) {
        self.order.linkedBrokerAccount = linkedBrokerAccount
        self.selectedAccountChanged = true
        _ = self.navigationController?.popViewController(animated: true)
    }

    // MARK: TradeItSymbolSearchViewControllerDelegate

    func symbolSearchViewController(
        _ symbolSearchViewController: TradeItSymbolSearchViewController,
        didSelectSymbol selectedSymbol: String
    ) {
        self.order.symbol = selectedSymbol
        self.clearMarketData()
        self.updateMarketData()
        _ = symbolSearchViewController.navigationController?.popViewController(animated: true)
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
                guard let orderCapabilities = (self.order.linkedBrokerAccount?.orderCapabilities.filter { $0.instrument == "equities" })?.first else {
                    self.alertManager.showAlertWithMessageOnly(
                        onViewController: self,
                        withTitle: "Unsupported Account",
                        withMessage: "The selected account does not support trading stocks. Please choose another account.",
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
                self.orderCapabilities = orderCapabilities
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
        self.order.action = TradeItOrderAction(
            value: self.orderCapabilities?.defaultValueFor(
                field: .actions,
                value: self.order.action.rawValue
            )
        )
        self.order.type = TradeItOrderPriceType(
            value: self.orderCapabilities?.defaultValueFor(
                field: .priceTypes,
                value: self.order.type.rawValue
            )
        )
        self.order.expiration = TradeItOrderExpiration(
            value: self.orderCapabilities?.defaultValueFor(
                field: .expirationTypes,
                value: self.order.expiration.rawValue
            )
        )
        self.order.userDisabledMargin = false
    }

    private func setPreviewButtonEnablement() {
        if self.order.isValid() {
            self.previewOrderButton.enable()
        } else {
            self.previewOrderButton.disable()
        }
    }

    private func updateMarketData() {
        self.quote = nil
        self.reload(row: .marketPrice)
        self.reload(row: .estimatedCost)

        guard let symbol = self.order.symbol else {
            self.clearMarketData()
            return
        }
        
        if streamingMarketDataService == nil {
            self.marketDataService.getQuote(symbol: symbol, onSuccess: updateQuotePrice, onFailure: { _ in self.clearMarketData() })
        }
    }

    private func clearMarketData() {
        self.quote = nil
        self.order.quoteLastPrice = nil
        self.reload(row: .marketPrice)
        self.reload(row: .estimatedCost)
    }

    private func reloadTicketRows() {
        self.setTitle()
        self.setPreviewButtonEnablement()

        let ticketRows: [TicketRow] = [
            .account,
            .orderAction,
            .symbol,
            .orderType,
            .expiration,
            self.order.userCanDisableMargin() ? .marginType : nil,
            .quantity,
            self.order.requiresLimitPrice() ? .limitPrice : nil,
            self.order.requiresStopPrice() ?.stopPrice : nil,
            .marketPrice,
            .estimatedCost
        ].compactMap { $0 }

        self.ticketRows = ticketRows

        self.tableView.reloadData()
    }
    
    private func reload(row: TicketRow, animation: UITableViewRowAnimation = .automatic) {
        guard let indexOfRow = self.ticketRows.index(of: row) else {
            return
        }

        let indexPath = IndexPath.init(row: indexOfRow, section: 0)
        self.tableView.reloadRows(at: [indexPath], with: animation)
    }

    private func provideCell(rowIndex: Int) -> UITableViewCell {
        let ticketRow = self.ticketRows[rowIndex]

        let cell = tableView.dequeueReusableCell(withIdentifier: ticketRow.cellReuseId) ?? UITableViewCell()
        let label = ticketRow.getTitle(forOrder: self.order)
        switch cell {
        case let selectionDetailCell as TradeItSelectionDetailCellTableViewCell:
            selectionDetailCell.altTitle.text = label
            break
        default:
            cell.textLabel?.text = label
            break
        }

        cell.selectionStyle = .none
        
        TradeItThemeConfigurator.configure(view: cell)
        
        guard let equityOrderCapabilities = self.orderCapabilities else { return cell }
        
        switch ticketRow {
        case .symbol:
            cell.detailTextLabel?.text = self.order.symbol
        case .orderAction:
            cell.detailTextLabel?.text = equityOrderCapabilities.labelFor(field: .actions, value: self.order.action.rawValue)
        case .quantity:
            let cell = cell as? TradeItNumericToggleInputCell
            cell?.configure(
                onValueUpdated: { newValue in
                    self.order.quantity = newValue
                    self.reload(row: .estimatedCost)
                    self.setPreviewButtonEnablement()
                },
                onQuantityTypeTapped: self.pushOrderQuantityTypeSelection
            )
            cell?.configureQuantityType(
                label: self.order.quantityTypeLabel,
                quantity: self.order.quantity,
                maxDecimalPlaces: equityOrderCapabilities.maxDecimalPlacesFor(orderQuantityType: self.order.quantityType),
                showToggle: supportedOrderQuantityTypes.count > 1
            )
        case .limitPrice:
            let cell = cell as? TradeItNumericToggleInputCell
            cell?.configure(
                onValueUpdated: { newValue in
                    self.order.limitPrice = newValue
                    self.reload(row: .estimatedCost)
                    self.setPreviewButtonEnablement()
                }
            )
            cell?.configureQuantityType(
                label: self.order.linkedBrokerAccount?.accountBaseCurrency,
                quantity: self.order.limitPrice,
                maxDecimalPlaces: equityOrderCapabilities.maxDecimalPlacesFor(orderQuantityType: .quoteCurrency)
            )
        case .stopPrice:
            let cell = cell as? TradeItNumericToggleInputCell
            cell?.configure(
                onValueUpdated: { newValue in
                    self.order.stopPrice = newValue
                    self.reload(row: .estimatedCost)
                    self.setPreviewButtonEnablement()
                }
            )
            cell?.configureQuantityType(
                label: self.order.linkedBrokerAccount?.accountBaseCurrency,
                quantity: self.order.stopPrice,
                maxDecimalPlaces: equityOrderCapabilities.maxDecimalPlacesFor(orderQuantityType: .quoteCurrency)
            )
        case .marketPrice:
            guard let marketCell = cell as? TradeItSubtitleWithDetailsCellTableViewCell else { return cell }
            let quotePresenter = TradeItQuotePresenter(self.order.linkedBrokerAccount?.accountBaseCurrency)
            marketCell.configure(
                subtitleLabel: quotePresenter.formatTimestamp(quote?.dateTime),
                detailsLabel: quotePresenter.formatCurrency(quote?.lastPrice),
                subtitleDetailsLabel: quotePresenter.formatChange(
                    change: quote?.change,
                    percentChange: quote?.pctChange
                ),
                subtitleDetailsLabelColor: TradeItQuotePresenter.getChangeLabelColor(changeValue: quote?.change)
            )
        case .marginType:
            cell.detailTextLabel?.text = MarginPresenter.labelFor(value: self.order.userDisabledMargin)
        case .estimatedCost:
            cell.detailTextLabel?.text = order.formattedEstimatedChange() ?? "N/A"
        case .orderType:
            cell.detailTextLabel?.text = self.orderCapabilities?.labelFor(field: .priceTypes, value: self.order.type.rawValue)
        case .expiration:
            cell.detailTextLabel?.text = self.orderCapabilities?.labelFor(field: .expirationTypes, value: self.order.expiration.rawValue)
        case .account:
            guard let detailCell = cell as? TradeItSelectionDetailCellTableViewCell else { return cell }
            detailCell.textLabel?.isHidden = true
            detailCell.configure(
                detailPrimaryText: self.order.linkedBrokerAccount?.getFormattedAccountName(),
                detailSecondaryText: accountSecondaryText(),
                altTitleText: ticketRow.getTitle(forOrder: self.order)
            )
        default:
            break
        }
        return cell
    }

    private func valueOrUnavailable(_ value: NSNumber) -> String {
        if (value == 0.0) {
            return "Unavailable"
        } else {
            return NumberFormatter.formatCurrency(value, currencyCode: self.order.linkedBrokerAccount?.accountBaseCurrency)
        }
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
        let buyingPowerLabel = self.order.linkedBrokerAccount?.balance?.buyingPowerLabel ?? "Buying Power"
        let buyingPowerValue = NumberFormatter.formatCurrency(buyingPower, currencyCode: self.order.linkedBrokerAccount?.accountBaseCurrency)
        return buyingPowerLabel + ": " + buyingPowerValue
    }

    private func sharesOwnedText() -> String? {
        guard let positions = self.order.linkedBrokerAccount?.positions, !positions.isEmpty else { return nil }

        let positionMatchingSymbol = positions.filter { portfolioPosition in
            TradeItPortfolioEquityPositionPresenter(portfolioPosition).getFormattedSymbol() == self.order.symbol
            }.first

        let sharesOwned = positionMatchingSymbol?.position?.quantity ?? 0 as NSNumber
        return "Shares Owned: " + NumberFormatter.formatQuantity(sharesOwned)
    }
    
    private func updateOrderQuantityTypeConstraints() {
        if !supportedOrderQuantityTypes.contains(self.order.quantityType) {
            self.order.quantity = nil
            self.order.quantityType = supportedOrderQuantityTypes.first ?? .shares
            self.reload(row: .quantity)
        }
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

    private func pushOrderQuantityTypeSelection() {
        if self.supportedOrderQuantityTypes.count <= 1 { return }

        self.selectionViewController.title = "Select quantity type"

        self.selectionViewController.initialSelection = self.order.quantityTypeLabel
        self.selectionViewController.selections = ["Shares", self.order.linkedBrokerAccount?.accountBaseCurrency].compactMap { $0 }
        self.selectionViewController.onSelected = { selection in
            let selectedQuantityType = selection == "Shares" ? OrderQuantityType.shares : OrderQuantityType.totalPrice
            self.order.quantityType = selectedQuantityType
            _ = self.navigationController?.popViewController(animated: true)
        }

        self.navigationController?.pushViewController(self.selectionViewController, animated: true)
    }
}

protocol TradeItTradingTicketViewControllerDelegate: class {
    func orderSuccessfullyPreviewed(
        onTradingTicketViewController tradingTicketViewController: TradeItTradingTicketViewController,
        withPreviewOrderResult previewOrderResult: TradeItPreviewOrderResult,
        placeOrderCallback: @escaping TradeItPlaceOrderHandlers
    )

    func invalidAccountSelected(
        onTradingTicketViewController tradingTicketViewController: TradeItTradingTicketViewController,
        withOrder order: TradeItOrder
    )
}

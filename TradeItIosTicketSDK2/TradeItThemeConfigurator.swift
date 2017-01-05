@objc class TradeItThemeConfigurator: NSObject {
    static let ACCESSIBILITY_IDENTIFIERS_TO_HIGHLIGHT = [
        "STOCK_SYMBOL",
        "CHEVRON_UP",
        "CHEVRON_DOWN",
        "NATIVE_ARROW",
        "SELECTED_INDICATOR"
    ]

    static let CELL_ELEMENTS_TO_SKIP = [
        "POSITION_DETAILS_VIEW"
    ]

    static let BUTTON_TEXT_TO_HIGHLIGHT = [
        "Unlink Account"
    ]

    static func configure(view: UIView?) {
        guard let view = view else { return }
        view.backgroundColor = TradeItSDK.theme.backgroundColor
        configureTheme(view: view)
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    static func configureTableHeader(header: UIView?) {
        guard let header = header else { return }
        configureTableHeaderTheme(view: header)
    }

    static func configureTableCell(cell: UITableViewCell?) {
        guard let cell = cell else { return }
        cell.backgroundColor = TradeItSDK.theme.tableBackgroundColor
        configureTableCellTheme(view: cell)
    }

    private static func configureTableHeaderTheme(view: UIView) {
        switch view {
        case let label as UILabel:
            label.textColor = TradeItSDK.theme.tableHeaderTextColor
        default:
            view.backgroundColor = TradeItSDK.theme.tableHeaderBackgroundColor
        }

        view.subviews.forEach { subview in
            configureTableHeaderTheme(view: subview)
        }
    }

    private static func configureTableCellTheme(view: UIView) {
        switch view {
        case let label as UILabel:
            if isViewToHighlight(label) {
                label.textColor = TradeItSDK.theme.interactivePrimaryColor
            } else {
                label.textColor = TradeItSDK.theme.tableHeaderTextColor
            }
        case let button as UIButton:
            styleButton(button)
        case let imageView as UIImageView:
            styleImage(imageView)
        case let input as UISwitch:
            styleSwitch(input)
        default:
            break
        }

        if !self.CELL_ELEMENTS_TO_SKIP.contains(view.accessibilityIdentifier ?? "") {
            view.subviews.forEach { subview in
                configureTableCellTheme(view: subview)
            }
        }
    }

    private static func configureTheme(view: UIView) {
        switch view {
        case let label as UILabel:
            label.textColor = TradeItSDK.theme.textColor
        case let button as UIButton:
            styleButton(button)
        case let input as UITextField:
            input.backgroundColor = UIColor.clear
            input.layer.borderColor = TradeItSDK.theme.inputFrameColor.cgColor
            input.layer.borderWidth = 1
            input.layer.cornerRadius = 4
            input.layer.masksToBounds = true
            input.textColor = TradeItSDK.theme.textColor
            input.attributedPlaceholder = NSAttributedString(
                string: input.placeholder ?? "",
                attributes: [NSForegroundColorAttributeName: TradeItSDK.theme.inputFrameColor]
            )
        case let input as UISwitch:
            styleSwitch(input)
        case let imageView as UIImageView:
            styleImage(imageView)
        case let tableView as UITableView:
            tableView.backgroundColor = TradeItSDK.theme.tableBackgroundColor
        case let activityIndicator as UIActivityIndicatorView:
            activityIndicator.color = TradeItSDK.theme.interactivePrimaryColor
        case is UITableViewCell:
            break
        default:
            break
        }

        view.subviews.forEach { subview in
            configureTheme(view: subview)
        }
    }

    private static func styleImage(_ imageView: UIImageView) {
        if isViewToHighlight(imageView) {
            let image = imageView.image?.withRenderingMode(.alwaysTemplate)
            imageView.image = image
            imageView.tintColor = TradeItSDK.theme.interactivePrimaryColor
        }
    }

    private static func styleButton(_ button: UIButton) {
        if button.backgroundColor == UIColor.clear {
            button.setTitleColor(TradeItSDK.theme.interactivePrimaryColor, for: .normal)
        } else if self.BUTTON_TEXT_TO_HIGHLIGHT.contains(button.title(for: .normal) ?? "") {
            button.setTitleColor(TradeItSDK.theme.warningSecondaryColor, for: .normal)
            button.backgroundColor = TradeItSDK.theme.warningPrimaryColor
        } else {
            button.setTitleColor(TradeItSDK.theme.interactiveSecondaryColor, for: .normal)
            button.backgroundColor = TradeItSDK.theme.interactivePrimaryColor
        }
    }

    private static func styleSwitch(_ input: UISwitch) {
        input.tintColor = TradeItSDK.theme.interactivePrimaryColor
        input.onTintColor = TradeItSDK.theme.interactivePrimaryColor
    }

    private static func isViewToHighlight(_ view: UIView) -> Bool {
        return self.ACCESSIBILITY_IDENTIFIERS_TO_HIGHLIGHT.contains(view.accessibilityIdentifier ?? "")
    }
}

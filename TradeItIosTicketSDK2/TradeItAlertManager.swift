import UIKit

@objc public class TradeItAlertManager: NSObject {
    private var alertQueue = TradeItAlertQueue.sharedInstance
    var linkBrokerUIFlow: LinkBrokerUIFlow = TradeItLinkBrokerUIFlow()

    init(linkBrokerUIFlow: LinkBrokerUIFlow) {
        self.linkBrokerUIFlow = linkBrokerUIFlow

        super.init()
    }

    @objc public override init() {
        super.init()
    }

    @objc public func showError(
        _ error: TradeItErrorResult,
        onViewController viewController: UIViewController,
        onFinished: @escaping () -> Void = {}
    ) {
        self.showAlertWithMessageOnly(
            onViewController: viewController,
            withTitle: error.title,
            withMessage: error.message,
            withActionTitle: "OK",
            errorToReport: error,
            onAlertActionTapped: onFinished
        )
    }

    @objc public func showAlertWithAction(
        error: TradeItErrorResult,
        withLinkedBroker linkedBroker: TradeItLinkedBroker?,
        onViewController viewController: UIViewController,
        onFinished: @escaping () -> Void = {}
    ) {
        self.showAlertWithAction(
            error: error,
            withLinkedBroker: linkedBroker,
            onViewController: viewController,
            oAuthCallbackUrl: TradeItSDK.oAuthCallbackUrl,
            onFinished: onFinished
        )
    }


    @objc public func showAlertWithAction(
        error: TradeItErrorResult,
        withLinkedBroker linkedBroker: TradeItLinkedBroker?,
        onViewController viewController: UIViewController,
        oAuthCallbackUrl: URL,
        onFinished: @escaping () -> Void = {}
    ) {
        guard let linkedBroker = linkedBroker else {
            return self.showError(
                error,
                onViewController: viewController,
                onFinished: onFinished
            )
        }

        let onAlertActionRelinkAccount: () -> Void = {
            self.linkBrokerUIFlow.presentRelinkBrokerFlow(
                inViewController: viewController,
                linkedBroker: linkedBroker,
                oAuthCallbackUrl: oAuthCallbackUrl
            )
        }
        
        let onAlertRetryAuthentication: () -> Void = { () in
            linkedBroker.authenticate(
                onSuccess: {
                    onFinished()
                },
                onSecurityQuestion: { securityQuestion, answerSecurityQuestion, cancelQuestion in
                    self.promptUserToAnswerSecurityQuestion(
                        securityQuestion,
                        onViewController: viewController,
                        onAnswerSecurityQuestion: answerSecurityQuestion,
                        onCancelSecurityQuestion: onFinished
                    )
                },
                onFailure: { (TradeItErrorResult) in
                    onFinished()
                }
            )
        }

        switch error.errorCode {
        case .brokerLinkError?:
            self.showAlertWithMessageOnly(
                onViewController: viewController,
                withTitle: error.title,
                withMessage: error.message,
                withActionTitle: "Update",
                errorToReport: error,
                onAlertActionTapped: onAlertActionRelinkAccount,
                showCancelAction: true,
                onCancelActionTapped: onFinished
            )
        case .oauthError?:
            self.showAlertWithMessageOnly(
                onViewController: viewController,
                withTitle: error.title,
                withMessage: error.message,
                withActionTitle: "Update",
                errorToReport: error,
                onAlertActionTapped: onAlertActionRelinkAccount,
                showCancelAction: true,
                onCancelActionTapped: onFinished
            )
        case .sessionError?:
            self.showAlertWithMessageOnly(
                onViewController: viewController,
                withTitle: error.title,
                withMessage: error.message,
                withActionTitle: "Refresh",
                errorToReport: error,
                onAlertActionTapped: onAlertRetryAuthentication,
                showCancelAction: true,
                onCancelActionTapped: onFinished
            )
        default:
            self.showError(
                error,
                onViewController: viewController,
                onFinished: onFinished
            )
        }
    }

    @objc public func promptUserToAnswerSecurityQuestion(
        _ securityQuestion: TradeItSecurityQuestionResult,
        onViewController viewController: UIViewController,
        onAnswerSecurityQuestion: @escaping (_ withAnswer: String) -> Void,
        onCancelSecurityQuestion: @escaping () -> Void
    ) {
        let alert = TradeItAlertProvider.provideSecurityQuestionAlertWith(
            alertTitle: "Security Question",
            alertMessage: securityQuestion.securityQuestion ?? "No security question provided.",
            multipleOptions: securityQuestion.securityQuestionOptions ?? [],
            alertActionTitle: "Submit",
            onAnswerSecurityQuestion: { answer in
                onAnswerSecurityQuestion(answer)
                self.alertQueue.alertFinished()
            },
            onCancelSecurityQuestion: {
                onCancelSecurityQuestion()
                self.alertQueue.alertFinished()
            }
        )
        alertQueue.add(onViewController: viewController, alert: alert)
    }

    @objc public func showAlertWithMessageOnly(
        onViewController viewController: UIViewController,
        withTitle title: String,
        withMessage message: String,
        withActionTitle actionTitle: String,
        withCancelTitle cancelTitle: String = "Cancel",
        errorToReport: TradeItErrorResult? = nil,
        onAlertActionTapped: @escaping () -> Void = {},
        showCancelAction: Bool = false,
        onCancelActionTapped: (() -> Void)? = nil
    ) {
        NotificationCenter.default.post(
            name: TradeItNotification.Name.alertShown,
            object: nil,
            userInfo: [
                TradeItNotification.UserInfoKey.view.rawValue: viewController.classForCoder,
                TradeItNotification.UserInfoKey.alertTitle.rawValue: title,
                TradeItNotification.UserInfoKey.alertMessage.rawValue: message,
                TradeItNotification.UserInfoKey.error.rawValue: errorToReport as Any
            ]
        )

        let alert = TradeItAlertProvider.provideAlert(
            alertTitle: title,
            alertMessage: message,
            alertActionTitle: actionTitle,
            alertCancelTitle: cancelTitle,
            onAlertActionTapped: {
                onAlertActionTapped()
                self.alertQueue.alertFinished()
            },
            showCancelAction: showCancelAction,
            onCanceledActionTapped: {
                onCancelActionTapped?()
                self.alertQueue.alertFinished()
            }
        )

        alertQueue.add(onViewController: viewController, alert: alert)
    }
}

private class TradeItAlertQueue {
    static let sharedInstance = TradeItAlertQueue()
    private typealias AlertContext = (onViewController: UIViewController, alertController: UIAlertController)

    private var queue: [AlertContext] = []
    private var alreadyPresentingAlert = false

    private init() {}

    func add(onViewController viewController: UIViewController, alert: UIAlertController) {
        queue.append((viewController, alert))
        self.showNextAlert()
    }

    func alertFinished() {
        alreadyPresentingAlert = false
        showNextAlert()
    }

    func showNextAlert() {
        if alreadyPresentingAlert || queue.isEmpty { return }
        let alertContext = queue.removeFirst()
        alreadyPresentingAlert = true // TODO: Should this be moved up one line to decrease chance of race condition?

        if alertContext.onViewController.isViewLoaded && (alertContext.onViewController.view.window != nil) {
            alertContext.onViewController.present(alertContext.alertController, animated: true, completion: nil)
        } else {
            self.alertFinished()
        }
    }
}

import UIKit
import WebKit

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

    private var webView: WKWebView!
    private let refreshControl = UIRefreshControl()
    private let placeholderView = UIView()
    private var placeholderComposer: UIView?
    private var pageReadyObserver: NSObjectProtocol?
    private var hasPresentedWebContent = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        webView = WebViewStore.shared.webView
        webView.removeFromSuperview()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        refreshControl.tintColor = .secondaryLabel
        refreshControl.addTarget(self, action: #selector(reloadPage), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        configureLaunchPlaceholder()
        observePageReadiness()
        WebViewStore.shared.loadIfNeeded()

        // The shared web view may already be ready by the time this controller
        // attaches to it during a warm scene connection.
        if webView.url != nil, !webView.isLoading {
            hideLaunchPlaceholder(animated: false)
        }
    }

    @objc private func reloadPage() {
        WebViewStore.shared.reloadOrLoadHome()
    }

    deinit {
        if let pageReadyObserver {
            NotificationCenter.default.removeObserver(pageReadyObserver)
        }
    }

    private func configureLaunchPlaceholder() {
        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.backgroundColor = .systemBackground
        placeholderView.isUserInteractionEnabled = false
        placeholderView.accessibilityLabel = "正在打开 ChatGPT"
        view.addSubview(placeholderView)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "ChatGPT"
        titleLabel.textColor = .label
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        placeholderView.addSubview(titleLabel)

        let markView = UIImageView(image: UIImage(systemName: "sparkles"))
        markView.translatesAutoresizingMaskIntoConstraints = false
        markView.tintColor = .label
        markView.contentMode = .scaleAspectFit
        placeholderView.addSubview(markView)

        let composer = UIView()
        composer.translatesAutoresizingMaskIntoConstraints = false
        composer.backgroundColor = .secondarySystemBackground
        composer.layer.cornerRadius = 27
        composer.layer.borderWidth = 0.5
        composer.layer.borderColor = UIColor.separator.cgColor
        placeholderView.addSubview(composer)
        placeholderComposer = composer

        let promptLabel = UILabel()
        promptLabel.translatesAutoresizingMaskIntoConstraints = false
        promptLabel.text = "询问任何问题"
        promptLabel.textColor = .placeholderText
        promptLabel.font = .systemFont(ofSize: 16)
        composer.addSubview(promptLabel)

        let sendView = UIImageView(image: UIImage(systemName: "arrow.up.circle.fill"))
        sendView.translatesAutoresizingMaskIntoConstraints = false
        sendView.tintColor = .tertiaryLabel
        sendView.contentMode = .scaleAspectFit
        composer.addSubview(sendView)

        NSLayoutConstraint.activate([
            placeholderView.topAnchor.constraint(equalTo: view.topAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            placeholderView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: placeholderView.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: placeholderView.safeAreaLayoutGuide.topAnchor, constant: 13),

            markView.centerXAnchor.constraint(equalTo: placeholderView.centerXAnchor),
            markView.centerYAnchor.constraint(equalTo: placeholderView.centerYAnchor, constant: -24),
            markView.widthAnchor.constraint(equalToConstant: 32),
            markView.heightAnchor.constraint(equalToConstant: 32),

            composer.leadingAnchor.constraint(equalTo: placeholderView.leadingAnchor, constant: 14),
            composer.trailingAnchor.constraint(equalTo: placeholderView.trailingAnchor, constant: -14),
            composer.bottomAnchor.constraint(equalTo: placeholderView.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            composer.heightAnchor.constraint(equalToConstant: 54),

            promptLabel.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 18),
            promptLabel.centerYAnchor.constraint(equalTo: composer.centerYAnchor),

            sendView.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -10),
            sendView.centerYAnchor.constraint(equalTo: composer.centerYAnchor),
            sendView.widthAnchor.constraint(equalToConstant: 32),
            sendView.heightAnchor.constraint(equalToConstant: 32)
        ])

        UIView.animate(
            withDuration: 0.9,
            delay: 0,
            options: [.autoreverse, .repeat, .allowUserInteraction]
        ) {
            composer.alpha = 0.62
        }
    }

    private func observePageReadiness() {
        pageReadyObserver = NotificationCenter.default.addObserver(
            forName: .chatGPTPageReady,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hideLaunchPlaceholder(animated: true)
        }
    }

    private func showLaunchPlaceholder() {
        guard !hasPresentedWebContent else { return }
        placeholderView.isHidden = false
        placeholderView.alpha = 1
        view.bringSubviewToFront(placeholderView)
    }

    private func hideLaunchPlaceholder(animated: Bool) {
        guard !hasPresentedWebContent else { return }
        hasPresentedWebContent = true
        placeholderComposer?.layer.removeAllAnimations()

        let completion: (Bool) -> Void = { [weak self] _ in
            self?.placeholderView.isHidden = true
        }
        if animated {
            UIView.animate(withDuration: 0.22, animations: {
                self.placeholderView.alpha = 0
            }, completion: completion)
        } else {
            placeholderView.alpha = 0
            completion(true)
        }
    }

    // 登录授权流程涉及的域名，必须留在 App 内 WebView 完成，
    // 跳到外部 Safari 会导致会话丢失、登录失败。
    private func isAuthFlowURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let authDomains = [
            "chatgpt.com",
            "openai.com",
            "auth0.com",
            "workos.com",
            "accounts.google.com",
            "appleid.apple.com",
            "login.microsoftonline.com",
            "account.live.com"
        ]
        return authDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshControl.endRefreshing()
        hideLaunchPlaceholder(animated: true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        refreshControl.endRefreshing()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        hasPresentedWebContent = false
        showLaunchPlaceholder()
        WebViewStore.shared.reloadOrLoadHome()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        refreshControl.endRefreshing()

        // 用户取消跳转等非真实错误不提示
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }

        let alert = UIAlertController(title: "加载失败", message: "请检查网络连接后重试", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "重试", style: .default) { _ in
            WebViewStore.shared.reloadOrLoadHome()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    // 网页内导航放行；mailto/tel 等非 http(s) 链接交给系统
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme != "http", scheme != "https" {
            if navigationAction.navigationType == .linkActivated,
               UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // 新窗口链接：登录授权域名在 App 内继续，其余跳系统 Safari
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let url = navigationAction.request.url else {
            return nil
        }
        if isAuthFlowURL(url) {
            webView.load(URLRequest(url: url))
        } else if url.scheme?.lowercased().hasPrefix("http") == true {
            UIApplication.shared.open(url)
        }
        return nil
    }

    // 麦克风/相机权限授权给网页（语音对话、拍照上传）
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        let host = origin.host.lowercased()
        let trusted = host == "chatgpt.com" || host.hasSuffix(".chatgpt.com") ||
            host == "openai.com" || host.hasSuffix(".openai.com")
        decisionHandler(trusted ? .grant : .prompt)
    }

    // 网页 alert() 弹窗，不实现会导致页面 JS 挂起卡死
    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler()
        })
        present(alert, animated: true)
    }

    // 网页 confirm() 弹窗
    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler(true)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            completionHandler(false)
        })
        present(alert, animated: true)
    }

    // 网页 prompt() 输入框
    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = defaultText
        }
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            completionHandler(nil)
        })
        present(alert, animated: true)
    }

    // 状态栏颜色跟随系统深浅色
    override var preferredStatusBarStyle: UIStatusBarStyle {
        traitCollection.userInterfaceStyle == .dark ? .lightContent : .darkContent
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            setNeedsStatusBarAppearanceUpdate()
            WebViewStore.shared.applySystemTheme()
        }
    }
}

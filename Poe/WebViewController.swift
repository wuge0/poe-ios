//
//  WebViewController.swift
//  Poe
//
//  核心：WKWebView 容器。没有地址栏、没有工具栏，就是纯站点观感。
//

import UIKit
import WebKit

final class WebViewController: UIViewController {

    // MARK: - 属性

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()

        // 尽量贴近真机 Safari 的行为，降低被 Cloudflare 判定为机器人的概率
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()

        // 允许页面在原生 App 内正常处理弹窗
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self

        // 客户端观感：让页面自行处理安全区，
        // 避免聊天输入框被 Home Indicator 遮挡
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.allowsBackForwardNavigationGestures = Config.enableBackGesture

        // 隐藏滚动条，更像原生
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false

        if let userAgent = Config.customUserAgent {
            webView.customUserAgent = userAgent
        }

        return webView
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.tintColor = .secondaryLabel
        control.accessibilityLabel = "刷新"
        control.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        return control
    }()

    private lazy var progressBar: UIProgressView = {
        let bar = UIProgressView(progressViewStyle: .bar)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.trackTintColor = .clear
        bar.progressTintColor = .label
        bar.alpha = 0
        return bar
    }()

    private lazy var errorView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .systemBackground
        container.isHidden = true

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center

        let icon = UIImageView(image: UIImage(systemName: "wifi.exclamationmark"))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let title = UILabel()
        title.text = "无法连接"
        title.font = .preferredFont(forTextStyle: .headline)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = .label
        title.textAlignment = .center

        let message = UILabel()
        message.text = "请检查网络连接后重试"
        message.font = .preferredFont(forTextStyle: .subheadline)
        message.adjustsFontForContentSizeCategory = true
        message.textColor = .secondaryLabel
        message.textAlignment = .center
        message.numberOfLines = 0

        let retryButton = UIButton(type: .system)
        retryButton.setTitle("重新加载", for: .normal)
        retryButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        retryButton.titleLabel?.adjustsFontForContentSizeCategory = true
        retryButton.accessibilityLabel = "重新加载页面"
        retryButton.addTarget(self, action: #selector(handleRetryButtonTap(_:)), for: .touchUpInside)
        // 触控目标不小于 44pt
        retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        retryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(message)
        stack.addArrangedSubview(retryButton)
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -32),
        ])

        return container
    }()

    private var progressObservation: NSKeyValueObservation?

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        if Config.followSystemAppearance {
            overrideUserInterfaceStyle = .unspecified
        }

        view.addSubview(webView)
        view.addSubview(errorView)
        view.addSubview(progressBar)

        if Config.enablePullToRefresh {
            webView.scrollView.refreshControl = refreshControl
        }

        // WebView 顶部对齐安全区（不被刘海遮挡），底部铺满整屏，
        // 底部避让交给页面的 env(safe-area-inset-bottom) 处理
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            errorView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            errorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            errorView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            progressBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 2),
        ])

        observeProgress()
        loadStartPage()
    }

    // MARK: - 加载

    private func loadStartPage() {
        log("加载首页: \(Config.startURL.absoluteString)")
        webView.load(URLRequest(url: Config.startURL, cachePolicy: .useProtocolCachePolicy))
    }

    /// 下拉刷新触发（UIRefreshControl 要求无参 selector）
    @objc private func handleRefresh() {
        reload()
    }

    /// 重试按钮触发（UIButton 的 action 必须接收 sender，
    /// 否则运行时抛 unrecognized selector）
    @objc private func handleRetryButtonTap(_ sender: UIButton) {
        reload()
    }

    private func reload() {
        errorView.isHidden = true
        if webView.url == nil {
            loadStartPage()
        } else {
            webView.reload()
        }
    }

    private func observeProgress() {
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            guard let self else { return }
            let progress = Float(webView.estimatedProgress)
            self.progressBar.setProgress(progress, animated: true)

            if progress >= 1.0 {
                UIView.animate(withDuration: 0.25) { self.progressBar.alpha = 0 }
            } else {
                self.progressBar.alpha = 1
            }
        }
    }

    // MARK: - 日志

    private func log(_ message: String) {
        guard Config.verboseLogging else { return }
        NSLog("[Poe] \(message)")
    }
}

// MARK: - WKNavigationDelegate

extension WebViewController: WKNavigationDelegate {

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let host = url.host?.lowercased() ?? ""
        log("导航: \(host)\(url.path)")

        // 非 http/https（比如 tel:、mailto:、自定义 scheme）交给系统
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        }

        // 第三方登录入口：WKWebView 内无法完成，直接说明原因
        if Config.blockedLoginHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            log("拦截第三方登录: \(host)")
            decisionHandler(.cancel)
            presentThirdPartyLoginNotice()
            return
        }

        // 站外链接交给系统浏览器
        if !isInAppHost(host) {
            // 用户主动点击才跳转；页面内部的接口调用、埋点保持放行
            if navigationAction.navigationType == .linkActivated {
                log("外链跳转系统浏览器: \(url.absoluteString)")
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel)
                return
            }
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        refreshControl.endRefreshing()
        errorView.isHidden = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshControl.endRefreshing()
        log("加载完成: \(webView.url?.absoluteString ?? "")")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }

    private func handleNavigationFailure(_ error: Error) {
        refreshControl.endRefreshing()

        let nsError = error as NSError
        // 取消类错误不算真失败（比如我们主动 cancel 的外链跳转）
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }

        log("加载失败: \(nsError.localizedDescription)")
        errorView.isHidden = false
    }

    private func isInAppHost(_ host: String) -> Bool {
        Config.inAppHosts.contains { base in
            host == base || host.hasSuffix("." + base)
        }
    }

    // MARK: - 提示

    private func presentThirdPartyLoginNotice() {
        let alert = UIAlertController(
            title: "请使用邮箱登录",
            message: "Google 与 Apple 账号不允许在 App 内登录。请返回上一页，选择「使用邮箱继续」完成登录。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - WKUIDelegate

extension WebViewController: WKUIDelegate {

    /// target="_blank" 或 window.open 时，在当前 WebView 打开，
    /// 否则新窗口请求会被静默丢弃，表现为「点了没反应」。
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // 说明：这里有意不实现 runOpenPanelWith。
    //
    // 两个原因：
    // 1. 该方法自 iOS 18.4 才可用，本 App 部署目标是 iOS 15，
    //    实现它会导致编译期可用性错误。
    // 2. Apple 文档明确指出：iOS 上「不实现该方法时文件上传默认就是启用的」
    //    （"By default on iOS, file uploads are enabled if you don't
    //    implement this method."），系统会给出默认的选择器。
    //
    // 所以页面里的文件上传无需我们插手，交给系统默认行为即可。
}

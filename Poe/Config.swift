//
//  Config.swift
//  Poe
//
//  集中配置。改行为只需要改这个文件。
//

import Foundation

enum Config {

    // MARK: - 站点

    /// 启动页
    static let startURL = URL(string: "https://poe.com")!

    /// 允许在 App 内打开的域名（含子域名匹配）。
    /// 不在这个列表里的链接一律交给系统浏览器，避免在套壳里迷路。
    static let inAppHosts: [String] = [
        "poe.com",
        "poecdn.net",
        "poecdn.com",
        "quora.com",
        "qprofile.com",
    ]

    // MARK: - 登录

    /// 这些域名是第三方登录入口。WKWebView 内无法完成 Google OAuth
    /// （Google 政策 disallowed_useragent），命中时给出提示而不是让用户
    /// 卡在一个永远转圈的页面上。
    static let blockedLoginHosts: [String] = [
        "accounts.google.com",
        "appleid.apple.com",
    ]

    // MARK: - 外观

    /// 自定义 UA。nil = 使用系统默认（与真机 Safari 特征一致，
    /// 最不容易触发 Cloudflare 的机器人校验）。
    static let customUserAgent: String? = nil

    /// 是否显示下拉刷新
    static let enablePullToRefresh = true

    /// 是否允许侧滑返回上一页
    static let enableBackGesture = true

    /// 是否启用深色模式跟随系统
    static let followSystemAppearance = true

    // MARK: - 调试

    /// 打开后在控制台输出导航与 Cookie 日志，用于排查
    /// Cloudflare 校验、登录态丢失等问题。
    static let verboseLogging = true
}

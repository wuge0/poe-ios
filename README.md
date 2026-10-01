# Poe iOS 客户端

把 [poe.com](https://poe.com) 打包成 iOS App，纯客户端观感。

用 **WKWebView 套壳**：约 5 MB、构建 3 分钟。不需要 Gecko 那样上百 MB 的浏览器引擎。

## 为什么这么轻

poe.com 在 iOS 15 的 Safari 里本来就能正常打开，系统 WebKit 完全够用。
不需要换内核，所以不需要 Reynard/Gecko 那套重型方案。

## 定制内容

| 项 | 说明 |
|---|---|
| 启动页 | `https://poe.com`，打开即进入 |
| 地址栏 | 无 |
| 工具栏 | 无，全屏内容 |
| 图标 | Poe 风格紫靛渐变圆标 |
| 下拉刷新 | 支持 |
| 侧滑返回 | 支持 |
| 外链 | 非 poe 域名交给系统浏览器 |
| 文件上传 | 支持（系统选取器） |
| 深色模式 | 跟随系统 |

所有开关集中在 `Poe/Config.swift`。

## 登录说明（重要）

**必须用邮箱登录。**

Google 与 Apple 账号**无法**在 App 内登录 —— Google 的 OAuth 2.0 政策明确禁止
内嵌 WebView 发起授权请求，会返回 `disallowed_useragent` 错误。这是 Google 的安全
策略（依据 RFC 8252 §8.1），不是代码能绕过的。

而且套壳方案无法自救：我们不是 poe 的 OAuth 客户端，拿不到 poe 的 client_id，
也无法注册 poe 的回调域名。即便用系统浏览器完成 Google 认证，换来的会话 Cookie
也落在系统浏览器容器里 —— 自 iOS 11 起 `SFSafariViewController` 不再与 WKWebView
共享 Cookie 存储，**Cookie 传不回来**。

配套行为：代码会拦截 Google/Apple 登录入口，弹窗引导你改用邮箱。

## 构建

GitHub Actions 自动构建（`.github/workflows/build.yml`）：

```bash
gh workflow run build.yml -R <owner>/poe-ios
```

产物：
- **Release 直链**（推荐，长期保留）
- Actions Artifacts（保留 30 天）

本地构建（需 macOS + Xcode）：

```bash
./tools/make-ipa.sh
# 产物: dist/Poe.ipa
```

## 安装

需要 **TrollStore**（iOS 14 – 16.6.1），无需签名：

1. 手机上点开 Release 里的 `Poe.ipa` 链接
2. 下载完成后 TrollStore 自动识别
3. 点安装

## 已知不确定性

poe.com 由 **Cloudflare** 前置，存在机器人校验。WKWebView 是最不容易触发拦截的
方案（真实移动 UA、完整 Cookie 支持、真实 JS 引擎），但**需要真机实测确认**。

若遇到验证页面，通常是 Cloudflare Turnstile，在 WebView 内可正常完成。

排查时打开 `Config.verboseLogging`，控制台会输出导航与拦截日志。

## 目录结构

```
Poe/
├── Config.swift            # 集中配置
├── WebViewController.swift # 核心：WKWebView 容器
├── AppDelegate.swift
├── SceneDelegate.swift
├── Info.plist
└── Assets.xcassets/
tools/
└── make-ipa.sh             # 打包无签名 IPA
```

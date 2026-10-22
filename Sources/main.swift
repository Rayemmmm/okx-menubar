import AppKit
import Darwin

struct Position: Decodable {
    let direction: String
    let contracts: Double
    let btc: Double?
    let entry: Double?
    let leverage: Double?
    let marginMode: String
    let floating: Double?
    let ratio: Double?
    let liquidation: Double?
    let realized: Double?
}
struct Algo: Decodable {
    let kind: String
    let side: String
    let size: Double?
    let closeFraction: Double?
    let tp: Double?
    let sl: Double?
    let tpType: String
    let slType: String
    let tpOrderPrice: String
    let slOrderPrice: String
    let callbackRatio: Double?
    let callbackSpread: Double?
}
struct Snapshot: Decodable {
    let status: String
    let fetchedAt: String
    let message: String?
    let tickerTime: String?
    let markTime: String?
    let valuationTime: String?
    let totalAssetsUSDT: Double?
    let totalBalanceSource: String?
    let fundingValuationUSDT: Double?
    let earnValuationUSDT: Double?
    let last: Double?
    let mark: Double?
    let equityUSD: Double?
    let equityUSDT: Double?
    let cashUSDT: Double?
    let availableUSDT: Double?
    let floatingUSDT: Double?
    let todayLedgerUSDT: Double?
    let todayBillCount: Int?
    let positions: [Position]?
    let ordinaryOrderCount: Int?
    let algos: [Algo]?
    let attached: [Algo]?
    let readOnly: Bool?
    let demo: Bool?
}

enum Freshness {
    static func date(_ text: String?) -> Date? {
        guard let text = text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
    static func valid(_ data: Snapshot, now: Date, interval: Double) -> Bool {
        guard data.status == "ok", data.readOnly == true, data.demo == false,
              let fetched = date(data.fetchedAt), let ticker = date(data.tickerTime),
              let mark = date(data.markTime), let valuation = date(data.valuationTime) else { return false }
        let limit = max(15, interval * 2)
        return [fetched, ticker, mark, valuation].allSatisfy {
            let age = now.timeIntervalSince($0)
            return age >= -5 && age <= limit
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var snapshot: Snapshot?
    private var lastSuccess: Date?
    private var failure: String?
    private var process: Process?
    private var refreshTimer: Timer?
    private var clockTimer: Timer?
    private var timeoutTimer: Timer?
    private var paused = false
    private var displayedState = ""
    private var diagnosticsPath: String?
    private var node: String { Bundle.main.resourceURL!.appendingPathComponent("runtime/node").path }
    private let defaults = UserDefaults.standard
    private var interval: Double {
        let saved = defaults.double(forKey: "refreshInterval")
        return [5.0, 10.0, 15.0, 30.0, 60.0].contains(saved) ? saved : 5
    }
    private var displayMode: String {
        let saved = defaults.string(forKey: "displayMode") ?? "balanceAndFloating"
        return ["balanceAndFloating", "floating", "equity", "today"].contains(saved) ? saved : "balanceAndFloating"
    }
    private var showBTCPrice: Bool {
        return defaults.object(forKey: "showBTCPrice") as? Bool ?? true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if defaults.integer(forKey: "refreshCadenceVersion") < 1 {
            defaults.set(5, forKey: "refreshInterval")
            defaults.set(1, forKey: "refreshCadenceVersion")
        }
        if defaults.integer(forKey: "balanceLayoutVersion") < 2 {
            defaults.set("balanceAndFloating", forKey: "displayMode")
            defaults.set(2, forKey: "balanceLayoutVersion")
        }
        if let index = CommandLine.arguments.firstIndex(of: "--diagnostics"), CommandLine.arguments.count > index + 1 {
            diagnosticsPath = CommandLine.arguments[index + 1]
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem.button?.setAccessibilityLabel("OKX 只读账户状态")
        render()
        schedule()
        clockTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.state() != self.displayedState { self.render() }
        }
        RunLoop.main.add(clockTimer!, forMode: .common)
        refresh()
    }
    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        clockTimer?.invalidate()
        timeoutTimer?.invalidate()
        process?.terminate()
    }
    private func state() -> String {
        if paused { return "paused" }
        if failure != nil { return "error" }
        guard let data = snapshot else { return "loading" }
        return Freshness.valid(data, now: Date(), interval: interval) ? "fresh" : "stale"
    }
    private func number(_ value: Double?, digits: Int = 2, signed: Bool = false) -> String {
        guard let value = value, value.isFinite else { return "未提供" }
        let rounded = abs(value) < pow(10.0, -Double(digits)) / 2 ? 0.0 : value
        return String(format: signed ? "%+.\(digits)f" : "%.\(digits)f", rounded)
    }
    private func time(_ date: Date?) -> String {
        guard let date = date else { return "未成功" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    private func info(_ title: String, bold: Bool = false, color: NSColor? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if bold || color != nil {
            item.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: bold ? .semibold : .regular),
                .foregroundColor: color ?? NSColor.labelColor,
            ])
        }
        return item
    }
    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }
    private func schedule() {
        refreshTimer?.invalidate()
        refreshTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }
    func menuWillOpen(_ menu: NSMenu) { render() }

    private func render() {
        guard statusItem != nil else { return }
        displayedState = state()
        let menu = statusItem.menu ?? NSMenu()
        menu.removeAllItems()
        menu.addItem(info("OKX · 实盘只读", bold: true))
        var title = "OKX 连接中…"
        var tint = NSColor.labelColor
        switch displayedState {
        case "fresh":
            guard let data = snapshot else { break }
            let value: Double?
            switch displayMode {
            case "balanceAndFloating":
                value = data.floatingUSDT
                let balance = data.totalAssetsUSDT == nil ? "总余额未知" : "总\(number(data.totalAssetsUSDT))U"
                let floating = data.positions?.isEmpty == true ? "BTC空仓"
                    : data.floatingUSDT == nil ? "浮盈未知" : "浮\(number(data.floatingUSDT, signed: true))U"
                title = "OKX \(balance) · \(floating)"
            case "equity":
                value = data.equityUSDT
                title = value == nil ? "OKX 权益未知" : "OKX 权益\(number(value))U"
            case "today":
                value = data.todayLedgerUSDT
                title = value == nil ? "OKX 今日未知" : "OKX 今\(number(value, signed: true))U"
            default:
                value = data.floatingUSDT
                if data.positions?.isEmpty == true { title = "OKX BTC空仓" }
                else { title = value == nil ? "OKX 浮盈未知" : "OKX 浮\(number(value, signed: true))U" }
            }
            if showBTCPrice {
                title += data.last == nil ? " · BTC价格未知" : " · BTC\(number(data.last, digits: 1))"
            }
            if displayMode != "equity", let value = value { tint = value > 0 ? .systemGreen : value < 0 ? .systemRed : .labelColor }
            menu.addItem(info(process == nil ? "查询正常 · 每 \(Int(interval)) 秒刷新" : "正在刷新…"))
            menu.addItem(.separator())
            menu.addItem(info("BTC 浮动盈亏  \(number(data.floatingUSDT, digits: 4, signed: true)) USDT", bold: true,
                              color: (data.floatingUSDT ?? 0) >= 0 ? .systemGreen : .systemRed))
            menu.addItem(info("总余额（折合 USDT）  \(number(data.totalAssetsUSDT, digits: 4)) USDT", bold: true))
            menu.addItem(info("USDT 现金余额（不含浮盈亏）  \(number(data.cashUSDT, digits: 4)) USDT"))
            menu.addItem(info("USDT 交易权益（含浮盈亏）  \(number(data.equityUSDT, digits: 4)) USDT"))
            menu.addItem(info("交易账户总权益  \(number(data.equityUSD, digits: 4)) USD"))
            menu.addItem(info("可用余额  \(number(data.availableUSDT, digits: 4)) USDT"))
            menu.addItem(info("今日永续净入账  \(number(data.todayLedgerUSDT, digits: 4, signed: true)) USDT"))
            menu.addItem(.separator())
            if data.positions?.isEmpty == true {
                menu.addItem(info("BTC-USDT-SWAP · 当前空仓"))
            }
            for position in data.positions ?? [] {
                menu.addItem(info("\(position.direction)单  \(number(position.contracts)) 张 · \(number(position.btc, digits: 6)) BTC", bold: true))
                let margin = position.marginMode == "cross" ? "全仓" : position.marginMode == "isolated" ? "逐仓" : "模式未知"
                menu.addItem(info("\(number(position.leverage, digits: 0)) 倍 · \(margin) · 收益率 \(number(position.ratio.map { $0 * 100 }, signed: true))%"))
                menu.addItem(info("开仓均价  \(number(position.entry)) USDT"))
                menu.addItem(info("预估强平价  \(number(position.liquidation)) USDT"))
            }
            menu.addItem(info("最新成交价  \(number(data.last)) · 标记价  \(number(data.mark))"))
            menu.addItem(.separator())
            let algos = data.algos ?? []
            let takeProfits = algos.filter { $0.tp != nil }
            let stopLosses = algos.filter { $0.sl != nil }
            for algo in takeProfits { menu.addItem(info("止盈  \(number(algo.tp)) · \(trigger(algo.tpType)) · \(algo.tpOrderPrice == "-1" ? "触发后市价" : "限价")")) }
            if takeProfits.isEmpty { menu.addItem(info("止盈：本次未查到")) }
            for algo in stopLosses { menu.addItem(info("止损  \(number(algo.sl)) · \(trigger(algo.slType)) · \(algo.slOrderPrice == "-1" ? "触发后市价" : "限价")")) }
            if stopLosses.isEmpty { menu.addItem(info("止损：本次未查到", color: .systemOrange)) }
            for algo in algos.filter({ $0.kind == "move_order_stop" }) {
                menu.addItem(info("移动止损：回调 \(number(algo.callbackRatio.map { $0 * 100 }))% / 价差 \(number(algo.callbackSpread))"))
            }
            menu.addItem(info("普通挂单 \(data.ordinaryOrderCount.map(String.init) ?? "未知") 笔 · 待生效附带止盈止损 \(data.attached?.count ?? 0) 组"))
            menu.addItem(.separator())
            menu.addItem(info("更新 \(time(Freshness.date(data.fetchedAt))) · 北京时间"))
            let notes = NSMenu()
            notes.addItem(info("浮盈亏来自标记价，尚未扣平仓手续费。"))
            notes.addItem(info("现金余额含已占用保证金；交易权益包含浮盈亏。"))
            notes.addItem(info("菜单栏总余额直接来自欧易总资产估值，折合 USDT。"))
            notes.addItem(info("已含浮盈亏及接口覆盖的资金、交易、理财等资产，不重复相加。"))
            notes.addItem(info("资金账户估值：\(number(data.fundingValuationUSDT, digits: 4)) USDT"))
            notes.addItem(info("理财账户估值：\(number(data.earnValuationUSDT, digits: 4)) USDT"))
            notes.addItem(info("总余额时间：\(time(Freshness.date(data.valuationTime)))"))
            notes.addItem(info("今日净入账：北京时间 00:00 起的 USDT 永续账单。"))
            notes.addItem(info("含已实现盈亏、手续费及资金费；排除划转与浮盈亏。"))
            notes.addItem(info("止盈止损查询：条件 / OCO / 移动止损及附带单。"))
            notes.addItem(info("其他计划开仓单未覆盖，请在欧易核对。"))
            notes.addItem(info("最新价时间：\(time(Freshness.date(data.tickerTime)))"))
            notes.addItem(info("标记价时间：\(time(Freshness.date(data.markTime)))"))
            notes.addItem(info("数据超过 \(Int(max(15, interval * 2))) 秒将隐藏数值。"))
            let parent = NSMenuItem(title: "数据口径与时间", action: nil, keyEquivalent: "")
            parent.submenu = notes
            menu.addItem(parent)
        case "error":
            title = "OKX 查询失败"
            tint = .systemOrange
            menu.addItem(info(failure ?? "只读查询失败，旧数值已隐藏。", color: .systemOrange))
            menu.addItem(info("上次成功：\(time(lastSuccess))"))
        case "stale":
            title = "OKX 数据过期"
            tint = .systemOrange
            menu.addItem(info("行情或查询时间已过期，旧数值已隐藏。", color: .systemOrange))
            menu.addItem(info("上次成功：\(time(lastSuccess))"))
        case "paused":
            title = "OKX 已暂停"
            menu.addItem(info("已暂停刷新，未显示旧数值。"))
            menu.addItem(info("上次成功：\(time(lastSuccess))"))
        default:
            menu.addItem(info("正在连接本机只读 MCP…"))
        }
        menu.addItem(.separator())
        let refreshItem = action("立即刷新", #selector(refreshClicked), key: "r")
        refreshItem.isEnabled = process == nil
        menu.addItem(refreshItem)
        let display = NSMenu()
        for (key, label) in [("balanceAndFloating", "总余额 + BTC 浮盈亏"), ("floating", "BTC 浮动盈亏"), ("equity", "USDT 交易权益"), ("today", "今日永续净入账")] {
            let item = action(label, #selector(changeDisplay(_:)))
            item.representedObject = key
            item.state = displayMode == key ? .on : .off
            display.addItem(item)
        }
        let displayParent = NSMenuItem(title: "菜单栏显示", action: nil, keyEquivalent: "")
        displayParent.submenu = display
        menu.addItem(displayParent)
        let priceToggle = action("同时显示 BTC 最新价", #selector(toggleBTCPrice))
        priceToggle.state = showBTCPrice ? .on : .off
        menu.addItem(priceToggle)
        let intervals = NSMenu()
        for seconds in [5, 10, 15, 30, 60] {
            let item = action("每 \(seconds) 秒", #selector(changeInterval(_:)))
            item.tag = seconds
            item.state = interval == Double(seconds) ? .on : .off
            intervals.addItem(item)
        }
        let intervalParent = NSMenuItem(title: "刷新间隔", action: nil, keyEquivalent: "")
        intervalParent.submenu = intervals
        menu.addItem(intervalParent)
        menu.addItem(action(paused ? "恢复刷新" : "暂停刷新", #selector(togglePause)))
        menu.addItem(action("打开欧易网页", #selector(openOKX)))
        menu.addItem(action("退出 OKX 菜单栏", #selector(quit), key: "q"))
        let attributedTitle = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: tint,
        ])
        if displayedState == "fresh", displayMode == "balanceAndFloating", let separator = title.range(of: " · ") {
            let prefix = NSRange(title.startIndex..<separator.upperBound, in: title)
            attributedTitle.addAttribute(.foregroundColor, value: NSColor.labelColor, range: prefix)
        }
        if displayedState == "fresh", showBTCPrice, let suffix = title.range(of: " · BTC") {
            let range = NSRange(suffix.lowerBound..<title.endIndex, in: title)
            attributedTitle.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        }
        statusItem.button?.attributedTitle = attributedTitle
        statusItem.button?.toolTip = "OKX 实盘只读；\(title)；上次成功 \(time(lastSuccess))"
        menu.delegate = self
        statusItem.menu = menu
        writeDiagnostics()
    }
    private func trigger(_ text: String) -> String {
        return ["last":"最新价触发", "mark":"标记价触发", "index":"指数价触发"][text] ?? "触发类型未提供"
    }
    private func writeDiagnostics() {
        guard let path = diagnosticsPath else { return }
        // No account values or credentials: only lifecycle state for installation QA.
        let data: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier,
                                 "state": displayedState, "lastSuccess": lastSuccess?.timeIntervalSince1970 ?? 0,
                                 "runningQuery": process != nil, "readOnly": true,
                                 "displayMode": displayMode,
                                 "refreshIntervalSeconds": interval,
                                 "btcPriceVisible": displayedState == "fresh" && showBTCPrice && snapshot?.last != nil,
                                 "totalBalanceSource": snapshot?.totalBalanceSource ?? "unavailable",
                                 "totalBalanceAvailable": displayedState == "fresh" && snapshot?.totalAssetsUSDT != nil,
                                 "statusItemVisible": statusItem.isVisible,
                                 "statusButtonWindowPresent": statusItem.button?.window != nil]
        if let raw = try? JSONSerialization.data(withJSONObject: data) {
            try? raw.write(to: URL(fileURLWithPath: path), options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
    }
    private func refresh() {
        guard !paused, process == nil else { return }
        guard let worker = Bundle.main.path(forResource: "snapshot", ofType: "mjs") else {
            failure = "本机数据入口缺失，旧数值已隐藏。"
            snapshot = nil
            render()
            return
        }
        let task = Process()
        let output = Pipe()
        task.executableURL = URL(fileURLWithPath: node)
        task.arguments = [worker]
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        let inherited = ProcessInfo.processInfo.environment
        var environment: [String: String] = [:]
        for key in ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG"] { environment[key] = inherited[key] }
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        task.environment = environment
        do {
            try task.run()
            process = task
            timeoutTimer?.invalidate()
            timeoutTimer = Timer(timeInterval: 22, repeats: false) { [weak self, weak task] _ in
                guard let self = self, let task = task, self.process === task else { return }
                task.terminate()
                self.process = nil
                self.snapshot = nil
                self.failure = "查询超时，旧数值已隐藏；将自动重试。"
                self.render()
            }
            RunLoop.main.add(timeoutTimer!, forMode: .common)
            render()
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let raw = output.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                let decoded = raw.count <= 1048576 ? try? JSONDecoder().decode(Snapshot.self, from: raw) : nil
                DispatchQueue.main.async {
                    guard let self = self, self.process === task else { return }
                    self.timeoutTimer?.invalidate()
                    self.process = nil
                    if task.terminationStatus == 0, let decoded = decoded, decoded.status == "ok",
                       Freshness.valid(decoded, now: Date(), interval: self.interval) {
                        self.snapshot = decoded
                        self.lastSuccess = Freshness.date(decoded.fetchedAt)
                        self.failure = nil
                    } else {
                        self.snapshot = nil
                        self.failure = decoded?.status == "stale" ? "行情时间戳过期，未显示旧数值。" : "只读查询失败或权限校验未通过，旧数值已隐藏。"
                    }
                    self.render()
                }
            }
        } catch {
            snapshot = nil
            failure = "本机数据进程未能启动，旧数值已隐藏。"
            render()
        }
    }
    @objc private func refreshClicked() {
        paused = false
        refresh()
    }
    @objc private func changeDisplay(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        defaults.set(value, forKey: "displayMode")
        render()
    }
    @objc private func changeInterval(_ sender: NSMenuItem) {
        defaults.set(sender.tag, forKey: "refreshInterval")
        schedule()
        render()
    }
    @objc private func toggleBTCPrice() {
        defaults.set(!showBTCPrice, forKey: "showBTCPrice")
        render()
    }
    @objc private func togglePause() {
        paused.toggle()
        if !paused { refresh() }
        render()
    }
    @objc private func openOKX() {
        NSWorkspace.shared.open(URL(string: "https://www.okx.com/trade-swap/btc-usdt-swap")!)
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

func selfTest() {
    let text = """
    {"status":"ok","fetchedAt":"2026-10-20T06:00:00.000Z","tickerTime":"2026-10-20T06:00:00.000Z","markTime":"2026-10-20T06:00:00.000Z","valuationTime":"2026-10-20T06:00:00.000Z","readOnly":true,"demo":false}
    """
    let good = try! JSONDecoder().decode(Snapshot.self, from: text.data(using: .utf8)!)
    let now = Freshness.date("2026-10-20T06:00:10.000Z")!
    precondition(Freshness.valid(good, now: now, interval: 30))
    precondition(Freshness.valid(good, now: now, interval: 5))
    precondition(!Freshness.valid(good, now: now.addingTimeInterval(6), interval: 5))
    precondition(!Freshness.valid(good, now: now.addingTimeInterval(60), interval: 30))
    precondition(!Freshness.valid(good, now: now.addingTimeInterval(-20), interval: 30))
    for bad in [text.replacingOccurrences(of: "\"readOnly\":true", with: "\"readOnly\":false"),
                text.replacingOccurrences(of: "\"demo\":false", with: "\"demo\":true"),
                text.replacingOccurrences(of: "\"status\":\"ok\"", with: "\"status\":\"error\""),
                "{\"status\":\"ok\",\"fetchedAt\":\"2026-10-20T06:00:00.000Z\",\"readOnly\":true,\"demo\":false}"] {
        let data = try! JSONDecoder().decode(Snapshot.self, from: bad.data(using: .utf8)!)
        precondition(!Freshness.valid(data, now: now, interval: 30))
    }
    print("Passed: fresh / expired / future clock / writable mode / demo mode / failed query / missing timestamps.")
}
func acquireInstanceLock() -> Int32? {
    // Keep a private process lock for the complete app lifetime. Never remove it:
    // the OS releases the lock on exit, including after an unexpected crash.
    let folder = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".local/share/okx-readonly/menu-bar", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
    } catch { return nil }
    let path = folder.appendingPathComponent("menu-instance.lock").path
    let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { return nil }
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_uid == getuid(),
          (info.st_mode & S_IFMT) == S_IFREG,
          flock(fd, LOCK_EX | LOCK_NB) == 0 else {
        close(fd)
        return nil
    }
    fchmod(fd, 0o600)
    return fd
}
if CommandLine.arguments.contains("--self-test") {
    selfTest()
} else if let instanceLock = acquireInstanceLock() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
    close(instanceLock)
}

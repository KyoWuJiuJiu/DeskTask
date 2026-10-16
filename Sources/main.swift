import AppKit

private let initialWidth: CGFloat = WidgetView.expandedWidth
private let initialHeight: CGFloat = 120

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ReminderStore()
    private var window: WidgetWindow?
    private var container: NSView?
    private var widget: WidgetView?

    /// 「鼠标移开若干秒后收进桌面」的计时器。
    private var minimizeTimer: Timer?
    private var keyMonitor: Any?
    private var statusItem: NSStatusItem?
    /// 用户真正操作过之后才开启"空闲自动收进桌面"。
    ///
    /// 否则启动瞬间就会误收：启动时窗口要从初始的 328x120 缩成 42x42（左上角不动），
    /// 鼠标会因为窗口"缩走"而触发一次 mouseExited，接着 2 秒后就把自己藏起来了 ——
    /// 表现就是"双击图标以后什么都没发生"。
    private var minimizeArmed = false
    private var isMinimized = false
    private static let minimizeDelay: TimeInterval = 1.0

    private var appliedWidth: CGFloat = 0
    private var appliedHeight: CGFloat = 0
    private var appliedRadius: CGFloat = 0
    private var appliedIdle = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = WidgetWindow(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false

        // 容器负责圆角和裁剪；统一按深色玻璃渲染，颜色解析才稳定。
        let container = NSView()
        window.contentView = container
        self.container = container
        container.wantsLayer = true
        container.layer?.cornerRadius = 18
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.appearance = NSAppearance(named: .darkAqua)

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.frame = container.bounds
        blur.autoresizingMask = [.width, .height]
        container.addSubview(blur)

        let widget = WidgetView(store: store)
        widget.frame = container.bounds
        widget.autoresizingMask = [.width, .height]
        widget.onSizeChange = { [weak self] width, height, cornerRadius, idle in
            self?.applySize(width: width, height: height, cornerRadius: cornerRadius, idle: idle)
        }
        widget.onMouseEnter = { [weak self] in self?.cancelMinimize() }
        widget.onMouseExit = { [weak self] in self?.scheduleMinimize(force: true) }
        widget.onRestoreRequest = { [weak self] in self?.restore(openPanel: true) }
        widget.onUserActivity = { [weak self] in self?.minimizeArmed = true }
        // 建完一条就自己开始收起倒计时，不必等鼠标移开。
        widget.onItemCreated = { [weak self] in self?.scheduleMinimize(force: true, delay: 2.5) }
        container.addSubview(widget)

        store.onStructureChange = { [weak self] in
            guard let self else { return }
            self.widget?.rebuild()
            // 建完提醒后鼠标一般还在窗口上；一旦移开就进入折叠倒计时。
            if !self.mouseIsInside {
                self.scheduleMinimize()
            }
        }
        store.onTick = { [weak self] in self?.widget?.refresh() }
        store.onFire = { [weak self] in self?.alert() }

        self.window = window
        self.widget = widget

        widget.rebuild()
        installKeyMonitor()
        installStatusItem()
        positionWindow()

        // 换屏幕/分辨率变化时重新贴合"刘海正下方、屏幕水平居中"。
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.applySize(
                width: self.appliedWidth,
                height: self.appliedHeight,
                cornerRadius: self.appliedRadius,
                force: true
            )
        }

        window.orderFrontRegardless()
    }

    // MARK: - 位置与尺寸

    /// 固定的落点：**屏幕水平居中、刘海正下方一点**。
    ///
    /// 用 `safeAreaInsets.top` 拿刘海高度（没有刘海时退化成菜单栏高度），
    /// 再往下留 `topGap`。窗口宽度变化时保持**水平居中**，所以锚点是顶边中点而不是左上角。
    private func anchoredFrame(width: CGFloat, height: CGFloat) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1512, height: 982)
        let notch = screen?.safeAreaInsets.top ?? 0
        let menuBar = max(notch, 33)
        let topGap: CGFloat = 24

        let topY = frame.maxY - menuBar - topGap
        return NSRect(
            x: frame.midX - width / 2,
            y: topY - height,
            width: width,
            height: height
        )
    }

    private func positionWindow() {
        guard let window = window else { return }
        window.setFrame(anchoredFrame(width: window.frame.width, height: window.frame.height), display: true)
    }

    /// 空闲时用的「桌面层」：在壁纸、桌面图标、通知中心面板之上，但在所有普通窗口之下。
    ///
    /// 实测（CGWindowListCopyWindowInfo）各层：壁纸 -2147483626、Finder 桌面窗口 -2147483603、
    /// Window Server 菜单栏背板 -2147483602、通知中心面板 -2147483601、普通窗口和桌面小组件都是 0。
    /// 所以取 -2147483600：贴着桌面，又在一切 level 0 窗口之后。
    ///
    /// 注意：**桌面小组件也在 level 0**，和普通窗口同层。所以"在小组件前面"与"在所有窗口后面"
    /// 无法同时成立，这里选的是整体沉到所有 level 0 窗口之下。
    private var shelfLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 3)
    }

    private func applySize(
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat,
        idle: Bool = false,
        force: Bool = false
    ) {
        guard let window = window else { return }
        let width = max(24, ceil(width))
        let height = max(8, ceil(height))
        let radius = max(0, cornerRadius)
        guard force
            || abs(width - appliedWidth) > 0.5
            || abs(height - appliedHeight) > 0.5
            || abs(radius - appliedRadius) > 0.5
            || idle != appliedIdle else { return }
        appliedWidth = width
        appliedHeight = height
        appliedRadius = radius
        appliedIdle = idle

        // 空闲(加号/横杠) → 沉到桌面层；展开 → 浮到最前，方便操作。
        window.level = idle ? shelfLevel : .floating

        container?.layer?.cornerRadius = radius
        window.setFrame(anchoredFrame(width: width, height: height), display: true, animate: false)
    }

    // MARK: - 收进桌面 / 提回前台

    private var mouseIsInside: Bool {
        guard let window = window else { return false }
        return window.frame.contains(NSEvent.mouseLocation)
    }

    /// 每次按键都把折叠倒计时往后推：只要还在打字就不会被收起来，
    /// 停手 2 秒后才收。这比判断 first responder 可靠——输入框拿到焦点后会一直占着它，
    /// 光看 first responder 会导致"一旦点过输入框就永远不再折叠"。
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // 还在打字就一直把折叠往后推（哪怕鼠标停在窗口上），停手 1 秒才收。
            self.scheduleMinimize(force: true)
            return event
        }
    }

    private func scheduleMinimize(force: Bool = false, delay: TimeInterval? = nil) {
        cancelMinimize()
        guard !isMinimized, minimizeArmed else { return }
        // 正在拉长 / 正在填任务时不要收，否则会把用户填到一半的东西藏起来。
        if widget?.isInputting == true { return }
        if !force && mouseIsInside { return }

        let timer = Timer(timeInterval: delay ?? Self.minimizeDelay, repeats: false) { [weak self] _ in
            self?.minimizeNow()
        }
        RunLoop.main.add(timer, forMode: .common)
        minimizeTimer = timer
    }

    private func cancelMinimize() {
        minimizeTimer?.invalidate()
        minimizeTimer = nil
    }

    private func minimizeNow() {
        guard window != nil, !isMinimized else { return }
        // 先把还在编辑的输入提交掉，再收。
        widget?.endEditing()
        isMinimized = true
        widget?.setMinimized(true)
    }

    /// 提回前台。`openPanel` 为真时顺便把模式面板打开（用户点了 +）。
    private func restore(openPanel: Bool) {
        cancelMinimize()
        guard let window = window else { return }

        window.level = .floating
        window.orderFrontRegardless()

        if isMinimized {
            isMinimized = false
            widget?.setMinimized(false)
        }
        if openPanel {
            widget?.setPanel(.choosing)
        }
    }

    // MARK: - 菜单栏图标
    //
    // 它同时解决两件事：
    // 1. 部件收进桌面后可能完全够不着（曾经因为层级比 Finder 桌面窗口低而点不动），
    //    这时候没有菜单栏入口就等于"退都退不掉"。
    // 2. 它就是"常驻在刘海旁边"的原生做法 —— 刘海两侧本来就是菜单栏区域。

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "timer", accessibilityDescription: "DeskTask")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            toggleWidget()
        }
    }

    private func showStatusMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "显示 DeskTask", action: #selector(showWidget), keyEquivalent: "")
        menu.addItem(withTitle: "收进桌面", action: #selector(hideWidget), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "清除全部提醒", action: #selector(clearReminders), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 DeskTask", action: #selector(quitApp), keyEquivalent: "q")
        for entry in menu.items where entry.action != nil {
            entry.target = self
        }
        item.menu = menu
        item.button?.performClick(nil)
        // 弹完立刻摘掉，否则左键也会变成弹菜单。
        item.menu = nil
    }

    private func toggleWidget() {
        if isMinimized {
            restore(openPanel: true)
        } else {
            minimizeNow()
        }
    }

    @objc private func showWidget() {
        restore(openPanel: true)
    }

    @objc private func hideWidget() {
        minimizeNow()
    }

    @objc private func clearReminders() {
        store.removeAll()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - 到点提醒

    private func alert() {
        if let sound = NSSound(named: "Glass") {
            sound.play()
        } else {
            NSSound.beep()
        }
        NSApp.activate(ignoringOtherApps: true)
        // 到点时不管收没收进桌面，都要把它提出来。
        restore(openPanel: false)
    }
}

// MARK: - 启动

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(
    withTitle: "退出 DeskTask",
    action: #selector(NSApplication.terminate(_:)),
    keyEquivalent: "q"
)
appMenuItem.submenu = appMenu
application.mainMenu = mainMenu

let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()

import AppKit

/// 刘海下方的倒计时 HUD：鼠标移到屏幕顶部中间时弹出，移开片刻后收起。
///
/// 感应区是一块透明窗口，`hitTest` 返回 nil，所以点击会穿透到下面的菜单栏，
/// 不会挡住刘海两侧的菜单栏项目。
final class NotchHUDController {
    /// HUD 显示/隐藏时回调，用来把桌面上空闲状态的部件临时让开。
    var onHUDVisibilityChange: ((Bool) -> Void)?

    private let hud: NSPanel
    private let hudView = CountdownHUDView()
    private let zone: NSWindow
    private var hideTimer: Timer?

    private(set) var isShowing = false

    init() {
        // 先把所有存储属性初始化完，之后闭包里才能引用 self
        hud = NSPanel(
            contentRect: Self.hudRect(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hud.isOpaque = false
        hud.backgroundColor = .clear
        hud.hasShadow = true
        hud.level = .statusBar
        hud.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hud.ignoresMouseEvents = true        // HUD 自己不接收鼠标，免得一出现就把悬停状态打断
        hudView.frame = NSRect(origin: .zero, size: Self.hudRect().size)
        hud.contentView = hudView

        zone = HoverWindow(
            contentRect: Self.notchZoneRect(),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        zone.isOpaque = false
        zone.backgroundColor = .clear
        zone.hasShadow = false
        zone.level = .statusBar + 1          // 盖在菜单栏之上，才能收到悬停事件
        zone.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let hover = HoverView(frame: NSRect(origin: .zero, size: Self.notchZoneRect().size))
        hover.onEnter = { [weak self] in self?.handleEnter() }
        hover.onExit = { [weak self] in self?.hideSoon() }
        zone.contentView = hover
        zone.orderFrontRegardless()
    }

    // MARK: - 显示/隐藏

    func update(remainingText: String, remainingFraction: Double, hasTimer: Bool) {
        hudView.remainingText = remainingText
        hudView.remainingFraction = remainingFraction
        hudView.hasTimer = hasTimer
        hudView.needsDisplay = true
    }

    private func handleEnter() {
        guard hudView.hasTimer else { return }   // 没有正在跑的计时就不弹
        show()
    }

    private func show() {
        hideTimer?.invalidate()
        hideTimer = nil
        guard !isShowing else { return }
        isShowing = true
        hud.orderFrontRegardless()
        onHUDVisibilityChange?(true)
    }

    func hideSoon() {
        hideTimer?.invalidate()
        let timer = Timer(timeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.hide()
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    private func hide() {
        guard isShowing else { return }
        isShowing = false
        hud.orderOut(nil)
        onHUDVisibilityChange?(false)
    }

    // MARK: - 几何

    /// 感应区：屏幕顶部中间，稍微比刘海宽一点，方便扫过去就能触发。
    static func notchZoneRect() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1512, height: 982)
        let width: CGFloat = 260
        let height: CGFloat = 40
        return NSRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height)
    }

    /// HUD：刘海下沿再往下 6pt
    static func hudRect() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1512, height: 982)
        let notch = max(screen?.safeAreaInsets.top ?? 0, 33)
        let width: CGFloat = 208
        let height: CGFloat = 30
        let top = frame.maxY - notch - 6
        return NSRect(x: frame.midX - width / 2, y: top - height, width: width, height: height)
    }
}

/// 感应区窗口：不抢焦点，命中测试返回 nil，点击穿透。
private final class HoverWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class HoverView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}

/// HUD 内容：一根随时间变短的进度条 + 居中剩余时间。
final class CountdownHUDView: NSView {
    var remainingText = ""
    /// 1 = 满，随时间递减
    var remainingFraction: Double = 1
    var hasTimer = false

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius = rect.height / 2
        let track = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor(calibratedWhite: 0.12, alpha: 0.94).setFill()
        track.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        track.lineWidth = 1
        track.stroke()

        if hasTimer {
            let inset: CGFloat = 3
            let usable = rect.width - inset * 2
            let innerHeight = rect.height - inset * 2
            let fraction = CGFloat(min(1, max(0, remainingFraction)))
            let width = max(innerHeight, usable * fraction)
            let fill = NSBezierPath(
                roundedRect: NSRect(x: inset, y: inset, width: width, height: innerHeight),
                xRadius: innerHeight / 2,
                yRadius: innerHeight / 2
            )
            NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
            fill.fill()
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let text = NSAttributedString(string: remainingText, attributes: attributes)
        let size = text.size()
        text.draw(at: NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        ))
    }
}

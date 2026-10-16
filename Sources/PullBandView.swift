import AppKit

/// DeskMinder 的核心交互：按住这根「橡皮筋」向右拉，拉得越长时间越久，松手即定时长。
///
/// 外观上刻意不做成滚动条：没有轨道、没有刻度，只有一条会被拉长、变细、
/// 表面纹路被撑开的橡皮筋，末端有一颗可以抓的圆头。
final class PullBandView: NSView {
    /// 松手并确定时长后回调。
    var onCommit: ((Int) -> Void)?

    static let slotHeight: CGFloat = 44
    static let hintHeight: CGFloat = 15
    static let totalHeight: CGFloat = slotHeight + 5 + hintHeight

    private let restWidth: CGFloat = 78
    private let restHeight: CGFloat = 34
    private let minHeight: CGFloat = 24
    private let bulgeExtra: CGFloat = 5

    private var pull: CGFloat = 0
    private var dragStartX: CGFloat = 0
    /// 回弹动画期间锁住显示值，避免数字飞快地倒退。
    private var frozenMinutes: Int?
    private var snapTimer: Timer?

    override var isFlipped: Bool { true }

    /// .accessory 应用未激活时，第一次点击默认会被吞掉；这里让它直接生效。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    deinit {
        snapTimer?.invalidate()
    }

    private var minutes: Int { frozenMinutes ?? PullStops.minutes(forPull: pull) }
    private var isDragging: Bool { frozenMinutes == nil && pull > 0 }
    private var isActive: Bool { isDragging || frozenMinutes != nil }

    /// 拉得越长，越细。
    private var shape: (width: CGFloat, height: CGFloat) {
        let stretch = PullStops.visual(forPull: pull)
        let maxStretch = max(1, PullStops.visual(forMinutes: PullStops.maxMinutes))
        let ratio = min(1, stretch / maxStretch)
        let height = restHeight - (restHeight - minHeight) * ratio
        return (min(restWidth + stretch, bounds.width), height)
    }

    // MARK: - 鼠标

    override func mouseDown(with event: NSEvent) {
        snapTimer?.invalidate()
        snapTimer = nil
        frozenMinutes = nil
        dragStartX = event.locationInWindow.x
        pull = 0
        // 让窗口成为 key window，后面输入框才能直接打字。
        window?.makeKey()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        pull = max(0, event.locationInWindow.x - dragStartX)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let released = pull
        let chosen = PullStops.minutes(forPull: released)

        if chosen > 0 {
            frozenMinutes = chosen
            onCommit?(chosen)
        }
        snapBack(from: released)
    }

    /// 松手后像橡皮筋一样弹回去。
    private func snapBack(from value: CGFloat) {
        let start = Date()
        let duration: TimeInterval = 0.26
        snapTimer?.invalidate()

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] ticker in
            guard let self else {
                ticker.invalidate()
                return
            }
            let progress = min(1, Date().timeIntervalSince(start) / duration)
            let eased = 1 - pow(1 - progress, 3)
            self.pull = value * (1 - eased)
            self.needsDisplay = true
            if progress >= 1 {
                ticker.invalidate()
                self.snapTimer = nil
                self.pull = 0
                self.frozenMinutes = nil
                self.needsDisplay = true
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        snapTimer = timer
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        let (width, height) = shape
        let active = isActive
        let y = (Self.slotHeight - height) / 2
        let radius = height / 2
        let bodyWidth = max(width, radius * 2)
        let base = active ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.26)

        // 橡皮筋剖面：两端鼓、中间细 —— 这是"被拉紧的皮筋"最直观的形状，
        // 也不用任何独立把手，就不会看成滑块。
        let bulge = height + bulgeExtra
        let silhouette = NSBezierPath()
        let midWidth = max(1, bodyWidth - bulge)
        silhouette.appendRoundedRect(
            NSRect(x: bulge / 2, y: y, width: midWidth, height: height),
            xRadius: radius,
            yRadius: radius
        )
        let bulgeY = (Self.slotHeight - bulge) / 2
        silhouette.appendOval(in: NSRect(x: 0, y: bulgeY, width: bulge, height: bulge))
        silhouette.appendOval(in: NSRect(x: bodyWidth - bulge, y: bulgeY, width: bulge, height: bulge))

        if active {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 8
            shadow.shadowOffset = NSSize(width: 0, height: 2)
            shadow.set()
            base.setFill()
            silhouette.fill()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            base.setFill()
            silhouette.fill()
        }

        // 被撑开的纹路：条纹数量固定，间距随拉伸变大 —— 这就是"橡皮被拉长"的观感来源。
        let marks = 6
        let inset: CGFloat = 13
        let usable = bodyWidth - inset * 2 - bulgeExtra
        if usable > 14 {
            NSColor.white.withAlphaComponent(active ? 0.30 : 0.16).setStroke()
            for index in 1...marks {
                let x = inset + usable * CGFloat(index) / CGFloat(marks + 1)
                let stroke = NSBezierPath()
                stroke.lineWidth = 1
                stroke.move(to: NSPoint(x: x, y: y + height * 0.28))
                stroke.line(to: NSPoint(x: x, y: y + height * 0.72))
                stroke.stroke()
            }
        }

        // 文字
        let text = minutes > 0 ? "\(minutes) 分钟" : "拉长"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: active ? NSColor.white : NSColor.labelColor.withAlphaComponent(0.82),
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        attributed.draw(at: NSPoint(x: 13, y: (Self.slotHeight - textSize.height) / 2))

        // 下方提示
        let hint: String
        if isDragging {
            hint = minutes > 0 ? "松手即定为 \(minutes) 分钟" : "继续拉…"
        } else {
            hint = "按住向右拖 · 拖得越长时间越久"
        }
        let hintAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        NSAttributedString(string: hint, attributes: hintAttributes)
            .draw(at: NSPoint(x: 1, y: Self.slotHeight + 5))
    }
}

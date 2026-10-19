import AppKit

/// 圆形 + 按钮。两种形态：
/// - 折叠态（`plain`）：整窗就是一块圆形玻璃，这里只画字形；
/// - 展开态：画一个小圆底 + 加号／减号。
final class PlusButtonView: NSView {
    var onClick: (() -> Void)?

    var expanded: Bool = false {
        didSet { needsDisplay = true }
    }

    var plain: Bool = false {
        didSet { needsDisplay = true }
    }

    private var hovering = false
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    /// .accessory 应用未激活时，第一次点击默认会被吞掉；这里让它直接生效。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let size = bounds.width
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let glyphColor: NSColor

        if plain {
            // 圆形玻璃本身就是按钮，这里不再画圆底。
            glyphColor = NSColor.labelColor.withAlphaComponent(hovering ? 1.0 : 0.88)
        } else {
            // 磨玻璃：半透明浅色圆 + 细描边，跟窗口本身的毛玻璃同质，不用 accent 蓝。
            let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
            NSColor.labelColor.withAlphaComponent(hovering ? 0.30 : 0.16).setFill()
            circle.fill()
            NSColor.labelColor.withAlphaComponent(hovering ? 0.34 : 0.20).setStroke()
            circle.lineWidth = 1
            circle.stroke()
            glyphColor = NSColor.labelColor.withAlphaComponent(hovering ? 1.0 : 0.82)
        }

        // 字形按按钮尺寸等比缩放，这样 64pt 的玻璃圆和 22pt 的迷你按钮都好看。
        let arm = size * (plain ? 0.155 : 0.22)
        let weight = max(2, size * (plain ? 0.042 : 0.09))

        let path = NSBezierPath()
        path.lineWidth = weight
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: center.x - arm, y: center.y))
        path.line(to: NSPoint(x: center.x + arm, y: center.y))
        if !expanded {
            path.move(to: NSPoint(x: center.x, y: center.y - arm))
            path.line(to: NSPoint(x: center.x, y: center.y + arm))
        }
        glyphColor.setStroke()
        path.stroke()
    }

    /// 位置是固定的（屏幕水平居中、刘海正下方），所以不再支持拖动移动窗口，只处理点击。
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

/// 圆角小按钮。
final class PillButton: NSView {
    var onClick: (() -> Void)?

    private let label = NSTextField(labelWithString: "")
    private let accented: Bool
    private var hovering = false
    private var trackingArea: NSTrackingArea?

    init(title: String, accented: Bool = false) {
        self.accented = accented
        super.init(frame: .zero)
        label.stringValue = title
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.alignment = .center
        label.textColor = accented ? .white : .labelColor
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    override var isFlipped: Bool { true }

    /// .accessory 应用未激活时，第一次点击默认会被吞掉；这里让它直接生效。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        label.sizeToFit()
        label.frame = NSRect(
            x: 0,
            y: (bounds.height - label.frame.height) / 2,
            width: bounds.width,
            height: label.frame.height
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)

        if accented {
            NSColor.controlAccentColor.withAlphaComponent(hovering ? 1.0 : 0.88).setFill()
            path.fill()
        } else {
            NSColor.labelColor.withAlphaComponent(hovering ? 0.20 : 0.10).setFill()
            path.fill()
            NSColor.labelColor.withAlphaComponent(0.14).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

/// 点 + 之后出现的两个模式入口。
final class ChooserRow: NSView {
    /// 26（模式行） + 10（间距） + 24（快捷行）
    static let height: CGFloat = 60

    var onTimer: (() -> Void)?
    var onTask: (() -> Void)?
    /// 点了某个快捷时长：直接建一条对应时长的倒计时。
    var onQuick: ((Int) -> Void)?

    private static let quickMinutes = [5, 10, 25, 30, 60]

    private let timerButton = PillButton(title: "拉长计时")
    private let taskButton = PillButton(title: "选择日期")
    private var quickButtons: [PillButton] = []

    override var isFlipped: Bool { true }

    /// .accessory 应用未激活时，第一次点击默认会被吞掉；这里让它直接生效。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init() {
        super.init(frame: .zero)

        timerButton.onClick = { [weak self] in self?.onTimer?() }
        taskButton.onClick = { [weak self] in self?.onTask?() }
        addSubview(timerButton)
        addSubview(taskButton)

        for minutes in Self.quickMinutes {
            let button = PillButton(title: "\(minutes)分")
            button.onClick = { [weak self] in self?.onQuick?(minutes) }
            quickButtons.append(button)
            addSubview(button)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override func layout() {
        super.layout()

        let modeWidth: CGFloat = 84
        let modeHeight: CGFloat = 26
        timerButton.frame = NSRect(x: 0, y: 0, width: modeWidth, height: modeHeight)
        taskButton.frame = NSRect(x: modeWidth + 8, y: 0, width: modeWidth, height: modeHeight)

        let count = CGFloat(quickButtons.count)
        guard count > 0 else { return }
        let gap: CGFloat = 6
        let width = (bounds.width - gap * (count - 1)) / count
        let height: CGFloat = 24
        let y = modeHeight + 10
        for (index, button) in quickButtons.enumerated() {
            button.frame = NSRect(
                x: (width + gap) * CGFloat(index),
                y: y,
                width: width,
                height: height
            )
        }
    }
}

/// task 模式：选日期（只要日期，不需要时刻）+ 写任务内容。
final class TaskComposeView: NSView {
    static let height: CGFloat = 54

    var onSubmit: ((String, Date) -> Void)?

    private let todayButton = PillButton(title: "今天")
    private let tomorrowButton = PillButton(title: "明天")
    private let dayAfterButton = PillButton(title: "后天")
    private let picker = NSDatePicker()
    private let field = NSTextField()
    private let submitButton = PillButton(title: "添加", accented: true)
    private var inputBox: NSRect = .zero

    override var isFlipped: Bool { true }

    /// .accessory 应用未激活时，第一次点击默认会被吞掉；这里让它直接生效。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init() {
        super.init(frame: .zero)

        todayButton.onClick = { [weak self] in self?.setDaysFromToday(0) }
        tomorrowButton.onClick = { [weak self] in self?.setDaysFromToday(1) }
        dayAfterButton.onClick = { [weak self] in self?.setDaysFromToday(2) }
        submitButton.onClick = { [weak self] in self?.fire() }

        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .yearMonthDay
        picker.datePickerMode = .single
        picker.dateValue = Calendar.current.startOfDay(for: Date())
        picker.font = .systemFont(ofSize: 11)

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.textColor = .labelColor
        field.placeholderString = "任务内容…"
        field.cell?.sendsActionOnEndEditing = false
        field.target = self
        field.action = #selector(fireFromField)

        for view in [todayButton, tomorrowButton, dayAfterButton, picker, field, submitButton] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    func focusField() {
        window?.makeFirstResponder(field)
    }

    /// 提交后清空，方便下一次。
    func reset() {
        field.stringValue = ""
        picker.dateValue = Calendar.current.startOfDay(for: Date())
    }

    private func setDaysFromToday(_ days: Int) {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date())
        picker.dateValue = calendar.date(byAdding: .day, value: days, to: base) ?? base
    }

    private func fire() {
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            window?.makeFirstResponder(field)
            return
        }
        onSubmit?(text, picker.dateValue)
    }

    @objc private func fireFromField() {
        fire()
    }

    override func layout() {
        super.layout()
        let gap: CGFloat = 6
        let buttonWidth: CGFloat = 42
        let rowHeight: CGFloat = 22

        todayButton.frame = NSRect(x: 0, y: 0, width: buttonWidth, height: rowHeight)
        tomorrowButton.frame = NSRect(x: buttonWidth + gap, y: 0, width: buttonWidth, height: rowHeight)
        dayAfterButton.frame = NSRect(x: (buttonWidth + gap) * 2, y: 0, width: buttonWidth, height: rowHeight)

        let pickerWidth: CGFloat = 122
        picker.frame = NSRect(x: bounds.width - pickerWidth, y: 0, width: pickerWidth, height: rowHeight)

        let submitWidth: CGFloat = 52
        let fieldHeight: CGFloat = 24
        let row2Y = rowHeight + 8
        let boxWidth = bounds.width - submitWidth - 8
        inputBox = NSRect(x: 0, y: row2Y, width: boxWidth, height: fieldHeight)
        field.frame = inputBox.insetBy(dx: 9, dy: 3)
        submitButton.frame = NSRect(x: bounds.width - submitWidth, y: row2Y, width: submitWidth, height: fieldHeight)

        needsDisplay = true
    }

    /// 输入框外框：没有它的话，光秃秃一行占位文字看不出这里能打字。
    override func draw(_ dirtyRect: NSRect) {
        guard inputBox.width > 1 else { return }
        let path = NSBezierPath(roundedRect: inputBox, xRadius: 8, yRadius: 8)
        NSColor.labelColor.withAlphaComponent(0.10).setFill()
        path.fill()
        NSColor.labelColor.withAlphaComponent(0.16).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// 空闲时的「横杠」状态条。
///
/// 不只是装饰，直接显示两条最有用的信息：
/// 左边是最近一条 reminder 还剩多少分钟（底色填充长度就是它的进度），
/// 右边是今天需要完成的任务数。
final class IdleBarView: NSView {
    var onClick: (() -> Void)?

    /// 0…1：最近一个倒计时的进度。
    var progress: Double = 0
    var hasTimer = false
    var timerText = ""
    /// 右侧主段（过期数 / 今日数）与其颜色
    var taskText = ""
    var taskTextColor: NSColor = .labelColor
    /// 右侧副段（跟在主段后面，例如「· 今日 3 个」）与其颜色
    var taskSuffix = ""
    var taskSuffixColor: NSColor = .labelColor

    static let barWidth: CGFloat = 296
    static let barHeight: CGFloat = 26

    private var hovering = false
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let track = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: radius,
            yRadius: radius
        )
        NSColor.labelColor.withAlphaComponent(hovering ? 0.30 : 0.20).setFill()
        track.fill()
        NSColor.labelColor.withAlphaComponent(hovering ? 0.34 : 0.22).setStroke()
        track.lineWidth = 1
        track.stroke()

        // 倒计时进度：作为底色从左侧铺开
        if hasTimer {
            let inset: CGFloat = 2
            let usable = bounds.width - inset * 2
            let ratio = CGFloat(min(1, max(0, progress)))
            let innerHeight = bounds.height - inset * 2
            let width = max(innerHeight, usable * ratio)
            let fill = NSBezierPath(
                roundedRect: NSRect(x: inset, y: inset, width: width, height: innerHeight),
                xRadius: innerHeight / 2,
                yRadius: innerHeight / 2
            )
            NSColor.controlAccentColor.withAlphaComponent(hovering ? 0.9 : 0.75).setFill()
            fill.fill()
        }

        // 两条信息
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        if !timerText.isEmpty {
            let text = NSAttributedString(string: timerText, attributes: attributes)
            let size = text.size()
            text.draw(at: NSPoint(x: 13, y: (bounds.height - size.height) / 2))
        }
        // 右侧从后往前贴：先画副段，再把主段贴在它左边，整体右对齐
        var rightX = bounds.width - 13
        if !taskSuffix.isEmpty {
            var suffixAttributes = attributes
            suffixAttributes[.foregroundColor] = taskSuffixColor
            let suffix = NSAttributedString(string: taskSuffix, attributes: suffixAttributes)
            let size = suffix.size()
            rightX -= size.width
            suffix.draw(at: NSPoint(x: rightX, y: (bounds.height - size.height) / 2))
        }
        if !taskText.isEmpty {
            var mainAttributes = attributes
            mainAttributes[.foregroundColor] = taskTextColor
            let main = NSAttributedString(string: taskText, attributes: mainAttributes)
            let size = main.size()
            rightX -= size.width
            main.draw(at: NSPoint(x: rightX, y: (bounds.height - size.height) / 2))
        }
    }
}

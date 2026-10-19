import AppKit

/// 标题栏：左侧抓手 + 应用名。窗口位置是固定的，这里不再承担拖动。
final class HeaderView: NSView {
    static let height: CGFloat = 18

    override var isFlipped: Bool { true }

    /// .accessory 应用未激活时，第一次点击默认会被吞掉；这里让它直接生效。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.tertiaryLabelColor.setFill()
        for index in 0..<3 {
            let rect = NSRect(x: 1, y: 5 + CGFloat(index) * 4, width: 11, height: 2)
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        NSAttributedString(string: "DeskTask", attributes: attributes)
            .draw(at: NSPoint(x: 17, y: 1))
    }

}

/// 空闲时整窗的样子。
enum IdleShape {
    /// 有活动中的提醒/任务 → 一条横杠（同时也是最近那个倒计时的进度条）
    case bar
    /// 什么都没有 → 一个简单的加号
    case plus
    /// 不是空闲态 → 完整界面
    case none
}

/// 面板状态：折叠、选模式、拉长计时、设置日期。
enum PanelState: Equatable {
    case collapsed
    case choosing
    case stretching
    case taskCompose
}

/// 浮窗根视图。
final class WidgetView: NSView {
    static let expandedWidth: CGFloat = 328
    static let compactSize: CGFloat = 42
    private static let plusSize: CGFloat = 32
    private static let plusSizeInline: CGFloat = 22

    private let store: ReminderStore
    private let header = HeaderView()
    private let plusButton = PlusButtonView()
    private let chooser = ChooserRow()
    private let band = PullBandView()
    private let compose = TaskComposeView()
    private let bar = IdleBarView()
    private var chips: [ChipView] = []

    private var panelState: PanelState = .collapsed
    private var pendingFocusID: UUID?
    private var lastReportedSize: NSSize = .zero
    private var lastReportedRadius: CGFloat = 0
    private var lastReportedIdle: Bool?
    /// 收进桌面（沉到所有窗口之下）时为 true：整窗只剩一个 +。
    private var minimized = false
    private var trackingArea: NSTrackingArea?

    var onSizeChange: ((
        _ width: CGFloat,
        _ height: CGFloat,
        _ cornerRadius: CGFloat,
        _ idle: Bool
    ) -> Void)?
    var onMouseEnter: (() -> Void)?
    var onMouseExit: (() -> Void)?
    /// 最小化状态下被点击：请求委托方把窗口提回前台。
    var onRestoreRequest: (() -> Void)?
    /// 用户真的操作过这个部件了（点 +、拉皮筋、提交任务）。
    var onUserActivity: (() -> Void)?
    /// 刚刚新建了一条提醒/任务：可以开始算"用完自动收起"的倒计时了。
    var onItemCreated: (() -> Void)?

    /// 正在拉长或正在填任务 —— 这时候收起会把用户填到一半的东西藏起来。
    var isInputting: Bool {
        panelState == .stretching || panelState == .taskCompose
    }

    override var isFlipped: Bool { true }

    /// .accessory 应用未激活时，第一次点击默认会被吞掉；这里让它直接生效。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(store: ReminderStore) {
        self.store = store
        super.init(frame: NSRect(x: 0, y: 0, width: Self.expandedWidth, height: 120))

        plusButton.onClick = { [weak self] in self?.togglePanel() }
        bar.onClick = { [weak self] in self?.togglePanel() }
        plusButton.menu = makeMenu()
        chooser.onTimer = { [weak self] in self?.setPanel(.stretching) }
        chooser.onTask = { [weak self] in self?.setPanel(.taskCompose) }
        chooser.onQuick = { [weak self] minutes in self?.startTimer(minutes: minutes) }
        compose.onSubmit = { [weak self] title, date in
            self?.onUserActivity?()
            self?.createTask(title: title, dueDate: date)
        }
        band.onCommit = { [weak self] minutes in
            self?.startTimer(minutes: minutes)
        }

        addSubview(header)
        addSubview(chooser)
        addSubview(band)
        addSubview(compose)
        addSubview(bar)
        addSubview(plusButton)

        updateVisibility()
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    /// 还有没有"在跑的东西"：进行中的倒计时，或者还没完成的任务。
    private var hasWork: Bool {
        store.items.contains { $0.kind == .task || $0.phase == .running }
    }

    /// 最近一个倒计时的进度，用来画横杠的填充长度。
    private var nearestTimerProgress: Double {
        var best = 0.0
        for item in store.items where item.kind == .timer && item.phase == .running {
            best = max(best, store.progress(item))
        }
        return best
    }

    private var hasRunningTimer: Bool {
        store.items.contains { $0.kind == .timer && $0.phase == .running }
    }

    /// 最近一条倒计时还剩多少分钟。
    private var nearestTimerText: String {
        var soonest: TimeInterval?
        for item in store.items where item.kind == .timer && item.phase == .running {
            let left = store.remaining(item)
            if soonest == nil || left < soonest! {
                soonest = left
            }
        }
        guard let seconds = soonest else { return "" }
        let minutes = Int((seconds / 60).rounded(.up))
        return minutes <= 0 ? "不到 1 分钟" : "还剩 \(minutes) 分钟"
    }

    /// 横条右侧的两段文案：过期数是红的，今日数是绿的。
    private func updateBarInfo() {
        let overdue = store.overdueTaskCount
        let today = store.todayTaskCount

        bar.progress = nearestTimerProgress
        bar.hasTimer = hasRunningTimer
        bar.timerText = nearestTimerText

        if overdue > 0 {
            bar.taskText = "过期 \(overdue) 个"
            bar.taskTextColor = .systemRed
            if today > 0 {
                bar.taskSuffix = " · 今日 \(today) 个"
                bar.taskSuffixColor = .systemGreen
            } else {
                bar.taskSuffix = ""
            }
        } else {
            bar.taskText = today == 0 ? "今日无任务" : "今日 \(today) 个任务"
            bar.taskTextColor = .systemGreen
            bar.taskSuffix = ""
        }
        bar.needsDisplay = true
    }

    /// 空闲时的样子：有活动内容 → 横杠；什么也没有 → 加号。
    private var idleShape: IdleShape {
        if !minimized && (panelState != .collapsed || !chips.isEmpty) {
            return .none
        }
        return hasWork ? .bar : .plus
    }

    /// 由 App 层调用：收进桌面 / 提回前台。
    func setMinimized(_ value: Bool) {
        guard minimized != value else { return }
        minimized = value
        if value {
            panelState = .collapsed
        }
        updateVisibility()
        needsLayout = true
    }

    /// 收起之前先提交正在进行的输入，避免把用户写的东西一起藏起来。
    func endEditing() {
        window?.makeFirstResponder(nil)
    }

    private func togglePanel() {
        onUserActivity?()
        if minimized {
            onRestoreRequest?()
            return
        }
        setPanel(panelState == .collapsed ? .choosing : .collapsed)
    }

    // MARK: - 鼠标进出（用来触发"移开 2 秒后收进桌面"）

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
        onMouseEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExit?()
    }

    /// 切换面板状态（内部公开，便于离屏渲染自检）。
    func setPanel(_ state: PanelState) {
        panelState = state
        updateVisibility()
        needsLayout = true

        // 面板收起时释放焦点，否则隐藏的输入框会继续吞按键。
        if state == .collapsed {
            window?.makeFirstResponder(nil)
        }
        if state == .taskCompose {
            DispatchQueue.main.async { [weak self] in
                self?.compose.focusField()
            }
        }
    }

    private func updateVisibility() {
        let shape = idleShape
        let idle = (shape != .none)

        header.isHidden = idle
        chooser.isHidden = idle || panelState != .choosing
        band.isHidden = idle || panelState != .stretching
        compose.isHidden = idle || panelState != .taskCompose

        // 只有收成横条时才藏起 +/−；面板展开时它必须还在（右上角那个按钮）。
        plusButton.isHidden = (shape == .bar)
        bar.isHidden = (shape != .bar)
        plusButton.expanded = (panelState != .collapsed)
        // 空闲成加号时不画圆底——那块圆形玻璃本身就是按钮。
        plusButton.plain = (shape == .plus)

        // 空闲时连任务列表一起彻底折叠。
        for chip in chips {
            chip.isHidden = idle
        }
    }

    /// 条数/状态变化：整块重建。
    func rebuild() {
        for chip in chips {
            chip.removeFromSuperview()
        }

        chips = store.items.map { item in
            let chip = ChipView(item: item)
            chip.onRemove = { [weak self] in self?.store.remove(item.id) }
            chip.onComplete = { [weak self] in self?.completeTask(item.id) }
            chip.onTitleChange = { [weak self] text in self?.store.updateTitle(item.id, title: text) }
            addSubview(chip)
            // 立刻刷一次，否则第一帧会显示占位符 "—"，要等 0.25 秒后的心跳才补上。
            chip.refresh(with: store)
            return chip
        }

        updateVisibility()
        needsLayout = true

        // 刚拉完的那张计时卡：把光标放进标题框，方便可选地命名。
        if let id = pendingFocusID {
            pendingFocusID = nil
            if let chip = chips.first(where: { $0.item.id == id }) {
                DispatchQueue.main.async {
                    chip.focusTitle()
                }
            }
        }
    }

    /// 时间在走：原地刷新，不重建（重建会打断正在输入的输入法）。
    func refresh() {
        for chip in chips {
            chip.refresh(with: store)
        }
        // 横杠的填充长度跟着倒计时走。
        if idleShape == .bar {
            updateBarInfo()
        }
    }

    /// 建一条倒计时：拉皮筋和点快捷时长走的都是这里。
    private func startTimer(minutes: Int) {
        onUserActivity?()
        NSApp.activate(ignoringOtherApps: true)
        pendingFocusID = store.addTimer(minutes: minutes)
        setPanel(.collapsed)
        onItemCreated?()
    }

    private func createTask(title: String, dueDate: Date) {
        let id = store.addTask(title: title, dueDate: dueDate)
        compose.reset()
        setPanel(.collapsed)
        onItemCreated?()

        RemindersBridge.create(title: title, dueDate: dueDate) { [weak self] result in
            switch result {
            case .success(let reminderID):
                self?.store.markSynced(id, reminderID: reminderID)
            case .failure(let error):
                self?.store.markSyncFailed(id, message: error.message)
            }
        }
    }

    private func completeTask(_ id: UUID) {
        guard let item = store.item(id) else { return }
        if case .synced(let reminderID) = item.sync {
            RemindersBridge.complete(reminderID: reminderID) { _ in }
        }
        store.remove(id)
    }

    // MARK: - 布局

    override func layout() {
        super.layout()

        switch idleShape {
        case .plus:
            // 什么都没有：整窗就是一块圆形玻璃，加号铺满它。
            plusButton.frame = bounds
            report(
                width: Self.compactSize,
                height: Self.compactSize,
                cornerRadius: Self.compactSize / 2,
                idle: true
            )
            return
        case .bar:
            // 有事情在跑：收成一条横杠，填充长度就是最近那个倒计时的进度。
            bar.frame = bounds
            updateBarInfo()
            report(
                width: IdleBarView.barWidth,
                height: IdleBarView.barHeight,
                cornerRadius: IdleBarView.barHeight / 2,
                idle: true
            )
            return
        case .none:
            break
        }

        let padding: CGFloat = 14
        let contentWidth = max(80, bounds.width - padding * 2)
        var y = padding

        header.frame = NSRect(x: padding, y: y, width: contentWidth, height: HeaderView.height)
        plusButton.frame = NSRect(
            x: bounds.width - padding - Self.plusSizeInline,
            y: y + (HeaderView.height - Self.plusSizeInline) / 2,
            width: Self.plusSizeInline,
            height: Self.plusSizeInline
        )
        y += HeaderView.height + 10

        // 面板块
        var panelHeight: CGFloat = 0
        switch panelState {
        case .choosing:
            panelHeight = ChooserRow.height
            chooser.frame = NSRect(x: padding, y: y + 10, width: contentWidth, height: panelHeight)
        case .stretching:
            panelHeight = PullBandView.totalHeight
            band.frame = NSRect(x: padding, y: y + 10, width: contentWidth, height: panelHeight)
        case .taskCompose:
            panelHeight = TaskComposeView.height
            compose.frame = NSRect(x: padding, y: y + 10, width: contentWidth, height: panelHeight)
        case .collapsed:
            panelHeight = 0
        }
        if panelHeight > 0 {
            y += 10 + panelHeight
        }

        // 卡片列表
        if !chips.isEmpty {
            y += 10
        }
        for (index, chip) in chips.enumerated() {
            chip.frame = NSRect(x: padding, y: y, width: contentWidth, height: ChipView.height)
            y += ChipView.height
            if index < chips.count - 1 {
                y += 6
            }
        }

        // 关键：这里必须报「目标宽度」而不是 bounds.width。
        // 空闲态窗口只有几十点宽，若照抄当前宽度，展开后窗口永远长不回去，
        // [选择日期] 会被整个裁在窗口外。
        report(width: Self.expandedWidth, height: y + padding, cornerRadius: 18, idle: false)
    }

    private func report(width: CGFloat, height: CGFloat, cornerRadius: CGFloat, idle: Bool) {
        let target = NSSize(width: ceil(width), height: ceil(height))
        let sameWidth = abs(target.width - lastReportedSize.width) < 0.5
        let sameHeight = abs(target.height - lastReportedSize.height) < 0.5
        let sameRadius = abs(cornerRadius - lastReportedRadius) < 0.5
        let sameIdle = (lastReportedIdle == idle)
        guard !(sameWidth && sameHeight && sameRadius && sameIdle) else { return }
        lastReportedSize = target
        lastReportedRadius = cornerRadius
        lastReportedIdle = idle

        // 不在 layout 里同步改窗口，派发到下一轮。
        DispatchQueue.main.async { [weak self] in
            self?.onSizeChange?(target.width, target.height, cornerRadius, idle)
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "清除全部提醒", action: #selector(clearAll), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 DeskTask", action: #selector(quit), keyEquivalent: "")
        for item in menu.items where item.action != nil {
            item.target = self
        }
        return menu
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        return makeMenu()
    }

    @objc private func clearAll() {
        store.removeAll()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

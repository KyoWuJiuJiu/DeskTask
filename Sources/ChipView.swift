import AppKit

/// 一张提醒卡片。
///
/// 关键约定：`titleField.stringValue` **只在 init 里写一次**。
/// 心跳刷新时绝对不能回写，否则输入法组字期间会被反复重置，中文永远打不进来。
final class ChipView: NSView, NSTextFieldDelegate {
    private(set) var item: ReminderItem

    var onRemove: (() -> Void)?
    var onComplete: (() -> Void)?
    var onTitleChange: ((String) -> Void)?

    private let titleField = NSTextField()
    private let detailLabel = NSTextField(labelWithString: "")
    private let completeButton = NSButton()
    private let removeButton = NSButton()
    private var progress: Double = 0

    static let height: CGFloat = 54

    override var isFlipped: Bool { true }

    /// .accessory 应用未激活时，第一次点击默认会被吞掉；这里让它直接生效。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(item: ReminderItem) {
        self.item = item
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: Self.height))

        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.focusRingType = .none
        titleField.font = .systemFont(ofSize: 13, weight: .medium)
        titleField.textColor = .labelColor
        titleField.cell?.lineBreakMode = .byTruncatingTail
        titleField.cell?.sendsActionOnEndEditing = false
        titleField.delegate = self
        titleField.target = self
        titleField.action = #selector(titleCommitted)
        titleField.stringValue = item.title
        titleField.isEditable = (item.kind == .timer)
        titleField.isSelectable = (item.kind == .timer)
        titleField.placeholderString = item.kind == .timer ? "计时（可留空）" : ""

        detailLabel.font = .systemFont(ofSize: 10, weight: .medium)
        detailLabel.cell?.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1

        configure(removeButton, symbol: "xmark.circle.fill", action: #selector(tapRemove))
        configure(completeButton, symbol: "checkmark.circle.fill", action: #selector(tapComplete))
        completeButton.isHidden = (item.kind != .task)

        addSubview(titleField)
        addSubview(detailLabel)
        addSubview(completeButton)
        addSubview(removeButton)

        updateDetail(store: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    private func configure(_ button: NSButton, symbol: String, action: Selector) {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.target = self
        button.action = action
    }

    func focusTitle() {
        window?.makeFirstResponder(titleField)
    }

    /// 每次心跳调一次：只刷新随时间变化的部分，绝不碰 stringValue。
    func refresh(with store: ReminderStore) {
        item = store.items.first(where: { $0.id == item.id }) ?? item
        progress = store.progress(item)
        updateDetail(store: store)
        needsDisplay = true
    }

    private func updateDetail(store: ReminderStore?) {
        switch item.kind {
        case .timer:
            if item.phase == .fired {
                detailLabel.stringValue = "时间到！"
                detailLabel.textColor = .systemRed
            } else {
                let left = store.map { formatDuration($0.remaining(item)) } ?? "—"
                detailLabel.stringValue = "\(item.minutes) 分钟 · 还剩 \(left)"
                detailLabel.textColor = .secondaryLabelColor
            }

        case .task:
            let dateText = item.dueDate.map(formatDueDate) ?? "未定日期"
            switch item.sync {
            case .pending:
                detailLabel.stringValue = "任务 · \(dateText) · 同步中…"
                detailLabel.textColor = .secondaryLabelColor
                detailLabel.toolTip = nil
            case .synced:
                detailLabel.stringValue = "任务 · \(dateText) · 已同步到提醒事项"
                detailLabel.textColor = .systemGreen
                detailLabel.toolTip = "已在 Apple「提醒事项」的默认列表中创建"
            case .failed(let message):
                detailLabel.stringValue = "任务 · \(dateText) · 未同步"
                detailLabel.textColor = .systemOrange
                detailLabel.toolTip = message
            case .notApplicable:
                detailLabel.stringValue = "任务 · \(dateText)"
                detailLabel.textColor = .secondaryLabelColor
                detailLabel.toolTip = nil
            }
        }
    }

    // MARK: - 布局

    override func layout() {
        super.layout()

        let button: CGFloat = 22
        let trailing: CGFloat = 12
        var right = bounds.width - trailing

        removeButton.frame = NSRect(
            x: right - button,
            y: (bounds.height - button) / 2,
            width: button,
            height: button
        )
        right -= button + 4

        if item.kind == .task {
            completeButton.frame = NSRect(
                x: right - button,
                y: (bounds.height - button) / 2,
                width: button,
                height: button
            )
            right -= button + 4
        }

        let textX: CGFloat = 12 + 22 + 10
        let textWidth = max(40, right - textX)
        titleField.frame = NSRect(x: textX, y: 11, width: textWidth, height: 18)
        detailLabel.frame = NSRect(x: textX, y: 32, width: textWidth, height: 13)
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 13, yRadius: 13)

        tint.withAlphaComponent(item.kind == .task ? 0.16 : 0.16).setFill()
        path.fill()
        tint.withAlphaComponent(0.38).setStroke()
        path.lineWidth = 1
        path.stroke()

        // 左侧环形：timer 显示分钟数 + 进度，task 显示日期里的"日"
        let ringRect = NSRect(x: 12, y: (bounds.height - 22) / 2, width: 22, height: 22)
        let background = NSBezierPath(ovalIn: ringRect.insetBy(dx: 1.5, dy: 1.5))
        NSColor.labelColor.withAlphaComponent(0.18).setStroke()
        background.lineWidth = 2.5
        background.stroke()

        if item.kind == .timer, progress > 0 {
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: NSPoint(x: ringRect.midX, y: ringRect.midY),
                radius: ringRect.width / 2 - 1.5,
                startAngle: 90,
                endAngle: 90 - 360 * CGFloat(progress),
                clockwise: true
            )
            arc.lineWidth = 2.5
            arc.lineCapStyle = .round
            tint.setStroke()
            arc.stroke()
        }

        let middleText: String
        switch item.kind {
        case .timer:
            middleText = item.phase == .fired ? "!" : "\(item.minutes)"
        case .task:
            middleText = "\(Calendar.current.component(.day, from: item.dueDate ?? Date()))"
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: tint,
        ]
        let middle = NSAttributedString(string: middleText, attributes: attributes)
        let size = middle.size()
        middle.draw(at: NSPoint(
            x: ringRect.midX - size.width / 2,
            y: ringRect.midY - size.height / 2
        ))
    }

    private var tint: NSColor {
        switch item.kind {
        case .timer:
            return item.phase == .fired ? .systemRed : .controlAccentColor
        case .task:
            return .systemIndigo
        }
    }

    // MARK: - 交互

    @objc private func tapRemove() {
        onRemove?()
    }

    @objc private func tapComplete() {
        onComplete?()
    }

    @objc private func titleCommitted() {
        window?.makeFirstResponder(nil)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as? NSTextField === titleField else { return }
        onTitleChange?(titleField.stringValue)
    }

    /// 收尾时再落一次：输入法组字中的内容只有在这里才是最终形态。
    func controlTextDidEndEditing(_ obj: Notification) {
        guard obj.object as? NSTextField === titleField else { return }
        onTitleChange?(titleField.stringValue)
    }
}

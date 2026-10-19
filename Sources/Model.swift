import Foundation

/// 两种模式。
/// - `timer`：reminder 模式 —— 拉长定时长，纯倒计时，不写提醒事项
/// - `task`：task 模式 —— 指定完成日期，并同步到 Apple「提醒事项」
enum ItemKind: Equatable {
    case timer
    case task
}

enum Phase: Equatable {
    case running
    case fired
}

/// 任务同步到「提醒事项」的状态。
enum SyncState: Equatable {
    case notApplicable
    case pending
    case synced(reminderID: String)
    case failed(String)
}

struct ReminderItem: Equatable, Identifiable {
    let id: UUID
    var kind: ItemKind
    var title: String
    /// timer 用
    var minutes: Int
    var deadline: Date?
    /// task 用（当天 00:00）
    var dueDate: Date?
    var phase: Phase
    /// 到点的时刻。到点后只停留 `ReminderStore.firedLinger` 秒就自动离开清单。
    var firedAt: Date?
    var sync: SyncState

    init(
        id: UUID = UUID(),
        kind: ItemKind,
        title: String = "",
        minutes: Int = 0,
        deadline: Date? = nil,
        dueDate: Date? = nil,
        phase: Phase = .running,
        firedAt: Date? = nil,
        sync: SyncState = .notApplicable
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.minutes = minutes
        self.deadline = deadline
        self.dueDate = dueDate
        self.phase = phase
        self.firedAt = firedAt
        self.sync = sync
    }
}

/// 清单 + 心跳。
///
/// 两种通知刻意分开：
/// - `onStructureChange`：条数/状态变了，调用方需要重建视图
/// - `onTick`：只是时间在走，调用方原地刷新（重建会打断正在输入的输入法）
final class ReminderStore {
    private(set) var items: [ReminderItem] = []

    var onStructureChange: (() -> Void)?
    var onTick: (() -> Void)?
    var onFire: (() -> Void)?

    private var ticker: Timer?
    private var now = Date()
    private var lastAlertAt = Date.distantPast
    private var alertRounds = 0

    init() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    deinit {
        ticker?.invalidate()
    }

    /// 到点之后在清单里停留多久；过了就自动移除，不再挂着红色条。
    static let firedLinger: TimeInterval = 120

    private func tick() {
        let current = Date()
        now = current

        var justFired = false
        for index in items.indices where items[index].kind == .timer && items[index].phase == .running {
            if let deadline = items[index].deadline, deadline <= current {
                items[index].phase = .fired
                items[index].firedAt = current
                justFired = true
            }
        }

        // 到点超过 firedLinger 的，直接从清单里删掉（提醒频率不变，只是不一直留着）
        let settled = items.filter { item in
            guard item.kind == .timer, item.phase == .fired, let firedAt = item.firedAt else {
                return false
            }
            return current.timeIntervalSince(firedAt) >= Self.firedLinger
        }.map(\.id)
        if !settled.isEmpty {
            items.removeAll { settled.contains($0.id) }
            alertRounds = 0
            onStructureChange?()
        }

        if justFired {
            lastAlertAt = current
            alertRounds = 0
            onStructureChange?()
            onFire?()
            return
        }

        // 一直没被确认的话，每 30 秒再响一次，最多 5 次。
        if items.contains(where: { $0.kind == .timer && $0.phase == .fired }) {
            if alertRounds < 5, current.timeIntervalSince(lastAlertAt) >= 30 {
                lastAlertAt = current
                alertRounds += 1
                onFire?()
            }
        } else {
            alertRounds = 0
        }

        onTick?()
    }

    /// reminder 模式：拉完即开始倒计时。
    @discardableResult
    func addTimer(minutes: Int) -> UUID {
        let value = max(1, minutes)
        let item = ReminderItem(
            kind: .timer,
            minutes: value,
            deadline: Date().addingTimeInterval(TimeInterval(value * 60))
        )
        items.insert(item, at: 0)
        onStructureChange?()
        return item.id
    }

    /// task 模式：先落一条 pending 的卡片，随后由同步结果改状态。
    @discardableResult
    func addTask(title: String, dueDate: Date) -> UUID {
        let item = ReminderItem(kind: .task, title: title, dueDate: dueDate, sync: .pending)
        items.insert(item, at: 0)
        onStructureChange?()
        return item.id
    }

    /// 静默更新：不触发重建，否则会打断正在组字的输入法。
    func updateTitle(_ id: UUID, title: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].title = title
    }

    func markSynced(_ id: UUID, reminderID: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].sync = .synced(reminderID: reminderID)
        onStructureChange?()
    }

    func markSyncFailed(_ id: UUID, message: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].sync = .failed(message)
        onStructureChange?()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        onStructureChange?()
    }

    func removeAll() {
        items.removeAll()
        alertRounds = 0
        onStructureChange?()
    }

    func item(_ id: UUID) -> ReminderItem? {
        items.first(where: { $0.id == id })
    }

    /// 已过期（到期日早于今天 00:00）的任务数。
    var overdueTaskCount: Int {
        items.filter { isTaskOverdue($0, at: now) }.count
    }

    /// 今天到期的任务数（不含已过期的）。
    var todayTaskCount: Int {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = startOfToday.addingTimeInterval(24 * 3600)
        return items.filter { item in
            guard item.kind == .task, let due = item.dueDate else { return false }
            return due >= startOfToday && due < endOfToday
        }.count
    }

    func remaining(_ item: ReminderItem) -> TimeInterval {
        guard let deadline = item.deadline else { return 0 }
        return deadline.timeIntervalSince(now)
    }

    /// 0…1 的进度，用于环形进度条。
    func progress(_ item: ReminderItem) -> Double {
        guard item.kind == .timer else { return 0 }
        guard item.phase == .running else { return 1 }
        let total = TimeInterval(max(1, item.minutes) * 60)
        let left = max(0, remaining(item))
        return min(1, max(0, 1 - left / total))
    }
}

/// 任务是否已过期：到期日早于参考时刻所在的自然日 00:00。
func isTaskOverdue(_ item: ReminderItem, at reference: Date = Date()) -> Bool {
    guard item.kind == .task, let due = item.dueDate else { return false }
    return due < Calendar.current.startOfDay(for: reference)
}

/// mm:ss（超过一小时则为 h:mm:ss）。
func formatDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%02d:%02d", minutes, secs)
}

/// 12月25日 / 明天 / 今天
func formatDueDate(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "今天" }
    if calendar.isDateInTomorrow(date) { return "明天" }
    let parts = calendar.dateComponents([.month, .day], from: date)
    return "\(parts.month ?? 0)月\(parts.day ?? 0)日"
}

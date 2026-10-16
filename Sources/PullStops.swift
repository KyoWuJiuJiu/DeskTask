import CoreGraphics

struct PullStop {
    /// 累计的原始拉动距离（点）
    let pull: CGFloat
    /// 对应的时长（分钟）
    let minutes: Int
}

/// 「拉得越长，时间越久」的映射表。
///
/// 手感由两件事构成：
/// 1. **粘滞**：每一段里，前 `gap - stick` 点 1:1 跟手；靠近下一个刻度时斜率降到
///    `stickFactor`，所以越接近刻度越"拉不动"，跨过去之后又恢复跟手。
/// 2. **末端阻尼**：超过最后一个刻度后斜率降到 `resistance`，不会飞出窗口。
enum PullStops {
    static let stick: CGFloat = 9
    static let stickFactor: CGFloat = 0.45
    static let resistance: CGFloat = 0.25

    static let table: [PullStop] = [
        PullStop(pull: 20, minutes: 1),
        PullStop(pull: 38, minutes: 2),
        PullStop(pull: 58, minutes: 3),
        PullStop(pull: 82, minutes: 5),
        PullStop(pull: 110, minutes: 10),
        PullStop(pull: 142, minutes: 15),
        PullStop(pull: 178, minutes: 30),
        PullStop(pull: 220, minutes: 60),
    ]

    static var maxMinutes: Int { table.last?.minutes ?? 60 }

    /// 原始拉动距离 → 时长（没拉够第一格就是 0）。
    static func minutes(forPull pull: CGFloat) -> Int {
        var result = 0
        for entry in table where pull >= entry.pull {
            result = entry.minutes
        }
        return result
    }

    /// 原始拉动距离 → 视觉伸长量（含粘滞压缩）。
    static func visual(forPull pull: CGFloat) -> CGFloat {
        var rawCursor: CGFloat = 0
        var visualCursor: CGFloat = 0
        var previous: CGFloat = 0

        for entry in table {
            let gap = entry.pull - previous
            let free = max(0, gap - stick)
            let rawSegment = free + stick
            let visualSegment = free + stick * stickFactor

            if pull <= rawCursor + rawSegment {
                let offset = pull - rawCursor
                let within = offset <= free ? offset : free + (offset - free) * stickFactor
                return visualCursor + within
            }

            rawCursor += rawSegment
            visualCursor += visualSegment
            previous = entry.pull
        }

        return visualCursor + (pull - rawCursor) * resistance
    }

    /// 某个刻度对应的视觉伸长量，用来画轨道上的刻度点。
    static func visual(forMinutes minutes: Int) -> CGFloat {
        var total: CGFloat = 0
        var previous: CGFloat = 0
        for entry in table {
            let gap = entry.pull - previous
            total += max(0, gap - stick) + stick * stickFactor
            previous = entry.pull
            if entry.minutes == minutes { break }
        }
        return total
    }
}

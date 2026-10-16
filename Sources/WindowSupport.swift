import AppKit

/// 无边框窗口默认不能成为 key window，那样里面的输入框就没法打字。
final class WidgetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

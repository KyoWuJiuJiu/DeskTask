import AppKit

func makeRep(_ size: NSSize) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: max(1, Int(size.width)),
        pixelsHigh: max(1, Int(size.height)),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = size
    return rep
}

func sample(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> String {
    guard let c = rep.colorAt(x: x, y: y) else { return "?" }
    return String(format: "a%.2f", c.alphaComponent)
}

func settle() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.06))
}

func render(_ view: NSView, size: NSSize, cornerRadius: CGFloat, to path: String) {
    let rect = NSRect(origin: .zero, size: size)
    view.frame = rect
    view.appearance = NSAppearance(named: .darkAqua)
    view.layoutSubtreeIfNeeded()

    let viewRep = makeRep(size)
    view.cacheDisplay(in: view.bounds, to: viewRep)

    let canvas = makeRep(size)
    let cg = NSGraphicsContext(bitmapImageRep: canvas)!.cgContext

    cg.saveGState()
    cg.setFillColor(CGColor(red: 0.13, green: 0.14, blue: 0.17, alpha: 1))
    let shape = CGPath(
        roundedRect: rect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
    cg.addPath(shape)
    cg.fillPath()
    cg.restoreGState()

    let bgOK = canvas.colorAt(x: max(1, Int(size.width / 2)), y: max(1, Int(size.height) - 3))!.alphaComponent > 0.9

    if let image = viewRep.cgImage {
        cg.saveGState()
        cg.draw(image, in: rect)
        cg.restoreGState()
    }

    if let png = canvas.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
    }
    print("wrote \(path)  \(Int(size.width))x\(Int(size.height))  底色=\(bgOK ? "OK" : "丢了")  中心=\(sample(canvas, Int(size.width / 2), Int(size.height / 2)))")
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let store = ReminderStore()
let widget = WidgetView(store: store)

var reported = NSSize.zero
var reportedRadius: CGFloat = 0
widget.onSizeChange = { width, height, cornerRadius, _ in
    reported = NSSize(width: width, height: height)
    reportedRadius = cornerRadius
}
store.onStructureChange = { widget.rebuild() }

func shoot(_ name: String) {
    widget.layoutSubtreeIfNeeded()
    settle()
    print("  \(name) 上报尺寸 \(Int(reported.width))x\(Int(reported.height)) 圆角=\(Int(reportedRadius))")
    render(widget, size: reported, cornerRadius: reportedRadius, to: "/tmp/dm-\(name).png")
}

print("== 1 折叠态 =="); shoot("1-compact")
print("== 2 点 + =="); widget.setPanel(.choosing); shoot("2-choosing")
print("== 3 拉长计时 =="); widget.setPanel(.stretching); shoot("3-stretching")
print("== 4 选择日期 =="); widget.setPanel(.taskCompose); shoot("4-task")

print("== 5 列表 ==")
let timerID = store.addTimer(minutes: 10)
store.updateTitle(timerID, title: "开会")
let taskID = store.addTask(title: "把季度报销单交给财务", dueDate: Calendar.current.date(byAdding: .day, value: 3, to: Date())!)
// 一条已过期的任务，用来检查红色标记与横条的过期计数
_ = store.addTask(title: "回复客户合同修改意见", dueDate: Calendar.current.date(byAdding: .day, value: -3, to: Date())!)
// 一条今天到期的任务，用来检查横条里绿色的「今日 N 个」
_ = store.addTask(title: "今天交周报", dueDate: Date())
store.markSynced(taskID, reminderID: "x-apple-reminder://TEST")
widget.setPanel(.collapsed)
shoot("5-list")

print("== 6 空闲：有任务/倒计时在跑 -> 一条横杠 ==")
widget.setMinimized(true)
shoot("6-bar")

print("== 7 空闲：全部清空 -> 简单加号 ==")
store.removeAll()
widget.setMinimized(false)
widget.setMinimized(true)
shoot("7-plus")
widget.setMinimized(false)

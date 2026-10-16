import AppKit

// 离屏绘图前必须先初始化 NSApplication，否则 NSGraphicsContext 会直接段错误。
_ = NSApplication.shared

// 画一张 1024×1024 的应用图标，然后导出所有尺寸并打成 .icns。
// 视觉语言跟应用内部一致：蓝色渐变玻璃 + 环形进度 + 加号。

let canvas: CGFloat = 1024

/// 直接向 CoreGraphics 申请自己的位图缓冲。
///
/// 不能用 NSGraphicsContext(bitmapImageRep:)：那个上下文和 rep 都是局部对象，
/// 函数一返回就被释放，把 cgContext 传出去会指向已释放内存（段错误）。
func makeContext(size: CGFloat) -> CGContext {
    let cg = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    cg.scaleBy(x: size / canvas, y: size / canvas)
    return cg
}

func draw(in cg: CGContext) {
    let space = CGColorSpaceCreateDeviceRGB()

    // Big Sur 规范：图形本体只占画布约 80%，四周留 100pt
    let inset: CGFloat = 100
    let rect = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
    let radius = rect.width * 0.2237
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // 主体渐变
    cg.saveGState()
    cg.addPath(squircle)
    cg.clip()
    let body = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(red: 0.42, green: 0.57, blue: 1.00, alpha: 1),
            CGColor(red: 0.15, green: 0.25, blue: 0.78, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    cg.drawLinearGradient(
        body,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: []
    )

    // 顶部高光，制造玻璃感
    let glow = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.38),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    )!
    cg.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.06),
        startRadius: 0,
        endCenter: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.06),
        endRadius: rect.width * 0.78,
        options: []
    )
    cg.restoreGState()

    // 内描边
    cg.saveGState()
    cg.addPath(CGPath(roundedRect: rect.insetBy(dx: 2.5, dy: 2.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
    cg.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.28))
    cg.setLineWidth(5)
    cg.strokePath()
    cg.restoreGState()

    // 环形进度 + 加号
    let center = CGPoint(x: canvas / 2, y: canvas / 2)
    let ringRadius: CGFloat = 232
    let ringWidth: CGFloat = 52

    cg.saveGState()
    cg.setLineCap(.round)
    cg.setLineWidth(ringWidth)

    cg.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.30))
    cg.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    cg.strokePath()

    cg.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    cg.addArc(center: center, radius: ringRadius, startAngle: .pi / 2, endAngle: -.pi * 0.62, clockwise: true)
    cg.strokePath()

    // 中间的加号
    let arm: CGFloat = 86
    cg.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    cg.setLineWidth(56)
    cg.move(to: CGPoint(x: center.x - arm, y: center.y))
    cg.addLine(to: CGPoint(x: center.x + arm, y: center.y))
    cg.move(to: CGPoint(x: center.x, y: center.y - arm))
    cg.addLine(to: CGPoint(x: center.x, y: center.y + arm))
    cg.strokePath()
    cg.restoreGState()
}

func png(_ size: Int) -> Data {
    let cg = makeContext(size: CGFloat(size))
    draw(in: cg)
    guard let image = cg.makeImage() else {
        fatalError("无法生成 \(size)px 位图")
    }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG 编码失败 \(size)px")
    }
    return data
}

let workDir = FileManager.default.currentDirectoryPath
let iconset = URL(fileURLWithPath: workDir).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in entries {
    try! png(size).write(to: iconset.appendingPathComponent("\(name).png"))
}
print("已生成 iconset: \(iconset.path)")

let icns = URL(fileURLWithPath: workDir).appendingPathComponent("AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "已生成 \(icns.path)" : "iconutil 失败：\(task.terminationStatus)")

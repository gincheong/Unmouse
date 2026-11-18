// 사용법: swift icon/make-icon.swift <출력 폴더(.iconset)>
// 앱의 라벨 모양(화살표 달린 노란 상자)을 그대로 아이콘으로 그린다.
import AppKit

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ top: UInt32, _ bottom: UInt32) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(top), color(bottom)] as CFArray,
        locations: [0, 1])!
}

// 좌표는 1024 기준으로 쓰고 실제 크기에 맞춰 배율만 바꾼다.
func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let plate = CGPath(
        roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 186, cornerHeight: 186,
        transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, alpha: 0.35))
    context.addPath(plate)
    context.setFillColor(color(0x1B1E26))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(plate)
    context.clip()
    context.drawLinearGradient(
        gradient(0x343A48, 0x14161C), start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
    context.restoreGState()

    // 라벨이 가리키는 대상
    context.setFillColor(color(0xFFFFFF, alpha: 0.92))
    context.fillEllipse(in: CGRect(x: 512 - 30, y: 800, width: 60, height: 60))

    let box = CGRect(x: 262, y: 236, width: 500, height: 400)
    let triangle = CGMutablePath()
    triangle.move(to: CGPoint(x: 512, y: 756))
    triangle.addLine(to: CGPoint(x: 512 - 84, y: box.maxY - 20))
    triangle.addLine(to: CGPoint(x: 512 + 84, y: box.maxY - 20))
    triangle.closeSubpath()
    let label = CGPath(roundedRect: box, cornerWidth: 96, cornerHeight: 96, transform: nil).union(triangle)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, alpha: 0.45))
    context.addPath(label)
    context.setFillColor(color(0xFFD60A))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(label)
    context.clip()
    context.drawLinearGradient(
        gradient(0xFFE766, 0xFFC400), start: CGPoint(x: 0, y: 756), end: CGPoint(x: 0, y: box.minY), options: [])
    context.restoreGState()

    let text = NSAttributedString(
        string: "U",
        attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 330, weight: .heavy),
            .foregroundColor: NSColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1),
        ])
    let size = text.size()
    text.draw(at: CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))

    graphics.flushGraphics()
    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    print("usage: swift make-icon.swift <output.iconset>")
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: output.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: output.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

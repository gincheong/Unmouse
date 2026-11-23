import AppKit
import SwiftUI

struct LabelItem {
    let label: String
    let target: Target
}

final class OverlayController {
    private var windows: [NSPanel] = []

    // highlight는 스크롤 모드에서 선택된 영역의 테두리로 그린다.
    // cells가 true면 그리드 모드처럼 각 대상의 경계선도 그린다.
    func show(items: [LabelItem], highlight: CGRect? = nil, pointers: Bool = true, cells: Bool = false) {
        hide()
        for screen in NSScreen.screens {
            let panel = NSPanel(
                contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.animationBehavior = .none
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

            let view = LabelsView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.screenAXRect = AXScanner.axRect(of: screen)
            view.items = items.filter { view.screenAXRect.contains($0.target.point) }
            view.highlight = highlight
            view.showsPointers = pointers
            view.showsCells = cells
            view.reload()
            panel.contentView = view
            panel.orderFrontRegardless()
            windows.append(panel)
        }
    }

    func update(typed: String) {
        for window in windows {
            guard let view = window.contentView as? LabelsView else { continue }
            view.typed = typed
            view.reload()
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

struct LabelLayout: Identifiable {
    let id: Int
    let text: String
    let typedCount: Int
    let box: CGRect
    let radius: CGFloat
    // 대상을 가리키는 삼각형의 세 꼭짓점. 첫 번째가 대상 쪽 끝이다.
    let pointer: [CGPoint]?
    // 유리 라벨은 삼각형 대신 끝이 둥근 돌기로 대상을 가리킨다.
    var smoothPointer = false

    // 상자와 삼각형을 합친 외곽선. origin을 주면 그 점을 원점으로 옮긴 좌표로 만든다.
    func outline(relativeTo origin: CGPoint = .zero) -> Path {
        let shift = CGAffineTransform(translationX: -origin.x, y: -origin.y)
        var path = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if let pointer {
            let tip = pointer[0]
            let arrow = CGMutablePath()
            if smoothPointer {
                let baseY = pointer[1].y
                let edgeY = tip.y < box.midY ? box.minY + 1 : box.maxY - 1
                // 돌기가 둥근 모서리 밖으로 나가지 않게 폭을 제한한다.
                let room = min(tip.x - box.minX, box.maxX - tip.x) - radius * 0.5
                let half = max(min(abs(edgeY - tip.y) * 1.9, box.width * 0.3, room), 2)
                arrow.move(to: CGPoint(x: tip.x - half, y: baseY))
                arrow.addLine(to: CGPoint(x: tip.x - half, y: edgeY))
                arrow.addCurve(
                    to: tip, control1: CGPoint(x: tip.x - half * 0.35, y: edgeY),
                    control2: CGPoint(x: tip.x - half * 0.5, y: tip.y))
                arrow.addCurve(
                    to: CGPoint(x: tip.x + half, y: edgeY), control1: CGPoint(x: tip.x + half * 0.5, y: tip.y),
                    control2: CGPoint(x: tip.x + half * 0.35, y: edgeY))
                arrow.addLine(to: CGPoint(x: tip.x + half, y: baseY))
            } else {
                arrow.move(to: tip)
                arrow.addLine(to: pointer[1])
                arrow.addLine(to: pointer[2])
            }
            arrow.closeSubpath()
            path = path.union(arrow)
        }
        return Path(path).applying(shift)
    }

    var bounds: CGRect {
        pointer.map { box.union(CGRect(x: $0[0].x, y: $0[0].y, width: 0, height: 0)) } ?? box
    }
}

final class LabelsView: NSView {
    var items: [LabelItem] = []
    var typed = ""
    var highlight: CGRect?
    var showsPointers = true
    var showsCells = false
    var screenAXRect = CGRect.zero
    private var glassHost: NSView?

    // AX 좌표와 같은 좌상단 원점으로 그린다.
    override var isFlipped: Bool { true }

    func reload() {
        glassHost?.removeFromSuperview()
        glassHost = nil
        let style = Settings.labelStyle
        if style.glass, !showsCells, #available(macOS 26.0, *) {
            let smoothed = layouts(style: style).map { layout in
                var layout = layout
                layout.smoothPointer = true
                return layout
            }
            let host = NSHostingView(rootView: GlassLabels(layouts: smoothed, style: style))
            host.frame = bounds
            addSubview(host)
            glassHost = host
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if showsCells {
            drawGrid()
            return
        }
        let style = Settings.labelStyle

        if let highlight {
            let rect = highlight.offsetBy(dx: -screenAXRect.minX, dy: -screenAXRect.minY).insetBy(dx: 2, dy: 2)
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            path.lineWidth = 3
            style.background.setStroke()
            path.stroke()
        }
        guard glassHost == nil, let context = NSGraphicsContext.current?.cgContext else { return }

        let font = style.font
        for layout in layouts(style: style) {
            let outline = layout.outline().cgPath
            context.addPath(outline)
            context.setFillColor(style.background.withAlphaComponent(style.backgroundOpacity).cgColor)
            context.fillPath()
            context.addPath(outline)
            context.setStrokeColor(style.text.withAlphaComponent(0.45).cgColor)
            context.setLineWidth(1)
            context.strokePath()

            let text = NSMutableAttributedString(
                string: layout.text, attributes: [.font: font, .foregroundColor: style.text])
            text.addAttribute(
                .foregroundColor, value: style.text.withAlphaComponent(0.3),
                range: NSRange(location: 0, length: layout.typedCount))
            let size = text.size()
            text.draw(at: CGPoint(x: layout.box.midX - size.width / 2, y: layout.box.midY - size.height / 2))
        }
    }

    // 그리드는 칸 크기가 정해져 있어서 라벨 설정의 글자 크기, 여백, 유리를 쓰지 않고 칸에 맞춰 그린다.
    private func drawGrid() {
        let grid = Settings.gridStyle
        let label = Settings.labelStyle
        let cells = items.filter { $0.label.hasPrefix(typed) }
            .map { ($0.label, $0.target.frame.offsetBy(dx: -screenAXRect.minX, dy: -screenAXRect.minY)) }

        grid.line.withAlphaComponent(grid.lineOpacity).setStroke()
        for (_, cell) in cells { NSBezierPath(rect: cell).stroke() }
        if let highlight {
            let rect = highlight.offsetBy(dx: -screenAXRect.minX, dy: -screenAXRect.minY)
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2
            grid.line.setStroke()
            path.stroke()
        }

        for (name, cell) in cells {
            let string = label.uppercase ? name.uppercased() : name
            // 작은 칸에서는 글자가 칸 안에 들어가도록 줄인다.
            let fitted = min(cell.height * 0.85, cell.width * 1.3 / CGFloat(string.count))
            let font = Settings.labelFont(
                family: label.fontFamily, weight: label.fontWeight, size: max(min(grid.fontSize, fitted), 6))
            let text = NSMutableAttributedString(string: string, attributes: [.font: font, .foregroundColor: grid.text])
            text.addAttribute(
                .foregroundColor, value: grid.text.withAlphaComponent(0.3),
                range: NSRange(location: 0, length: typed.count))
            let size = text.size()
            let box = CGRect(
                x: cell.midX - size.width / 2 - 2, y: cell.midY - size.height / 2, width: size.width + 4,
                height: size.height
            ).intersection(cell.insetBy(dx: 1, dy: 1))
            grid.background.withAlphaComponent(grid.backgroundOpacity).setFill()
            NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
            text.draw(at: CGPoint(x: cell.midX - size.width / 2, y: cell.midY - size.height / 2))
        }
    }

    private func layouts(style: LabelStyle) -> [LabelLayout] {
        let font = style.font
        let pointed = showsPointers && style.pointer
        let arrowHeight = max(4, round(style.fontSize * 0.4))
        let padding = style.padding

        return items.filter { $0.label.hasPrefix(typed) }.enumerated().map { index, item in
            let text = style.uppercase ? item.label.uppercased() : item.label
            let textSize = (text as NSString).size(withAttributes: [.font: font])
            let height = ceil(textSize.height) + padding.height
            // 한 글자 라벨도 삼각형이 붙을 평평한 구간이 남도록 너비를 높이 이상으로 잡는다.
            let width = max(ceil(textSize.width) + padding.width, height)
            let radius = min(style.cornerRadius, min(width, height) / 2)
            let frame = item.target.frame.offsetBy(dx: -screenAXRect.minX, dy: -screenAXRect.minY)
            let maxX = bounds.width - width

            guard pointed else {
                let box = CGRect(
                    x: min(max(round(frame.midX - width / 2), 0), maxX),
                    y: min(max(round(frame.midY - height / 2), 0), bounds.height - height),
                    width: width, height: height)
                return LabelLayout(
                    id: index, text: text, typedCount: typed.count, box: box, radius: radius, pointer: nil)
            }

            // 작은 요소는 아래쪽 가장자리를, 큰 요소는 중앙 근처를 가리켜서 라벨이 대상을 덜 가린다.
            let reach = max(min(frame.height / 2 - 2, 10), 0)
            var tipY = round(frame.midY + reach)
            var box = CGRect(
                x: min(max(round(frame.midX - width / 2), 0), maxX), y: tipY + arrowHeight,
                width: width, height: height)
            var below = true
            if box.maxY > bounds.height {
                // 화면 아래에 자리가 없으면 라벨을 대상 위에 두고 아래로 가리킨다.
                tipY = round(frame.midY - reach)
                box.origin.y = tipY - arrowHeight - height
                below = false
            }

            let halfWidth = max(min(arrowHeight * 0.7, (width - 2 * radius) / 2), 2)
            // 상자가 화면 끝에 걸려 밀린 경우가 아니면 삼각형을 상자 정중앙에 둬서 좌우가 어긋나지 않게 한다.
            var arrowX = box.midX
            if abs(frame.midX - box.midX) > 1 {
                let margin = radius + halfWidth
                arrowX = min(max(round(frame.midX), box.minX + margin), max(box.maxX - margin, box.minX + margin))
            }
            // 둥근 모서리와 겹치는 구간에서도 삼각형이 상자와 이어지게 밑변을 상자 안쪽에 둔다.
            let inset = 1 + radius * 0.3
            let baseY = below ? box.minY + inset : box.maxY - inset
            let pointer = [
                CGPoint(x: arrowX, y: tipY),
                CGPoint(x: arrowX - halfWidth, y: baseY),
                CGPoint(x: arrowX + halfWidth, y: baseY),
            ]
            return LabelLayout(
                id: index, text: text, typedCount: typed.count, box: box, radius: radius, pointer: pointer)
        }
    }
}

@available(macOS 26.0, *)
private struct GlassLabels: View {
    let layouts: [LabelLayout]
    let style: LabelStyle

    var body: some View {
        // 가까이 있는 라벨끼리 한 덩어리로 합쳐지지 않게 간격을 0으로 둔다.
        GlassEffectContainer(spacing: 0) {
            ZStack(alignment: .topLeading) {
                ForEach(layouts) { layout in
                    let bounds = layout.bounds
                    let shape = OutlineShape(layout: layout)
                    label(layout)
                        .frame(width: layout.box.width, height: layout.box.height)
                        .offset(x: layout.box.minX - bounds.minX, y: layout.box.minY - bounds.minY)
                        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
                        .background {
                            if style.glassTint { shape.fill(Color(nsColor: style.background).opacity(0.5)) }
                        }
                        .glassEffect(.regular, in: shape)
                        .offset(x: bounds.minX, y: bounds.minY)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var textColor: Color {
        style.glassTint ? Color(nsColor: style.text) : .primary
    }

    private func label(_ layout: LabelLayout) -> some View {
        let typed = String(layout.text.prefix(layout.typedCount))
        let rest = String(layout.text.dropFirst(layout.typedCount))
        return (Text(typed).foregroundColor(textColor.opacity(0.35)) + Text(rest).foregroundColor(textColor))
            .font(Font(style.font as CTFont))
    }
}

private struct OutlineShape: Shape {
    let layout: LabelLayout

    func path(in rect: CGRect) -> Path {
        layout.outline(relativeTo: layout.bounds.origin)
    }
}

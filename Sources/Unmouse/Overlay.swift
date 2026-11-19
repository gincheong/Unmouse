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

    // 상자와 삼각형을 합친 외곽선. origin을 주면 그 점을 원점으로 옮긴 좌표로 만든다.
    func outline(relativeTo origin: CGPoint = .zero) -> Path {
        let shift = CGAffineTransform(translationX: -origin.x, y: -origin.y)
        var path = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if let pointer {
            let triangle = CGMutablePath()
            triangle.move(to: pointer[0])
            triangle.addLine(to: pointer[1])
            triangle.addLine(to: pointer[2])
            triangle.closeSubpath()
            path = path.union(triangle)
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
        if style.glass, #available(macOS 26.0, *) {
            let host = NSHostingView(rootView: GlassLabels(layouts: layouts(style: style), style: style))
            host.frame = bounds
            addSubview(host)
            glassHost = host
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let style = Settings.labelStyle

        if let highlight {
            let rect = highlight.offsetBy(dx: -screenAXRect.minX, dy: -screenAXRect.minY).insetBy(dx: 2, dy: 2)
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            path.lineWidth = 3
            style.background.setStroke()
            path.stroke()
        }
        if showsCells {
            style.background.withAlphaComponent(0.6).setStroke()
            for item in items where item.label.hasPrefix(typed) {
                let rect = item.target.frame.offsetBy(dx: -screenAXRect.minX, dy: -screenAXRect.minY)
                NSBezierPath(rect: rect).stroke()
            }
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
                            shape.fill(wash)
                            shape.fill(depth)
                            shape.fill(sheen)
                            glint(layout, in: bounds).clipShape(shape)
                        }
                        .overlay {
                            // 밝은 화면에서도 윤곽이 보이게 흰 테두리 바깥에 어두운 선을 겹친다.
                            shape.stroke(Color.black.opacity(0.3), lineWidth: 0.75)
                            // 색은 둘레 전체에 가늘게 두르고 아래쪽과 한쪽 옆만 조금 더 두껍게, 흰 반사는 위쪽에 둔다.
                            let side = variation(layout, 4) < 0.5 ? -0.3 : 0.3
                            shape.stroke(iridescence(layout), lineWidth: 0.4)
                            EdgeShape(layout: layout, shift: CGSize(width: side, height: -0.5))
                                .fill(iridescence(layout))
                            EdgeShape(layout: layout, shift: CGSize(width: -side, height: 0.6))
                                .fill(Color.white.opacity(0.9))
                            shape.stroke(rim, lineWidth: 0.5)
                        }
                        .glassEffect(.clear, in: shape)
                        .shadow(color: .black.opacity(0.45), radius: 3, y: 1.5)
                        .offset(x: bounds.minX, y: bounds.minY)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // 시스템 유리는 라벨 크기에서 광택 없이 평평하게 그려져서, 투명 유리 위에 색과 광택을 직접 얹는다.
    private var wash: Color {
        style.glassTint
            ? Color(nsColor: style.background).opacity(0.5) : Color(nsColor: .windowBackgroundColor).opacity(0.6)
    }

    private var sheen: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0)], startPoint: .top, endPoint: .center)
    }

    // 아래쪽을 어둡게 해서 유리의 두께처럼 보이게 한다.
    private var depth: LinearGradient {
        LinearGradient(colors: [.black.opacity(0), .black.opacity(0.22)], startPoint: .center, endPoint: .bottom)
    }

    private var rim: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.15)], startPoint: .top, endPoint: .bottom)
    }

    // 흰 테두리가 옅어지는 아래쪽 가장자리에 빛이 갈라진 색이 보인다.
    private func iridescence(_ layout: LabelLayout) -> AngularGradient {
        let colors: [Color] = [.cyan, .purple, .pink, .orange, .yellow, .mint, .cyan]
        return AngularGradient(
            colors: colors.map { $0.opacity(0.85) }, center: .center, angle: .degrees(variation(layout, 1) * 360))
    }

    // 라벨마다 광택이 다르게 보이도록 0과 1 사이 값을 만든다. 다시 그려도 바뀌지 않게 라벨 글자에서 계산한다.
    private func variation(_ layout: LabelLayout, _ salt: UInt64) -> Double {
        var hash = salt &* 0x9E37_79B9_7F4A_7C15
        for scalar in layout.text.unicodeScalars {
            hash = (hash ^ UInt64(scalar.value)) &* 0x100_0000_01B3
        }
        hash ^= hash >> 29
        return Double(hash % 1000) / 1000
    }

    // 상자 위쪽에 맺히는 반사광
    private func glint(_ layout: LabelLayout, in bounds: CGRect) -> some View {
        let box = layout.box
        return Color.clear.overlay(alignment: .topLeading) {
            Capsule()
                .fill(Color.white.opacity(0.9))
                .frame(width: box.width * (0.25 + 0.2 * variation(layout, 2)), height: max(1.5, box.height * 0.12))
                .blur(radius: 0.6)
                .offset(
                    x: box.minX - bounds.minX + box.width * (0.12 + 0.35 * variation(layout, 3)),
                    y: box.minY - bounds.minY + box.height * 0.13)
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

// 외곽선에서 shift만큼 옮긴 같은 모양을 뺀 영역. 옮긴 방향의 반대쪽 가장자리만 초승달 모양으로 남는다.
private struct EdgeShape: Shape {
    let layout: LabelLayout
    let shift: CGSize

    func path(in rect: CGRect) -> Path {
        let outline = layout.outline(relativeTo: layout.bounds.origin).cgPath
        var move = CGAffineTransform(translationX: shift.width, y: shift.height)
        guard let moved = outline.copy(using: &move) else { return Path() }
        return Path(outline.subtracting(moved))
    }
}

private struct OutlineShape: Shape {
    let layout: LabelLayout

    func path(in rect: CGRect) -> Path {
        layout.outline(relativeTo: layout.bounds.origin)
    }
}

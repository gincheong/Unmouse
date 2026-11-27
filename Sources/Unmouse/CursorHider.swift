import CoreGraphics
import Foundation

enum CursorHider {
    private static var hidden = false

    // CGDisplayHideCursor는 앱이 활성 상태일 때만 적용된다. 오버레이는 앱을 활성화하지 않으므로
    // 비공개 연결 속성 SetsCursorInBackground를 켠다. 심볼이 없는 macOS에서는 커서를 숨기지 않는다.
    private static let backgroundAllowed: Bool = {
        typealias DefaultConnection = @convention(c) () -> Int32
        typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        let handle = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        guard let connectionSymbol = dlsym(handle, "_CGSDefaultConnection"),
            let propertySymbol = dlsym(handle, "CGSSetConnectionProperty")
        else { return false }
        let connection = unsafeBitCast(connectionSymbol, to: DefaultConnection.self)()
        let setProperty = unsafeBitCast(propertySymbol, to: SetProperty.self)
        return setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue) == 0
    }()

    // hide와 show는 호출 횟수가 누적되므로 한 번씩만 호출한다.
    static func hide() {
        guard !hidden, backgroundAllowed else { return }
        hidden = CGDisplayHideCursor(CGMainDisplayID()) == .success
    }

    static func show() {
        guard hidden else { return }
        CGDisplayShowCursor(CGMainDisplayID())
        hidden = false
    }
}

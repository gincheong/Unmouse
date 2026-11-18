import AppKit
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = Controller()
    private let missionControl = MissionControlObserver()
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?
    private var loginItem: NSMenuItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        if AXIsProcessTrusted() {
            start()
        } else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard AXIsProcessTrusted() else { return }
                self?.permissionTimer?.invalidate()
                self?.start()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    private func start() {
        if !controller.installTap() {
            NSLog("Unmouse: event tap 생성 실패")
        }
        missionControl.onOpen = { [weak self] in self?.controller.missionControlOpened() }
        missionControl.onClose = { [weak self] in self?.controller.missionControlClosed() }
        missionControl.start()
        if let app = NSWorkspace.shared.frontmostApplication {
            enableAccessibility(for: app)
        }
    }

    @objc private func appActivated(_ notification: Notification) {
        guard AXIsProcessTrusted(),
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        enableAccessibility(for: app)
    }

    // 접근성 트리가 만들어지는 데 시간이 걸려서 클릭 모드를 켜기 전에 미리 요청해 둔다.
    private func enableAccessibility(for app: NSRunningApplication) {
        DispatchQueue.global(qos: .utility).async {
            AXScanner.enableAccessibility(for: app)
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "cursorarrow.click", accessibilityDescription: "Unmouse")

        let menu = NSMenu()
        let settings = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let login = NSMenuItem(title: "로그인 시 실행", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        loginItem = login
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Unmouse 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Unmouse 설정"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("Unmouse: 로그인 항목 변경 실패: \(error.localizedDescription)")
        }
        loginItem?.state = service.status == .enabled ? .on : .off
    }
}

// macOS 27에서는 Mission Control이 열릴 때 접근성 알림이 오지 않아서 열림 여부를 주기적으로 확인한다.
final class MissionControlObserver {
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?
    private var timer: DispatchSourceTimer?
    private var wasOpen = false

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "io.github.gincheong.Unmouse.mission-control", qos: .utility))
        timer.schedule(deadline: .now(), repeating: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self, Settings.missionControlEnabled else { return }
            let open = AXScanner().isMissionControlOpen()
            guard open != self.wasOpen else { return }
            self.wasOpen = open
            DispatchQueue.main.async {
                if open { self.onOpen?() } else { self.onClose?() }
            }
        }
        timer.resume()
        self.timer = timer
    }
}

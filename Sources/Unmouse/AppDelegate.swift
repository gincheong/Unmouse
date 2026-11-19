import AppKit
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = Controller()
    private let missionControl = MissionControlObserver()
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?
    private var settingsItem: NSMenuItem?
    private var loginItem: NSMenuItem?
    private var quitItem: NSMenuItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        setUpMainMenu()
        UserDefaults.standard.addObserver(self, forKeyPath: Settings.Keys.language, context: nil)
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { _ in Settings.saveConfigFile() }
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
            NSLog("Unmouse: failed to create the event tap")
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
        let settings = NSMenuItem(title: "", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        settingsItem = settings
        let login = NSMenuItem(title: "", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        loginItem = login
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        quitItem = quit
        item.menu = menu
        statusItem = item
        applyLanguage()
    }

    override func observeValue(
        forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        DispatchQueue.main.async { self.applyLanguage() }
    }

    private func applyLanguage() {
        settingsItem?.title = tr("Settings…", "설정…")
        loginItem?.title = tr("Launch at Login", "로그인 시 실행")
        quitItem?.title = tr("Quit Unmouse", "Unmouse 종료")
        settingsWindow?.title = tr("Unmouse Settings", "Unmouse 설정")
    }

    // Dock 아이콘이 없는 앱이라 메뉴는 보이지 않지만, 설정 창에서 ⌘Q, ⌘W, 편집 단축키가 동작하려면 메인 메뉴가 있어야 한다.
    private func setUpMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(
            NSMenuItem(title: "Quit Unmouse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        let mainMenu = NSMenu()
        for submenu in [appMenu, editMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = tr("Unmouse Settings", "Unmouse 설정")
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
            NSLog("Unmouse: failed to change the login item: \(error.localizedDescription)")
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

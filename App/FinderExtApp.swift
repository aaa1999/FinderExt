import AppKit
import ServiceManagement
import SwiftUI

@main
struct FinderExtApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var loginItemMenuItem: NSMenuItem?
    private var autoRenameMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "autoRenameAfterCreate": true,
        ])

        CommandCenter.shared.start { action, path in
            Task { @MainActor in
                self.dispatch(action: action, path: path)
            }
        }

        setupStatusItem()
        firstLaunchSetup()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = CommandCenter.shared.parse(url: url) else { continue }
            Task { @MainActor in
                self.dispatch(action: command.action, path: command.path)
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @MainActor
    private func dispatch(action: String, path: String) {
        guard CommandCenter.shared.isExistingDirectory(path) else { return }
        switch action {
        case "openTerminal":
            TerminalOpener.openTerminal(atPath: path)
        case "newFile":
            NewFilePanelController.shared.present(folderPath: path)
        default:
            break
        }
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "FinderExt")

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let enableItem = NSMenuItem(title: "启用 Finder 扩展…", action: #selector(openExtensionSettings(_:)), keyEquivalent: "")
        enableItem.target = self
        menu.addItem(enableItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "开机自动启动", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        loginItemMenuItem = loginItem

        let renameItem = NSMenuItem(title: "新建文件后自动重命名", action: #selector(toggleAutoRename(_:)), keyEquivalent: "")
        renameItem.target = self
        menu.addItem(renameItem)
        autoRenameMenuItem = renameItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 FinderExt", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func openExtensionSettings(_ sender: NSMenuItem) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("FinderExt: 切换登录项失败 \(error.localizedDescription)")
        }
    }

    @objc private func toggleAutoRename(_ sender: NSMenuItem) {
        let current = UserDefaults.standard.object(forKey: "autoRenameAfterCreate") as? Bool ?? true
        UserDefaults.standard.set(!current, forKey: "autoRenameAfterCreate")
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    // MARK: - 首次启动

    private func firstLaunchSetup() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "hasCompletedFirstLaunch") else { return }
        defaults.set(true, forKey: "hasCompletedFirstLaunch")

        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("FinderExt: 注册开机自启失败 \(error.localizedDescription)")
        }

        GuideWindowController.shared.show()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        loginItemMenuItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        autoRenameMenuItem?.state = (UserDefaults.standard.object(forKey: "autoRenameAfterCreate") as? Bool ?? true) ? .on : .off
    }
}

// MARK: - 首次启动引导窗口

final class GuideWindowController: NSWindowController {
    static let shared: GuideWindowController = {
        let view = GuideView { GuideWindowController.shared.closeWindow() }
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "FinderExt 使用引导"
        window.styleMask.formUnion([.titled, .closable])
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        let controller2 = GuideWindowController(window: window)
        window.center()
        return controller2
    }()

    func show() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() {
        close()
    }
}

struct GuideView: View {
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("FinderExt 安装完成", systemImage: "checkmark.seal.fill")
                .font(.title3)

            Divider()

            Text("最后一步：启用 Finder 扩展").font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                Label("点击「打开系统设置」，进入扩展设置页", systemImage: "1.circle")
                Label("在「Finder 扩展」中打开 FinderExt 的开关", systemImage: "2.circle")
                Label("回到 Finder，在任意文件夹内右键即可使用新功能", systemImage: "3.circle")
            }
            .font(.body)

            Text("右键新增的两项与 Finder 原有菜单合并显示，不影响原有功能。菜单栏图标中可调整「开机自启」「自动重命名」。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("稍后再说") { close() }
                Button("打开系统设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
                        NSWorkspace.shared.open(url)
                    }
                    close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 470)
    }
}

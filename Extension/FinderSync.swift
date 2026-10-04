import Cocoa
import FinderSync

/// Finder Sync 扩展：负责在 Finder 右键菜单中【追加】两个菜单项，
/// 点击后把目标文件夹路径发送给宿主 App 执行。
/// 菜单项由系统合并进 Finder 原生右键菜单，不会修改/覆盖原有条目。
class FinderSync: FIFinderSync {
    /// 右键时解析出的目标文件夹，菜单构建时缓存，点击时使用。
    private var pendingTargetFolder: URL?

    override init() {
        super.init()
        // 监听根目录，保证在任何文件夹右键都能出现菜单。
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        pendingTargetFolder = resolveTargetFolder(menuKind: menuKind)

        let menu = NSMenu(title: "FinderExt")

        let terminalItem = NSMenuItem(
            title: "在此打开终端",
            action: #selector(openTerminalHere(_:)),
            keyEquivalent: ""
        )
        terminalItem.target = self
        terminalItem.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)

        let newFileItem = NSMenuItem(
            title: "新建文件…",
            action: #selector(newFileHere(_:)),
            keyEquivalent: ""
        )
        newFileItem.target = self
        newFileItem.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)

        menu.addItem(terminalItem)
        menu.addItem(newFileItem)
        return menu
    }

    /// 目标文件夹解析：
    /// - 空白处右键 → 当前文件夹（targetedURL）
    /// - 选中单个文件夹右键 → 该文件夹
    /// - 选中单个文件右键 → 文件所在文件夹
    /// - 其他（多选等）→ 当前文件夹
    private func resolveTargetFolder(menuKind: FIMenuKind) -> URL? {
        let controller = FIFinderSyncController.default()

        if menuKind == .contextualMenuForContainer || menuKind == .contextualMenuForSidebar {
            return controller.targetedURL()
        }

        let selections = controller.selectedItemURLs() ?? []
        if selections.count == 1 {
            let url = selections[0]
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return url
            }
            return url.deletingLastPathComponent()
        }
        return controller.targetedURL()
    }

    @objc private func openTerminalHere(_ sender: Any?) {
        sendCommand(action: "openTerminal")
    }

    @objc private func newFileHere(_ sender: Any?) {
        sendCommand(action: "newFile")
    }

    private func sendCommand(action: String) {
        guard let folder = pendingTargetFolder else { return }

        var components = URLComponents()
        components.scheme = "finderext"
        components.host = "command"
        components.queryItems = [
            URLQueryItem(name: "action", value: action),
            URLQueryItem(name: "path", value: folder.path),
        ]

        if let url = components.url, NSWorkspace.shared.open(url) {
            return
        }

        // 兜底：URL 方式失败时改用分布式通知。
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(CommandCenterNotificationName),
            object: nil,
            userInfo: ["action": action, "path": folder.path],
            deliverImmediately: true
        )
    }
}

private let CommandCenterNotificationName = "com.lwc.finderext.command"

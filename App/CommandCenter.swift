import Foundation

struct FinderCommand {
    let action: String
    let path: String
}

/// 接收 Finder 扩展发来的命令。
/// 主通道：自定义 URL Scheme（finderext://command?action=…&path=…），
/// 宿主未运行时系统会自动拉起应用，命令不丢失。
/// 备用通道：NSDistributedNotificationCenter（扩展端 URL 方式失败时使用）。
final class CommandCenter {
    static let shared = CommandCenter()
    static let notificationName = "com.lwc.finderext.command"

    private var handler: ((String, String) -> Void)?

    func start(handler: @escaping (String, String) -> Void) {
        self.handler = handler
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleDistributedNotification(_:)),
            name: Notification.Name(Self.notificationName),
            object: nil
        )
    }

    @objc private func handleDistributedNotification(_ notification: Notification) {
        guard let info = notification.userInfo,
              let action = info["action"] as? String,
              let path = info["path"] as? String else { return }
        handler?(action, path)
    }

    /// 解析 finderext://command?action=xxx&path=/…
    func parse(url: URL) -> FinderCommand? {
        guard url.scheme?.lowercased() == "finderext",
              url.host?.lowercased() == "command",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var action: String?
        var path: String?
        for item in components.queryItems ?? [] {
            if item.name == "action" { action = item.value }
            if item.name == "path" { path = item.value }
        }
        guard let action, let path else { return nil }
        return FinderCommand(action: action, path: path)
    }

    func isExistingDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

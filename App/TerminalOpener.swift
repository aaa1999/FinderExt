import AppKit

/// 在指定文件夹打开终端。
///
/// 首选「一次性 .command 文件」方案：传给终端的只是本应用缓存目录里的脚本文件，
/// 目标文件夹仅由 shell 通过 `cd` 进入——不把目标文件夹作为文档打开，
/// 从而避免 macOS 26+ 的“按文件夹授权”弹窗。
/// 若该方案失败，回退为直接把文件夹交给 Terminal（可能触发按文件夹授权）。
enum TerminalOpener {
    static func openTerminal(atPath path: String) {
        if openViaCommandFile(path) { return }

        let folderURL = URL(fileURLWithPath: path)
        let terminalPath = UserDefaults.standard.string(forKey: "terminalAppPath")
            ?? "/System/Applications/Utilities/Terminal.app"
        guard FileManager.default.fileExists(atPath: terminalPath) else { return }
        let terminalURL = URL(fileURLWithPath: terminalPath)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        Task {
            try? await NSWorkspace.shared.open([folderURL], withApplicationAt: terminalURL, configuration: configuration)
        }
    }

    private static func openViaCommandFile(_ path: String) -> Bool {
        guard let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return false
        }
        let scriptDirectory = cacheDirectory.appendingPathComponent("com.lwc.finderext", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        } catch {
            return false
        }

        let scriptURL = scriptDirectory.appendingPathComponent("open-\(UUID().uuidString).command")
        let shellPath = path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        #!/bin/zsh
        cd '\(shellPath)' || exit 1
        rm -f "$0"
        exec -l "${SHELL:-/bin/zsh}" -i

        """
        guard FileManager.default.createFile(atPath: scriptURL.path, contents: script.data(using: .utf8)) else {
            return false
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        // .command 的默认处理应用即用户默认终端；打开成功后由脚本自行清理。
        return NSWorkspace.shared.open(scriptURL)
    }
}

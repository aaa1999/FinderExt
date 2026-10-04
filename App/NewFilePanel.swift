import AppKit
import SwiftUI

@MainActor
final class NewFilePanelController {
    static let shared = NewFilePanelController()

    private var panel: NSPanel?

    func present(folderPath: String) {
        panel?.orderOut(nil)

        let folder = URL(fileURLWithPath: folderPath)
        let viewModel = NewFileViewModel(folder: folder)
        viewModel.onFinish = { [weak self] in
            self?.panel?.orderOut(nil)
        }

        let hostingController = NSHostingController(rootView: NewFileView(viewModel: viewModel))
        let newPanel = NSPanel(contentViewController: hostingController)
        newPanel.title = "新建文件"
        newPanel.styleMask.formUnion([.titled, .closable])
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.hidesOnDeactivate = false
        newPanel.isReleasedWhenClosed = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        newPanel.standardWindowButton(.zoomButton)?.isHidden = true

        let contentSize = hostingController.view.fittingSize
        newPanel.setContentSize(NSSize(width: max(contentSize.width, 380), height: contentSize.height))
        newPanel.setFrameOrigin(positionNearMouse(panelSize: newPanel.frame.size))

        panel = newPanel
        NSApp.activate(ignoringOtherApps: true)
        newPanel.makeKeyAndOrderFront(nil)
    }

    private func positionNearMouse(panelSize: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let candidate = NSPoint(x: mouse.x + 24, y: mouse.y - panelSize.height / 2)
        guard let screen = NSScreen.main else { return candidate }
        let visible = screen.visibleFrame
        let x = min(max(candidate.x, visible.minX), visible.maxX - panelSize.width)
        let y = min(max(candidate.y, visible.minY), visible.maxY - panelSize.height)
        return NSPoint(x: x, y: y)
    }
}

@MainActor
final class NewFileViewModel: ObservableObject {
    let folder: URL
    @Published var name: String = ""
    @Published var errorMessage: String?
    @Published var isCreating = false
    var onFinish: (() -> Void)?

    init(folder: URL) {
        self.folder = folder
    }

    func cancel() {
        onFinish?()
    }

    func create() {
        guard !isCreating else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "请输入文件名"
            return
        }
        guard !trimmed.contains("/") else {
            errorMessage = "文件名不能包含 “/”"
            return
        }
        guard !trimmed.contains(":") else {
            errorMessage = "文件名不能包含 “:”"
            return
        }
        guard trimmed.count <= 255 else {
            errorMessage = "文件名过长"
            return
        }

        isCreating = true
        errorMessage = nil
        let folder = self.folder

        Task { [weak self] in
            let result = FileCreation.createFile(named: trimmed, in: folder)
            await MainActor.run {
                guard let self else { return }
                self.isCreating = false
                switch result {
                case .success(let url):
                    self.onFinish?()
                    self.revealInFinder(url)
                case .duplicate:
                    self.errorMessage = "同名文件已存在，请换个名字"
                case .failure(let message):
                    self.errorMessage = message
                }
            }
        }
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        if UserDefaults.standard.object(forKey: "autoRenameAfterCreate") as? Bool ?? true {
            RenameTrigger.trigger()
        }
    }
}

/// 建文件策略：
/// 首选通过 Finder AppleScript 让 Finder 代建——文件系统操作全部由 Finder 完成，
/// 本应用不触碰磁盘，因此不会触发 macOS 的“按文件夹授权”弹窗；
/// 全局只需一次“控制 Finder”的自动化授权。
/// 若自动化未授权/失败，则回退为本应用直接创建（此时可能触发文件夹授权弹窗）。
enum FileCreation {
    enum Result {
        case success(URL)
        case duplicate
        case failure(String)
    }

    static func createFile(named name: String, in folder: URL) -> Result {
        if case .some(let result) = createViaFinder(name: name, folder: folder) {
            switch result {
            case .success, .duplicate:
                return result
            case .failure:
                break
            }
        }

        let target = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: target.path) {
            return .duplicate
        }
        if FileManager.default.createFile(atPath: target.path, contents: nil) {
            return .success(target)
        }
        return .failure("创建失败（可能没有写入权限）")
    }

    private static func createViaFinder(name: String, folder: URL) -> Result? {
        let folderPath = appleScriptEscaped(folder.path)
        let fileName = appleScriptEscaped(name)
        let script = """
        tell application "Finder"
            set targetFolder to (POSIX file "\(folderPath)" as alias)
            if (exists file "\(fileName)" of targetFolder) then
                return "EXISTS"
            end if
            set newFile to make new file at targetFolder with properties {name:"\(fileName)"}
            set extension hidden of newFile to false
        end tell
        """
        guard let appleScript = NSAppleScript(source: script) else { return nil }
        var errorInfo: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            NSLog("FinderExt: Finder 代建文件失败 \(errorInfo)")
            return .failure("Finder 代建失败")
        }
        if descriptor.stringValue == "EXISTS" {
            return .duplicate
        }
        return .success(folder.appendingPathComponent(name))
    }

    private static func appleScriptEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

/// 创建并在 Finder 中选中后，尝试按回车进入“重命名”状态。
/// 依赖辅助功能/Automation 权限，失败则静默降级（文件保持选中）。
enum RenameTrigger {
    static func trigger() {
        let script = """
        tell application "Finder" to activate
        delay 0.25
        tell application "System Events" to keystroke return
        """
        DispatchQueue.global(qos: .userInitiated).async {
            let appleScript = NSAppleScript(source: script)
            var errorInfo: NSDictionary?
            appleScript?.executeAndReturnError(&errorInfo)
        }
    }
}

struct NewFileView: View {
    @ObservedObject var viewModel: NewFileViewModel
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("在当前文件夹下新建文件")
                .font(.headline)

            Text(viewModel.folder.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            TextField("完整文件名（含后缀）", text: $viewModel.name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFieldFocused)
                .onSubmit { viewModel.create() }

            if let message = viewModel.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) { viewModel.cancel() }
                    .keyboardShortcut(.cancelAction)
                Button(viewModel.isCreating ? "创建中…" : "创建") { viewModel.create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.isCreating)
            }
        }
        .padding(16)
        .frame(width: 380)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                nameFieldFocused = true
            }
        }
    }
}

import AppKit
import ServiceManagement

let refreshSeconds: TimeInterval = 10

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let engine = Bundle.main.path(forResource: "wakey", ofType: "sh")!
    let queue = DispatchQueue(label: "wakey.engine")
    var menuOpen = false

    func applicationDidFinishLaunching(_ note: Notification) {
        refresh()
        Timer.scheduledTimer(withTimeInterval: refreshSeconds, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        queue.async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: self.engine)
            let out = Pipe(), err = Pipe()
            proc.standardOutput = out
            proc.standardError = err
            var output = "", message = ""
            var status: Int32 = -1
            do {
                try proc.run()
                output = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                message = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                proc.waitUntilExit()
                status = proc.terminationStatus
            } catch {
                message = "\(error)"
            }
            DispatchQueue.main.async {
                if status == 0 {
                    self.render(output)
                } else {
                    self.showFailure(message.isEmpty ? "wakey.sh exited \(status)" : message)
                }
            }
        }
    }

    func render(_ output: String) {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        statusItem.button?.image = titleImage(parseLine(lines[0]))
        statusItem.button?.title = ""
        if menuOpen { return }

        let menu = NSMenu()
        menu.delegate = self
        var stack = [menu]
        for raw in lines.dropFirst().drop(while: { $0 != separator }).dropFirst() where !raw.isEmpty {
            if raw == separator {
                menu.addItem(.separator())
                stack = [menu]
                continue
            }
            let line = parseLine(raw)
            stack.removeLast(max(0, stack.count - line.depth - 1))
            if line.depth == stack.count, let parent = stack.last?.items.last {
                let sub = NSMenu()
                parent.submenu = sub
                stack.append(sub)
            }
            stack.last!.addItem(item(line))
        }
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Open at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(quitItem())
        statusItem.menu = menu
    }

    func item(_ line: Line) -> NSMenuItem {
        let item = NSMenuItem(title: line.text, action: nil, keyEquivalent: "")
        var font = NSFont.menuFont(ofSize: 0)
        if let name = line.params["font"], let custom = NSFont(name: name, size: CGFloat(Double(line.params["size"] ?? "") ?? font.pointSize)) {
            font = custom
        }
        item.attributedTitle = styled(line.text, font: font, color: .labelColor)
        if line.params["bash"] != nil {
            item.action = #selector(run(_:))
            item.target = self
            item.representedObject = line.params
        }
        if line.params["checked"] == "true" { item.state = .on }
        if let symbol = line.params["sfimage"] { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol) }
        return item
    }

    func quitItem() -> NSMenuItem {
        let quit = NSMenuItem(title: "Quit Wakey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        return quit
    }

    func showFailure(_ message: String) {
        statusItem.button?.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Wakey error")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: String(message.prefix(200)), action: nil, keyEquivalent: ""))
        menu.addItem(quitItem())
        statusItem.menu = menu
    }

    @objc func run(_ sender: NSMenuItem) {
        guard let params = sender.representedObject as? [String: String], let exe = params["bash"] else { return }
        let args = (1...9).compactMap { params["param\($0)"] }
        queue.async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            proc.arguments = args
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                proc.waitUntilExit()
            } catch {
                NSLog("Wakey: cannot run \(exe): \(error)")
            }
            if params["refresh"] == "true" { self.refresh() }
        }
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Wakey: login item: \(error)")
        }
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) { menuOpen = true }
    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        refresh()
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

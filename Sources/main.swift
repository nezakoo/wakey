import AppKit
import ServiceManagement
import UserNotifications

// The title shows minutes, so a slow timer is enough; the menu itself is rebuilt as it opens.
let refreshSeconds: TimeInterval = 60
let warnBeforeEndSeconds: TimeInterval = 300
let endingNotification = "ending"
let extendAction = "extend"
let releasesAPI = URL(string: "https://api.github.com/repos/nezakoo/wakey/releases/latest")!
let installCommand = "curl -fsSL https://raw.githubusercontent.com/nezakoo/wakey/main/install.sh | bash"

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    let engine = Bundle.main.path(forResource: "wakey", ofType: "sh")!
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    let queue = DispatchQueue(label: "wakey.engine")
    var menuOpen = false
    var scheduledEnd: String?

    func applicationDidFinishLaunching(_ note: Notification) {
        menu.delegate = self
        statusItem.menu = menu
        setUpNotifications()
        refresh()
        let timer = Timer.scheduledTimer(withTimeInterval: refreshSeconds, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 10
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    func runEngine(_ args: [String] = []) -> (status: Int32, output: String, message: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: engine)
        proc.arguments = args
        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        do {
            try proc.run()
            let output = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let message = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            proc.waitUntilExit()
            return (proc.terminationStatus, output, message)
        } catch {
            return (-1, "", "\(error)")
        }
    }

    func refresh() {
        queue.async {
            let result = self.runEngine()
            DispatchQueue.main.async { self.apply(result) }
        }
    }

    func apply(_ result: (status: Int32, output: String, message: String)) {
        if result.status == 0 {
            render(result.output)
        } else {
            showFailure(result.message.isEmpty ? "wakey.sh exited \(result.status)" : result.message)
        }
    }

    func render(_ output: String) {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let title = parseLine(lines[0])
        statusItem.button?.image = titleImage(title)
        scheduleEndingWarning(title.params["end"])
        if menuOpen { return }

        menu.removeAllItems()
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
        let update = NSMenuItem(title: "Check for updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        addQuitItems()
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

    // Quit ends the session too, so nothing keeps the Mac awake unseen; hold Option to keep it.
    func addQuitItems() {
        let quit = NSMenuItem(title: "Quit Wakey", action: #selector(quitStopping), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        let keep = NSMenuItem(title: "Quit Wakey, keep awake", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        keep.keyEquivalentModifierMask = [.command, .option]
        keep.isAlternate = true
        keep.target = NSApp
        menu.addItem(keep)
    }

    func showFailure(_ message: String) {
        statusItem.button?.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Wakey error")
        if menuOpen { return }
        menu.removeAllItems()
        menu.addItem(NSMenuItem(title: String(message.prefix(200)), action: nil, keyEquivalent: ""))
        addQuitItems()
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

    @objc func quitStopping() {
        _ = runEngine(["stop"])
        NSApp.terminate(nil)
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

    // MARK: Ending warning

    func setUpNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let extend = UNNotificationAction(identifier: extendAction, title: "+1h")
        center.setNotificationCategories([UNNotificationCategory(identifier: endingNotification, actions: [extend], intentIdentifiers: [])])
    }

    // end is the epoch the engine reports for a timed session of Wakey's own; nil means none.
    func scheduleEndingWarning(_ end: String?) {
        if end == scheduledEnd { return }
        scheduledEnd = end
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [endingNotification])
        guard let end, let epoch = TimeInterval(end) else { return }
        let delay = epoch - warnBeforeEndSeconds - Date().timeIntervalSince1970
        guard delay > 0 else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Wakey"
            content.body = "Keeping awake ends in 5 minutes."
            content.categoryIdentifier = endingNotification
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            center.add(UNNotificationRequest(identifier: endingNotification, content: content, trigger: trigger))
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        if response.actionIdentifier == extendAction {
            queue.async {
                _ = self.runEngine(["extend"])
                self.refresh()
            }
        }
        done()
    }

    // MARK: Updates

    // Only on request: Wakey makes no network calls of its own.
    @objc func checkForUpdates() {
        var request = URLRequest(url: releasesAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let tag = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["tag_name"] as? String
            DispatchQueue.main.async {
                guard let tag, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    self.alert("Couldn't check for updates", error?.localizedDescription ?? "No release found on GitHub.")
                    return
                }
                self.offerUpdate(String(tag.drop(while: { $0 == "v" })))
            }
        }.resume()
    }

    func offerUpdate(_ latest: String) {
        guard latest.compare(version, options: .numeric) == .orderedDescending else {
            alert("Wakey is up to date", "Version \(version) is the latest.")
            return
        }
        let viaBrew = Bundle.main.bundlePath.contains("/Cellar/")
        let command = viaBrew ? "brew upgrade wakey" : installCommand
        let choice = alert("Wakey \(latest) is available", "You have \(version). To update, run in Terminal:\n\n\(command)",
                           buttons: ["Copy command", "Release notes", "Later"])
        if choice == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        } else if choice == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://github.com/nezakoo/wakey/releases/latest")!)
        }
    }

    @discardableResult
    func alert(_ title: String, _ text: String, buttons: [String] = ["OK"]) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        buttons.forEach { alert.addButton(withTitle: $0) }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    // MARK: Menu

    // Rebuilt synchronously so it never opens stale; the engine takes ~0.1 s.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === self.menu { apply(runEngine()) }
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

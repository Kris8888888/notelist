import AppKit
import ServiceManagement
import SwiftUI

@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        let d = AppDelegate()
        app.delegate = d
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controllers: [UUID: NoteWindowController] = [:]
    private var status: NSStatusItem!
    private var loginItem: NSMenuItem!
    private var trashItem: NSMenuItem!

    func applicationDidFinishLaunching(_ n: Notification) {
        buildMainMenu()
        buildStatusItem()
        let store = Store.shared
        store.load()
        Reminders.shared.setup()
        store.onSaved = { Reminders.shared.reschedule(Store.shared.notes) }
        if store.notes.isEmpty && !FileManager.default.fileExists(atPath: store.file.path) {
            firstRun()
        }
        store.notes.forEach(open)
        Reminders.shared.reschedule(store.notes)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showAll()
        return true
    }

    func applicationWillTerminate(_ n: Notification) { Store.shared.save() }

    // MARK: - 便笺

    private func open(_ note: Note) {
        let c = NoteWindowController(note: note)
        c.onRemoved = { [weak self] n in
            let frame = self?.controllers[n.id]?.window?.frame ?? .zero
            Store.shared.moveToTrash(n)
            Store.shared.remove(n)
            self?.controllers[n.id]?.close()
            self?.controllers[n.id] = nil
            if !n.isEmpty {
                let name = n.title.isEmpty ? "便笺" : "「\(n.title)」"
                ToastPanel.shared.show("已删除\(name)", near: frame) { self?.restore(n.id) }
            }
        }
        controllers[note.id] = c
        c.showWindow(nil)
    }

    private func nextFrame() -> CGRect {
        let size = CGSize(width: 270, height: 320)
        if let key = NSApp.keyWindow, controllers.values.contains(where: { $0.window === key }) {
            let f = key.frame
            return CGRect(x: f.minX + 26, y: f.maxY - 26 - size.height, width: size.width, height: size.height)
        }
        let vis = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let k = CGFloat(Store.shared.notes.count % 8)
        return CGRect(x: vis.maxX - size.width - 40 - k * 26, y: vis.maxY - size.height - 40 - k * 26,
                      width: size.width, height: size.height)
    }

    @discardableResult
    private func createNote(title: String = "", items: [TodoItem] = []) -> Note {
        let color = Palette.all[Store.shared.notes.count % (Palette.all.count - 1)].key
        let note = Note(title: title, items: items, color: color, frame: nextFrame())
        Store.shared.add(note)
        open(note)
        return note
    }

    private func firstRun() {
        createNote(title: "今天", items: [
            TodoItem(text: "点左边的圆圈，勾掉一条"),
            TodoItem(text: "回车新起一条，⌥↑ ⌥↓ 调顺序"),
            TodoItem(text: "双击顶部空白处收起成一行"),
            TodoItem(text: "鼠标移到顶部可换颜色、置顶"),
        ])
    }

    @objc func newNote() {
        NSApp.activate(ignoringOtherApps: true)
        createNote()
    }

    @objc func showHistory() { HistoryWindow.shared.show() }

    func restore(_ id: UUID) {
        guard let n = Store.shared.takeFromTrash(id) else { return }
        Store.shared.add(n)
        open(n)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func restoreFromMenu(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { restore(id) }
    }

    @objc func showAll() {
        NSApp.activate(ignoringOtherApps: true)
        if controllers.isEmpty { createNote(); return }
        controllers.values.forEach { $0.window?.orderFront(nil) }
    }

    @objc func importStickies() {
        let result = StickiesImporter.run()
        let a = NSAlert()
        switch result {
        case .notFound:
            a.messageText = "没找到系统便笺的数据"
            a.informativeText = "系统「便笺」里还没有便笺，或者本机没装这个应用。"
        case .denied:
            a.messageText = "没有权限读取系统便笺"
            a.informativeText = "如果弹出了「想访问其他 App 的数据」，请点允许后再导入一次。"
        case .notes(let list):
            list.forEach { createNote(title: $0.title, items: $0.items) }
            a.messageText = list.isEmpty ? "系统便笺都是空的" : "导入了 \(list.count) 张便笺"
            a.informativeText = list.isEmpty ? "" : "每一行变成一条事项，第一行当标题。系统便笺里的原件没动。"
        }
        a.runModal()
    }

    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        do {
            if s.status == .enabled { try s.unregister() } else { try s.register() }
        } catch {
            let a = NSAlert()
            a.messageText = "设置开机启动没成功"
            a.informativeText = "先把「便笺清单」拖进「应用程序」文件夹，再打开设置一次。"
            a.runModal()
        }
        loginItem.state = s.status == .enabled ? .on : .off
    }

    // MARK: - 菜单

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于便笺清单", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏便笺清单", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出便笺清单", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let file = NSMenu(title: "文件")
        file.addItem(withTitle: "新建便笺", action: #selector(newNote), keyEquivalent: "n")
        file.addItem(withTitle: "从系统便笺导入…", action: #selector(importStickies), keyEquivalent: "")
        file.addItem(.separator())
        file.addItem(withTitle: "删除便笺", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = file

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "窗口")
        win.addItem(withTitle: "显示全部便笺", action: #selector(showAll), keyEquivalent: "0")
        win.addItem(withTitle: "已完成记录", action: #selector(showHistory), keyEquivalent: "y")
        win.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = win
        NSApp.windowsMenu = win

        NSApp.mainMenu = main
    }

    private func buildStatusItem() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "便笺清单")
        let m = NSMenu()
        m.addItem(withTitle: "新建便笺", action: #selector(newNote), keyEquivalent: "")
        m.addItem(withTitle: "显示全部便笺", action: #selector(showAll), keyEquivalent: "")
        m.addItem(withTitle: "已完成记录", action: #selector(showHistory), keyEquivalent: "")
        trashItem = m.addItem(withTitle: "最近删除的便笺", action: nil, keyEquivalent: "")
        trashItem.submenu = NSMenu()
        m.addItem(.separator())
        m.addItem(withTitle: "从系统便笺导入…", action: #selector(importStickies), keyEquivalent: "")
        loginItem = m.addItem(withTitle: "开机自动打开", action: #selector(toggleLogin), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        m.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) && $0.action != nil { $0.target = self } }
        m.delegate = self
        status.menu = m
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let sub = trashItem.submenu!
        sub.removeAllItems()
        let trash = Store.shared.trash
        if trash.isEmpty {
            let empty = sub.addItem(withTitle: "没有删除过的便笺", action: nil, keyEquivalent: "")
            empty.isEnabled = false
        }
        for n in trash {
            let name = n.title.isEmpty ? (n.items.first?.text ?? "无标题") : n.title
            let it = sub.addItem(withTitle: "\(name)（\(n.items.count) 条）", action: #selector(restoreFromMenu(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = n.id
        }
    }
}

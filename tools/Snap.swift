import AppKit
import SwiftUI
@main struct Snap { static func main() {
    let app = NSApplication.shared; app.setActivationPolicy(.accessory)
    func render(_ v: NSView, _ path: String) {
        let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
        v.cacheDisplay(in: v.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
    func shot(_ n: Note, _ size: CGSize, _ path: String) {
        let c = NoteWindowController(note: n)
        let w = c.window!; w.setFrame(CGRect(origin: .zero, size: size), display: true)
        c.showWindow(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        render(w.contentView!, path)
    }
    func it(_ t: String, star: Bool = false, indent: Int = 0, due: Date? = nil, time: Bool = false, done: Bool = false) -> TodoItem {
        var x = TodoItem(text: t, done: done, doneAt: done ? Date() : nil); x.starred = star; x.indent = indent; x.due = due; x.dueHasTime = time; return x
    }
    let cal = Calendar.current; let today = cal.startOfDay(for: Date())
    let a = Note(title: "这周要做", items: [
        it("改完首页方案第二版", star: true, due: cal.date(byAdding: .day, value: -1, to: today)),
        it("补空状态页", indent: 1),
        it("确认列表上限", indent: 1, done: true),
        it("组会", due: cal.date(bySettingHour: 15, minute: 0, second: 0, of: today), time: true),
        it("发周报", due: cal.date(byAdding: .day, value: 2, to: today)),
        it("整理会议纪要", done: true),
    ], color: "apricot", frame: .zero)
    a.showDone = true
    shot(a, CGSize(width: 280, height: 400), "/tmp/snap_a.png")
    let b = Note(title: "买菜", items: [it("鸡蛋", star: true), it("番茄", done: true), it("牛奶", due: cal.date(byAdding: .day, value: -2, to: today))], color: "ink", frame: .zero)
    shot(b, CGSize(width: 240, height: 220), "/tmp/snap_b.png")
    // 历史窗口
    let host = NSHostingView(rootView: HistoryView(store: Store.shared))
    host.frame = NSRect(x: 0, y: 0, width: 380, height: 480)
    let w = NSWindow(contentRect: host.frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
    w.titlebarAppearsTransparent = true; w.contentView = host; w.orderFront(nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    render(host, "/tmp/snap_h.png")
}}

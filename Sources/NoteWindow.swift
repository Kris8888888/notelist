import AppKit
import Combine
import SwiftUI

final class NoteWindowController: NSWindowController, NSWindowDelegate {
    let note: Note
    var onRemoved: ((Note) -> Void)?
    private var bag = Set<AnyCancellable>()
    static let collapsedHeight: CGFloat = 41

    init(note: Note) {
        self.note = note
        let w = NSWindow(contentRect: note.frame,
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            w.standardWindowButton(b)?.isHidden = true
        }
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 200, height: Self.collapsedHeight)
        w.setFrame(note.frame, display: false)
        super.init(window: w)
        w.delegate = self

        let host = NSHostingView(rootView: NoteView(
            note: note,
            onDelete: { [weak self] in self?.confirmDelete() },
            onToggleCollapse: { [weak self] in self?.toggleCollapse() }))
        host.sizingOptions = []
        // 底层磨砂玻璃，上面盖一层可调透明度的纸色（纸色画在 SwiftUI 里）
        w.isOpaque = false
        w.backgroundColor = .clear
        let root = NSView()
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        root.layer?.masksToBounds = true
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        for v in [blur, host as NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                v.topAnchor.constraint(equalTo: root.topAnchor),
                v.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            ])
        }
        w.contentView = root
        note.$glass.sink { on in
            blur.isHidden = !on
            DispatchQueue.main.async { w.invalidateShadow() }
        }.store(in: &bag)
        note.$opacity.sink { _ in DispatchQueue.main.async { w.invalidateShadow() } }.store(in: &bag)

        note.$color.sink { key in
            let p = Palette.named(key)
            w.appearance = NSAppearance(named: p.dark ? .darkAqua : .aqua)
        }.store(in: &bag)
        note.$pinned.sink { pinned in
            w.level = pinned ? .floating : .normal
            w.collectionBehavior = pinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
        }.store(in: &bag)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // 有内容的便笺打开时不自动选中标题
        if !note.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(nil) }
        }
    }

    func toggleCollapse() {
        guard let w = window else { return }
        var f = w.frame
        let top = f.maxY
        if note.collapsed {
            f.size.height = max(note.expandedHeight, 140)
        } else {
            note.expandedHeight = f.height
            f.size.height = Self.collapsedHeight
        }
        f.origin.y = top - f.height
        note.collapsed.toggle()
        w.setFrame(f, display: true, animate: true)
        record()
    }

    func confirmDelete() {
        guard let w = window else { return }
        if note.isEmpty { remove(); return }
        let a = NSAlert()
        a.messageText = "删除这张便笺？"
        let n = note.items.count
        a.informativeText = n > 0 ? "里面的 \(n) 条事项会一起删除，删除后找不回来。" : "删除后找不回来。"
        a.addButton(withTitle: "删除")
        a.addButton(withTitle: "取消")
        a.buttons[0].hasDestructiveAction = true
        a.beginSheetModal(for: w) { [weak self] r in
            if r == .alertFirstButtonReturn { self?.remove() }
        }
    }

    private func remove() {
        window?.orderOut(nil)
        onRemoved?(note)
    }

    private func record() {
        guard let w = window else { return }
        note.frame = w.frame
        if !note.collapsed { note.expandedHeight = w.frame.height }
        Store.shared.save()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        confirmDelete()
        return false
    }

    func windowDidMove(_ n: Notification) { record() }
    func windowDidEndLiveResize(_ n: Notification) { record() }
}

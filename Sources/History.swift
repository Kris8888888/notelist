import AppKit
import SwiftUI

/// 已完成记录：按天列出勾掉的事项，方便写日报周报
struct HistoryView: View {
    @ObservedObject var store: Store
    @State private var query = ""
    @State private var copied: Date?

    private let p = Palette.named("stone")
    private let cal = Calendar.current

    private var days: [(Date, [DoneRecord])] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let list = store.history.filter { q.isEmpty || $0.text.localizedCaseInsensitiveContains(q) || $0.note.localizedCaseInsensitiveContains(q) }
        let groups = Dictionary(grouping: list) { cal.startOfDay(for: $0.doneAt) }
        return groups.keys.sorted(by: >).map { d in (d, groups[d]!.sorted { $0.doneAt > $1.doneAt }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundColor(p.text.opacity(0.4))
                TextField("", text: $query)
                    .textFieldStyle(.plain)
                    .focusEffectDisabled()
                    .font(.system(size: 13))
                    .background(alignment: .leading) {
                        if query.isEmpty {
                            Text("搜索事项或便笺名").font(.system(size: 13))
                                .foregroundColor(p.text.opacity(0.35)).allowsHitTesting(false)
                        }
                    }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.55)))
            .padding(.horizontal, 18)
            .padding(.top, 38)
            .padding(.bottom, 8)

            if days.isEmpty {
                Spacer()
                Text(query.isEmpty ? "勾掉的事项会记在这里" : "没有找到「\(query)」")
                    .font(.system(size: 13))
                    .foregroundColor(p.text.opacity(0.45))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(days, id: \.0) { day, list in
                            dayHeader(day, list)
                            ForEach(list) { r in recordRow(r) }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
        .background(p.paper)
        .ignoresSafeArea()
    }

    private func dayTitle(_ d: Date) -> String {
        if cal.isDateInToday(d) { return "今天" }
        if cal.isDateInYesterday(d) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = cal.component(.year, from: d) == cal.component(.year, from: Date()) ? "M月d日 EEE" : "yyyy年M月d日 EEE"
        return f.string(from: d)
    }

    private func dayHeader(_ day: Date, _ list: [DoneRecord]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(dayTitle(day)).font(.system(size: 14, weight: .semibold)).foregroundColor(p.text)
            Text("\(list.count) 条").font(.system(size: 11).monospacedDigit()).foregroundColor(p.text.opacity(0.45))
            Spacer()
            Button(copied == day ? "已复制" : "复制") {
                let text = list.reversed().map { "- " + $0.text }.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = day
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copied == day { copied = nil } }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(p.ink)
            .help("把这一天做完的事复制成文字，按完成先后排")
        }
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private func recordRow(_ r: DoneRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(timeText(r.doneAt))
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(p.text.opacity(0.4))
                .frame(width: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.text).font(.system(size: 13)).foregroundColor(p.text)
                    .textSelection(.enabled)
                if !r.note.isEmpty {
                    Text(r.note).font(.system(size: 11)).foregroundColor(p.text.opacity(0.42))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .contextMenu {
            Button("从记录里删掉") { store.removeHistory(r.id) }
        }
    }

    private func timeText(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

final class HistoryWindow {
    static let shared = HistoryWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "已完成记录"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.backgroundColor = NSColor(Palette.named("stone").paper)
            w.appearance = NSAppearance(named: .aqua)
            let host = NSHostingView(rootView: HistoryView(store: Store.shared))
            host.sizingOptions = []
            w.contentView = host
            w.center()
            w.setFrameAutosaveName("HistoryWindow")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// 删掉整张便笺后，在原位置下方浮出几秒「撤回」
final class ToastPanel {
    static let shared = ToastPanel()
    private var panel: NSPanel?
    private var token = UUID()

    func show(_ text: String, near frame: CGRect, action: @escaping () -> Void) {
        panel?.orderOut(nil)
        let t = UUID(); token = t
        let view = ToastView(text: text) { [weak self] in
            action()
            self?.hide()
        }
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.contentView = host
        p.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: max(frame.maxY - 80, 40)))
        p.orderFrontRegardless()
        panel = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.token == t { self?.hide() }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct ToastView: View {
    let text: String
    let undo: () -> Void
    private let ink = Palette.named("stone").text

    var body: some View {
        HStack(spacing: 14) {
            Text(text).font(.system(size: 12.5)).lineLimit(1)
            Button("撤回", action: undo)
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(ink.opacity(0.92)))
        .padding(2)
        .fixedSize()
    }
}

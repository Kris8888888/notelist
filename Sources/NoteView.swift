import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Field: Hashable {
    case title
    case item(UUID)
    case new
}

/// 刚删掉的几条，等着撤回
struct UndoBatch {
    let id = UUID()
    let label: String
    let entries: [(Int, TodoItem)]
}

struct NoteView: View {
    @ObservedObject var note: Note
    var onDelete: () -> Void
    var onToggleCollapse: () -> Void

    @FocusState private var focus: Field?
    @State private var draft = ""
    @State private var hoverHeader = false
    @State private var showPalette = false
    @State private var undo: UndoBatch?
    @State private var dragging: UUID?

    private var p: Palette { Palette.named(note.color) }
    private var active: [TodoItem] { note.items.filter { !$0.done } }
    private var finished: [TodoItem] {
        note.items.filter { $0.done }.sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }
    private var progress: CGFloat {
        let total = note.items.count
        return total == 0 ? 0 : CGFloat(finished.count) / CGFloat(total)
    }

    var body: some View {
        VStack(spacing: 0) {
            progressStrip
            header
            if !note.collapsed {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        let list = active
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, item in
                            row(item, indented: item.indent > 0 && i > 0)
                        }
                        newRow
                        if !finished.isEmpty { doneSection }
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 10)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(p.paper.opacity(note.opacity))
        .overlay(alignment: .bottom) { undoToast }
        .ignoresSafeArea()
        .onChange(of: focus) { old, _ in leave(old) }
        .onAppear {
            if note.items.isEmpty && note.title.isEmpty {
                DispatchQueue.main.async { focus = .title }
            }
        }
    }

    // 顶部完成度细条：勾掉一条就往前走一截
    private var progressStrip: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(p.ink.opacity(0.14))
                Rectangle().fill(p.ink).frame(width: g.size.width * progress)
            }
        }
        .frame(height: 3)
        .animation(.easeOut(duration: 0.35), value: progress)
    }

    private var header: some View {
        HStack(spacing: 6) {
            TextField("", text: $note.title)
                .textFieldStyle(.plain)
                .focusEffectDisabled()
                .background(alignment: .leading) {
                    if note.title.isEmpty {
                        Text("清单").font(.system(size: 15, weight: .semibold))
                            .foregroundColor(p.text.opacity(0.3)).allowsHitTesting(false)
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(p.text)
                .focused($focus, equals: .title)
                .onSubmit { focus = .new }

            if hoverHeader || showPalette {
                HStack(spacing: 0) {
                    Button { showPalette.toggle() } label: {
                        Circle().fill(p.ink).frame(width: 10, height: 10)
                            .frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("换颜色")
                    .popover(isPresented: $showPalette, arrowEdge: .bottom) { palettePicker }

                    iconButton(note.pinned ? "pin.fill" : "pin", help: note.pinned ? "取消置顶" : "置顶") {
                        note.pinned.toggle()
                    }
                    iconButton(note.collapsed ? "chevron.down" : "chevron.up", help: note.collapsed ? "展开" : "收起成一行") {
                        onToggleCollapse()
                    }
                    iconButton("xmark", help: "删除这张便笺") { onDelete() }
                }
                .fixedSize()
                .transition(.opacity)
            } else if !note.items.isEmpty {
                Text("\(finished.count)/\(note.items.count)")
                    .font(.system(size: 11).monospacedDigit())
                    .fixedSize()
                    .foregroundColor(p.text.opacity(0.42))
                if note.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundColor(p.ink)
                }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 38)
        .background(WindowDragArea(onDoubleClick: onToggleCollapse))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hoverHeader = h } }
    }

    private var palettePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            colorDots
            Toggle("磨砂玻璃", isOn: $note.glass)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 12))
            HStack(spacing: 8) {
                Text("不透明度").font(.system(size: 12))
                Slider(value: $note.opacity, in: 0.15...1)
                    .controlSize(.small)
                Text("\(Int((note.opacity * 100).rounded()))%")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
        }
        .padding(12)
        .frame(width: 230)
    }

    private var colorDots: some View {
        HStack(spacing: 10) {
            ForEach(Palette.all) { c in
                Button {
                    note.color = c.key
                } label: {
                    ZStack {
                        Circle().fill(c.paper)
                        Circle().strokeBorder(c.ink, lineWidth: c.key == note.color ? 2.5 : 1)
                    }
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(c.name)
            }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(p.text.opacity(0.55))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func row(_ item: TodoItem, indented: Bool) -> some View {
        ItemRow(item: binding(item.id), palette: p, focus: $focus, indented: indented,
                onCheck: { toggle(item.id) },
                onSubmit: { insertAfter(item.id) },
                onBackspaceEmpty: { deleteBackward(item.id) },
                onMove: { move(item.id, by: $0) },
                onIndent: { setIndent(item.id, $0) },
                onStar: { toggleStar(item.id) },
                onCommit: { parseDue(item.id) },
                onRemove: { remove([item.id], label: "已删除 1 条") },
                onDragStart: { dragging = item.id })
            .onDrop(of: [.plainText], delegate: RowDrop(target: item.id, dragging: $dragging) { from, to in
                moveBlock(from, onto: to)
            })
    }

    private var newRow: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(p.ink.opacity(0.75))
                .frame(width: 15, height: 15)
                .padding(.top, 2)
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .focusEffectDisabled()
                .background(alignment: .leading) {
                    if draft.isEmpty {
                        Text("添加事项").font(.system(size: 13.5))
                            .foregroundColor(p.text.opacity(0.32)).allowsHitTesting(false)
                    }
                }
                .font(.system(size: 13.5))
                .foregroundColor(p.text)
                .focused($focus, equals: .new)
                .onSubmit { commitDraft(); focus = .new }
                .onKeyPress(.delete) {
                    guard draft.isEmpty, let last = active.last else { return .ignored }
                    focus = .item(last.id)
                    return .handled
                }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { focus = .new }
        .onDrop(of: [.plainText], delegate: RowDrop(target: nil, dragging: $dragging) { from, _ in
            moveBlock(from, onto: nil)
        })
    }

    private var doneSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { note.showDone.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(note.showDone ? 90 : 0))
                        Text("已完成 \(finished.count)")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(p.text.opacity(0.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                if note.showDone {
                    Button("清空") {
                        let ids = finished.map(\.id)
                        remove(ids, label: "已清空 \(ids.count) 条")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(p.text.opacity(0.4))
                    .help("删掉所有已完成的事项，已完成记录里还留着")
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 4)

            if note.showDone {
                ForEach(finished) { item in row(item, indented: false) }
            }
        }
    }

    @ViewBuilder private var undoToast: some View {
        if let u = undo {
            HStack(spacing: 12) {
                Text(u.label).font(.system(size: 12))
                Button("撤回") { restore(u) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(p.dark ? p.text : p.paper)
            }
            .foregroundColor((p.dark ? p.text : p.paper).opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(p.dark ? Color.white.opacity(0.14) : p.text.opacity(0.88)))
            .padding(.bottom, 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - 操作

    private func index(_ id: UUID) -> Int? { note.items.firstIndex { $0.id == id } }

    private func binding(_ id: UUID) -> Binding<TodoItem> {
        Binding(
            get: { note.items.first { $0.id == id } ?? TodoItem(text: "") },
            set: { v in if let i = index(id) { note.items[i] = v } }
        )
    }

    /// 主事项连同它下面的子事项
    private func blockRange(_ i: Int) -> Range<Int> {
        var end = i + 1
        if note.items[i].indent == 0 {
            while end < note.items.count && note.items[end].indent > 0 { end += 1 }
        }
        return i..<end
    }

    private func toggle(_ id: UUID) {
        guard let i = index(id) else { return }
        let nowDone = !note.items[i].done
        // 勾掉主事项时，下面没做完的子事项一起勾掉
        let range = nowDone ? blockRange(i) : i..<(i + 1)
        withAnimation(.easeOut(duration: 0.28)) {
            for j in range where note.items[j].done != nowDone || j == i {
                note.items[j].done = nowDone
                note.items[j].doneAt = nowDone ? Date() : nil
            }
        }
        for j in range {
            let it = note.items[j]
            if nowDone { Store.shared.recordDone(it, in: note) } else { Store.shared.unrecordDone(it.id) }
        }
    }

    private func toggleStar(_ id: UUID) {
        guard let i = index(id) else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            note.items[i].starred.toggle()
            // 标成重要的主事项挪到最上面
            if note.items[i].starred && note.items[i].indent == 0 {
                let r = blockRange(i)
                let block = Array(note.items[r])
                note.items.removeSubrange(r)
                note.items.insert(contentsOf: block, at: 0)
            }
        }
    }

    private func setIndent(_ id: UUID, _ level: Int) {
        guard let i = index(id) else { return }
        if level > 0 && active.first?.id == id { return }
        note.items[i].indent = level
    }

    private func parseDue(_ id: UUID) {
        guard let i = index(id), !note.items[i].done,
              let r = DueParser.parse(note.items[i].text) else { return }
        note.items[i].text = r.text
        note.items[i].due = r.due
        note.items[i].dueHasTime = r.hasTime
    }

    private func insertAfter(_ id: UUID) {
        parseDue(id)
        guard let i = index(id) else { return }
        if note.items[i].text.trimmingCharacters(in: .whitespaces).isEmpty || note.items[i].done {
            if note.items[i].indent > 0 { note.items[i].indent = 0; return }
            focus = .new
            return
        }
        var n = TodoItem(text: "")
        n.indent = note.items[i].indent
        // 主事项下面已经有子事项时，新的一条当它的第一个子事项
        if n.indent == 0 && i + 1 < note.items.count && note.items[i + 1].indent > 0 { n.indent = 1 }
        let at = i + 1
        note.items.insert(n, at: at)
        DispatchQueue.main.async { focus = .item(n.id) }
    }

    private func deleteBackward(_ id: UUID) {
        guard let i = index(id) else { return }
        if note.items[i].indent > 0 { note.items[i].indent = 0; return }
        let list = active
        guard let pos = list.firstIndex(where: { $0.id == id }) else { return }
        let prev: Field = pos > 0 ? .item(list[pos - 1].id) : .title
        note.items.removeAll { $0.id == id }
        DispatchQueue.main.async { focus = prev }
    }

    private func move(_ id: UUID, by delta: Int) {
        let list = active
        guard let pos = list.firstIndex(where: { $0.id == id }) else { return }
        let target = pos + delta
        guard target >= 0, target < list.count,
              let a = index(id), let b = index(list[target].id) else { return }
        withAnimation(.easeOut(duration: 0.15)) { note.items.swapAt(a, b) }
    }

    /// 拖到某一条上：放到它前面（往下拖时放到它后面）；拖到「添加事项」上：放到最后
    private func moveBlock(_ dragId: UUID, onto targetId: UUID?) {
        guard dragId != targetId, let from = index(dragId) else { return }
        let r = blockRange(from)
        let block = Array(note.items[r])
        if let t = targetId, block.contains(where: { $0.id == t }) { return }
        var items = note.items
        items.removeSubrange(r)
        var at = items.count
        if let t = targetId, let ti = items.firstIndex(where: { $0.id == t }), let origT = index(t) {
            var tIdx = ti
            // 拖主事项时不插进别人的子事项中间
            if block[0].indent == 0 { while tIdx > 0 && items[tIdx].indent > 0 { tIdx -= 1 } }
            at = tIdx
            if origT > from {
                at = tIdx + 1
                if items[tIdx].indent == 0 || block[0].indent == 0 {
                    while at < items.count && items[at].indent > 0 { at += 1 }
                }
            }
        }
        items.insert(contentsOf: block, at: min(at, items.count))
        if items[0].indent > 0 { items[0].indent = 0 }
        withAnimation(.easeOut(duration: 0.18)) { note.items = items }
    }

    private func remove(_ ids: [UUID], label: String) {
        let set = Set(ids)
        let entries = note.items.enumerated().filter { set.contains($0.element.id) }.map { ($0.offset, $0.element) }
        guard !entries.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            note.items.removeAll { set.contains($0.id) }
            undo = UndoBatch(label: label, entries: entries)
        }
        let id = undo!.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            if undo?.id == id { withAnimation(.easeOut(duration: 0.2)) { undo = nil } }
        }
    }

    private func restore(_ u: UndoBatch) {
        withAnimation(.easeOut(duration: 0.2)) {
            for (i, it) in u.entries.sorted(by: { $0.0 < $1.0 }) where index(it.id) == nil {
                note.items.insert(it, at: min(i, note.items.count))
            }
            undo = nil
        }
    }

    private func commitDraft() {
        let lines = draft.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        draft = ""
        guard !lines.isEmpty else { return }
        let items: [TodoItem] = lines.map { line in
            var it = TodoItem(text: line)
            if let r = DueParser.parse(line) {
                it.text = r.text; it.due = r.due; it.dueHasTime = r.hasTime
            }
            return it
        }
        withAnimation(.easeOut(duration: 0.18)) { note.items.append(contentsOf: items) }
    }

    // 离开某一行时：空行自动删掉、认一下日期；输入框里没回车的内容也收进清单
    private func leave(_ old: Field?) {
        switch old {
        case .item(let id):
            if let i = index(id), !note.items[i].done,
               note.items[i].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                note.items.remove(at: i)
            } else {
                parseDue(id)
            }
        case .new:
            commitDraft()
        default:
            break
        }
    }
}

struct RowDrop: DropDelegate {
    let target: UUID?
    @Binding var dragging: UUID?
    let move: (UUID, UUID?) -> Void

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }
    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != target, target != nil else { return }
        move(d, target)
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        if let d = dragging, target == nil { move(d, nil) }
        dragging = nil
        return true
    }
}

struct ItemRow: View {
    @Binding var item: TodoItem
    let palette: Palette
    var focus: FocusState<Field?>.Binding
    var indented: Bool
    var onCheck: () -> Void
    var onSubmit: () -> Void
    var onBackspaceEmpty: () -> Void
    var onMove: (Int) -> Void
    var onIndent: (Int) -> Void
    var onStar: () -> Void
    var onCommit: () -> Void
    var onRemove: () -> Void
    var onDragStart: () -> Void

    @State private var hover = false
    @State private var editingDue = false

    private var p: Palette { palette }
    private static let alert = Color(hex: 0xC2453A)
    private static let alertOnDark = Color(hex: 0xF08A7E)

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            checkbox
            VStack(alignment: .leading, spacing: 2) {
                textField
                if let due = item.due, !item.done || hover {
                    dueChip(due)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, 5)
        .padding(.leading, indented ? 24 : 0)
        .overlay(alignment: .topLeading) { handle }
        .onHover { hover = $0 }
    }

    // 左侧拖动把手，鼠标移上来才出现
    @ViewBuilder private var handle: some View {
        if !item.done {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(p.text.opacity(0.35))
                .frame(width: 12, height: 20)
                .contentShape(Rectangle())
                .opacity(hover ? 1 : 0)
                .offset(x: indented ? 11 : -13, y: 3)
                .onDrag {
                    onDragStart()
                    return NSItemProvider(object: item.id.uuidString as NSString)
                }
                .help("拖动调整顺序")
        }
    }

    private var checkbox: some View {
        Button(action: onCheck) {
            ZStack {
                Circle().strokeBorder(p.ink.opacity(item.done ? 0 : 0.75), lineWidth: 1.3)
                Circle().fill(p.ink).scaleEffect(item.done ? 1 : 0.001)
                Image(systemName: "checkmark")
                    .font(.system(size: 7.5, weight: .heavy))
                    .foregroundColor(p.paper)
                    .opacity(item.done ? 1 : 0)
            }
            .frame(width: indented ? 13 : 15, height: indented ? 13 : 15)
            .frame(width: 15, height: 15)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .help(item.done ? "标为未完成" : "完成")
    }

    @ViewBuilder private var textField: some View {
        if item.done {
            Text(item.text)
                .font(.system(size: 13.5))
                .lineSpacing(2)
                .foregroundColor(p.text.opacity(0.38))
                .strikethrough(true, color: p.text.opacity(0.32))
                .padding(.top, 0.5)
        } else {
            TextField("", text: $item.text, axis: .vertical)
                .textFieldStyle(.plain)
                .focusEffectDisabled()
                .font(.system(size: 13.5, weight: item.starred ? .semibold : .regular))
                .lineSpacing(2)
                .foregroundColor(p.text)
                .focused(focus, equals: .item(item.id))
                .onSubmit(onSubmit)
                .onKeyPress(.delete) {
                    guard item.text.isEmpty else { return .ignored }
                    onBackspaceEmpty()
                    return .handled
                }
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    guard press.modifiers.contains(.option) else { return .ignored }
                    onMove(press.key == .upArrow ? -1 : 1)
                    return .handled
                }
                .onKeyPress(keys: [.tab]) { press in
                    onIndent(press.modifiers.contains(.shift) ? 0 : 1)
                    return .handled
                }
                .onKeyPress(characters: CharacterSet(charactersIn: "\u{19}")) { _ in
                    onIndent(0)
                    return .handled
                }
        }
    }

    private func dueChip(_ due: Date) -> some View {
        let overdue = !item.done && DueParser.isOverdue(due, hasTime: item.dueHasTime)
        let today = DueParser.isToday(due)
        let color: Color = overdue ? (p.dark ? Self.alertOnDark : Self.alert) : (today ? p.ink : p.text.opacity(0.5))
        return Button { editingDue = true } label: {
            HStack(spacing: 3) {
                Image(systemName: item.dueHasTime ? "bell" : "calendar")
                    .font(.system(size: 9, weight: .medium))
                Text(DueParser.label(due, hasTime: item.dueHasTime))
                    .font(.system(size: 11, weight: overdue || today ? .medium : .regular).monospacedDigit())
            }
            .foregroundColor(item.done ? p.text.opacity(0.3) : color)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("改截止时间")
        .popover(isPresented: $editingDue, arrowEdge: .bottom) {
            DueEditor(item: $item, palette: p) { editingDue = false }
        }
    }

    private var trailing: some View {
        HStack(spacing: 0) {
            if !item.done && (hover || item.starred) {
                Button(action: onStar) {
                    Image(systemName: item.starred ? "star.fill" : "star")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(item.starred ? p.ink : p.text.opacity(0.4))
                        .frame(width: 18, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.starred ? "取消重要" : "标为重要，排到最上面")
            }
            if hover && !item.done && item.due == nil {
                Button { editingDue = true } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(p.text.opacity(0.4))
                        .frame(width: 18, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("设截止时间")
                .popover(isPresented: Binding(get: { editingDue && item.due == nil }, set: { editingDue = $0 }),
                         arrowEdge: .bottom) {
                    DueEditor(item: $item, palette: p) { editingDue = false }
                }
            }
            if hover {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(p.text.opacity(0.4))
                        .frame(width: 18, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("删除这一条")
            }
        }
        .padding(.top, 1)
    }
}

struct DueEditor: View {
    @Binding var item: TodoItem
    let palette: Palette
    var close: () -> Void

    @State private var date = Date()
    @State private var withTime = false

    private let cal = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                quick("今天", 0)
                quick("明天", 1)
                quick("后天", 2)
                quick("下周一", nextMonday())
            }
            DatePicker("", selection: $date, displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                Toggle("到点提醒", isOn: $withTime).toggleStyle(.checkbox)
                if withTime {
                    DatePicker("", selection: $date, displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.field)
                }
                Spacer()
            }
            .font(.system(size: 12))
            HStack {
                if item.due != nil {
                    Button("清除") {
                        item.due = nil
                        item.dueHasTime = false
                        close()
                    }
                }
                Spacer()
                Button("确定") { apply(); close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 250)
        .onAppear {
            if let d = item.due {
                date = d
                withTime = item.dueHasTime
            } else {
                date = cal.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
            }
        }
    }

    private func nextMonday() -> Int {
        let w = cal.component(.weekday, from: Date()) // 周日=1
        return w == 2 ? 7 : (9 - w) % 7
    }

    private func quick(_ title: String, _ days: Int) -> some View {
        Button(title) {
            let base = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: Date()))!
            let h = withTime ? cal.component(.hour, from: date) : 0
            let m = withTime ? cal.component(.minute, from: date) : 0
            date = cal.date(bySettingHour: h, minute: m, second: 0, of: base)!
            apply()
            close()
        }
        .controlSize(.small)
    }

    private func apply() {
        item.due = withTime ? date : cal.startOfDay(for: date)
        item.dueHasTime = withTime
    }
}

/// 顶部空白处：拖动移窗口，双击收起/展开
struct WindowDragArea: NSViewRepresentable {
    var onDoubleClick: () -> Void

    final class DragView: NSView {
        var onDoubleClick: (() -> Void)?
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { onDoubleClick?(); return }
            window?.performDrag(with: event)
        }
        override var mouseDownCanMoveWindow: Bool { true }
    }

    func makeNSView(context: Context) -> DragView {
        let v = DragView()
        v.onDoubleClick = onDoubleClick
        return v
    }

    func updateNSView(_ v: DragView, context: Context) { v.onDoubleClick = onDoubleClick }
}

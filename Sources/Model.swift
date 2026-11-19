import AppKit
import Combine
import SwiftUI

struct TodoItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var done = false
    var doneAt: Date? = nil
    var due: Date? = nil
    var dueHasTime = false
    var starred = false
    var indent = 0

    init(text: String, done: Bool = false, doneAt: Date? = nil) {
        self.text = text
        self.done = done
        self.doneAt = doneAt
    }

    enum CodingKeys: CodingKey { case id, text, done, doneAt, due, dueHasTime, starred, indent }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        doneAt = try c.decodeIfPresent(Date.self, forKey: .doneAt)
        due = try c.decodeIfPresent(Date.self, forKey: .due)
        dueHasTime = try c.decodeIfPresent(Bool.self, forKey: .dueHasTime) ?? false
        starred = try c.decodeIfPresent(Bool.self, forKey: .starred) ?? false
        indent = try c.decodeIfPresent(Int.self, forKey: .indent) ?? 0
    }
}

/// 勾掉一条就记一笔，清空、删除便笺都不影响这里
struct DoneRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var text: String
    var note: String
    var doneAt: Date
}

final class Note: ObservableObject, Identifiable, Codable {
    let id: UUID
    @Published var title: String
    @Published var items: [TodoItem]
    @Published var color: String
    @Published var pinned: Bool
    @Published var collapsed: Bool
    @Published var showDone: Bool
    @Published var glass: Bool
    @Published var opacity: Double
    var frame: CGRect
    var expandedHeight: CGFloat

    init(title: String = "", items: [TodoItem] = [], color: String = Palette.all[0].key, frame: CGRect) {
        id = UUID()
        self.title = title
        self.items = items
        self.color = color
        pinned = false
        collapsed = false
        showDone = false
        glass = false
        opacity = 1
        self.frame = frame
        expandedHeight = frame.height
    }

    var isEmpty: Bool { title.trimmingCharacters(in: .whitespaces).isEmpty && items.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty } }

    enum CodingKeys: CodingKey { case id, title, items, color, pinned, collapsed, showDone, glass, opacity, frame, expandedHeight }

    required init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        items = try c.decodeIfPresent([TodoItem].self, forKey: .items) ?? []
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? Palette.all[0].key
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        showDone = try c.decodeIfPresent(Bool.self, forKey: .showDone) ?? false
        glass = try c.decodeIfPresent(Bool.self, forKey: .glass) ?? false
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        frame = try c.decodeIfPresent(CGRect.self, forKey: .frame) ?? CGRect(x: 200, y: 400, width: 270, height: 320)
        expandedHeight = try c.decodeIfPresent(CGFloat.self, forKey: .expandedHeight) ?? frame.height
    }

    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(items, forKey: .items)
        try c.encode(color, forKey: .color)
        try c.encode(pinned, forKey: .pinned)
        try c.encode(collapsed, forKey: .collapsed)
        try c.encode(showDone, forKey: .showDone)
        try c.encode(glass, forKey: .glass)
        try c.encode(opacity, forKey: .opacity)
        try c.encode(frame, forKey: .frame)
        try c.encode(expandedHeight, forKey: .expandedHeight)
    }
}

final class Store: ObservableObject {
    static let shared = Store()
    private(set) var notes: [Note] = []
    @Published private(set) var history: [DoneRecord] = []
    @Published private(set) var trash: [Note] = []
    var onSaved: (() -> Void)?
    private var watchers: [UUID: AnyCancellable] = [:]
    let dir: URL
    var file: URL { dir.appendingPathComponent("notes.json") }

    private init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("便笺清单", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        // 每次启动留一份上次的备份，防止写坏
        try? data.write(to: dir.appendingPathComponent("notes.backup.json"), options: .atomic)
        if let list = try? JSONDecoder().decode([Note].self, from: data) {
            notes = list
            list.forEach(watch)
        }
        if let d = try? Data(contentsOf: url("history")), let h = try? JSONDecoder().decode([DoneRecord].self, from: d) {
            history = h
        }
        if let d = try? Data(contentsOf: url("trash")), let t = try? JSONDecoder().decode([Note].self, from: d) {
            trash = t
        }
        // 以前勾掉、还没进历史的也补进去
        let known = Set(history.map(\.id))
        for n in notes {
            for it in n.items where it.done && !known.contains(it.id) {
                history.append(DoneRecord(id: it.id, text: it.text, note: n.title, doneAt: it.doneAt ?? Date()))
            }
        }
        saveHistory()
    }

    private func url(_ name: String) -> URL { dir.appendingPathComponent("\(name).json") }

    private func write<T: Encodable>(_ v: T, _ name: String) {
        if let data = try? JSONEncoder().encode(v) { try? data.write(to: url(name), options: .atomic) }
    }

    func recordDone(_ item: TodoItem, in note: Note) {
        history.removeAll { $0.id == item.id }
        history.append(DoneRecord(id: item.id, text: item.text, note: note.title, doneAt: item.doneAt ?? Date()))
        saveHistory()
    }

    func unrecordDone(_ id: UUID) {
        history.removeAll { $0.id == id }
        saveHistory()
    }

    func removeHistory(_ id: UUID) { unrecordDone(id) }

    private func saveHistory() { write(history, "history") }

    func moveToTrash(_ n: Note) {
        trash.removeAll { $0.id == n.id }
        trash.insert(n, at: 0)
        if trash.count > 20 { trash.removeLast(trash.count - 20) }
        write(trash, "trash")
    }

    func takeFromTrash(_ id: UUID) -> Note? {
        guard let i = trash.firstIndex(where: { $0.id == id }) else { return nil }
        let n = trash.remove(at: i)
        write(trash, "trash")
        return n
    }

    func add(_ n: Note) {
        notes.append(n)
        watch(n)
        save()
    }

    func remove(_ n: Note) {
        notes.removeAll { $0.id == n.id }
        watchers[n.id] = nil
        save()
    }

    private func watch(_ n: Note) {
        watchers[n.id] = n.objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] in self?.save() }
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(notes) { try? data.write(to: file, options: .atomic) }
        onSaved?()
    }
}

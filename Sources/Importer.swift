import AppKit

enum StickiesImporter {
    struct Imported {
        let title: String
        let items: [TodoItem]
    }

    enum Result {
        case notFound
        case denied
        case notes([Imported])
    }

    static func run() -> Result {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.Stickies/Data/Library/Stickies")
        guard FileManager.default.fileExists(atPath: dir.path) else { return .notFound }
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return .denied
        }
        let docs = files.filter { $0.pathExtension == "rtfd" || $0.pathExtension == "rtf" }
        if docs.isEmpty { return .notFound }

        var out: [Imported] = []
        for url in docs {
            guard let s = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) else { continue }
            var lines = s.string.components(separatedBy: .newlines)
                .map(clean)
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }
            let title = lines.count > 1 ? lines.removeFirst() : ""
            out.append(Imported(title: title, items: lines.map { TodoItem(text: $0) }))
        }
        return .notes(out)
    }

    // 去掉行首的项目符号、勾选框
    private static func clean(_ line: String) -> String {
        var t = line.trimmingCharacters(in: .whitespaces)
        let marks = ["- [ ] ", "- [x] ", "☐", "☑", "□", "■", "•", "·", "-", "*", "—", "\u{FFFC}"]
        var changed = true
        while changed {
            changed = false
            for m in marks where t.hasPrefix(m) {
                t = String(t.dropFirst(m.count)).trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        return t
    }
}

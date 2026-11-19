import Foundation
import UserNotifications

/// 从事项文字里认出「明天」「周五 3点」「11月20日」这类说法，拆成截止时间
enum DueParser {
    struct Result {
        var text: String
        var due: Date
        var hasTime: Bool
    }

    private static let cal = Calendar.current
    private static let cnNum: [Character: Int] = ["零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10]
    private static let weekday: [Character: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7]

    static func number(_ s: String) -> Int? {
        if let n = Int(s) { return n }
        let cs = Array(s)
        if cs.count == 1 { return cnNum[cs[0]] }
        if cs.count == 2, cs[0] == "十" { return 10 + (cnNum[cs[1]] ?? 0) }
        if cs.count == 2, cs[1] == "十" { return (cnNum[cs[0]] ?? 0) * 10 }
        if cs.count == 3, cs[1] == "十" { return (cnNum[cs[0]] ?? 0) * 10 + (cnNum[cs[2]] ?? 0) }
        return nil
    }

    private static func match(_ pattern: String, in s: String) -> (NSRange, [String?])? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        let groups = (0..<m.numberOfRanges).map { i -> String? in
            let r = m.range(at: i)
            guard r.location != NSNotFound, let rr = Range(r, in: s) else { return nil }
            return String(s[rr])
        }
        return (m.range, groups)
    }

    static func parse(_ raw: String, now: Date = Date()) -> Result? {
        var s = raw
        let today = cal.startOfDay(for: now)
        var day: Date?
        var hour: Int?
        var minute = 0
        var period: String?

        // 日期部分
        if let (r, g) = match("(大后天|后天|明天|明日|今天|今日|今晚)", in: s) {
            switch g[1]! {
            case "今天", "今日": day = today
            case "今晚": day = today; period = "晚上"
            case "明天", "明日": day = cal.date(byAdding: .day, value: 1, to: today)
            case "后天": day = cal.date(byAdding: .day, value: 2, to: today)
            default: day = cal.date(byAdding: .day, value: 3, to: today)
            }
            s = cut(s, r)
        } else if let (r, g) = match("(下下|下|这|本)?(?:周|星期|礼拜)([一二三四五六日天])", in: s) {
            let target = weekday[Character(g[2]!)]!
            let cur = (cal.component(.weekday, from: today) + 5) % 7 + 1 // 周一=1 … 周日=7
            var delta = target - cur
            switch g[1] {
            case "下": delta += 7
            case "下下": delta += 14
            default: if delta < 0 { delta += 7 }
            }
            day = cal.date(byAdding: .day, value: delta, to: today)
            s = cut(s, r)
        } else if let (r, g) = match("(\\d{1,2})月(\\d{1,2})[日号]?", in: s),
                  let mo = Int(g[1]!), let d = Int(g[2]!), (1...12).contains(mo), (1...31).contains(d) {
            var c = cal.dateComponents([.year], from: today)
            c.month = mo; c.day = d
            if let dt = cal.date(from: c) {
                day = dt < cal.date(byAdding: .day, value: -60, to: today)! ? cal.date(byAdding: .year, value: 1, to: dt) : dt
            }
            s = cut(s, r)
        } else if let (r, g) = match("(?<![\\d月])(\\d{1,2})号", in: s), let d = Int(g[1]!), (1...31).contains(d) {
            var c = cal.dateComponents([.year, .month], from: today)
            c.day = d
            if let dt = cal.date(from: c) { day = dt < today ? cal.date(byAdding: .month, value: 1, to: dt) : dt }
            s = cut(s, r)
        }

        // 时间部分
        let numPat = "(\\d{1,2}|[一二两三四五六七八九十]{1,3})"
        if let (r, g) = match("(上午|早上|中午|下午|晚上)?\\s*(\\d{1,2})[:：](\\d{2})", in: s),
           let h = Int(g[2]!), let m = Int(g[3]!), h < 24, m < 60 {
            period = g[1] ?? period; hour = h; minute = m
            s = cut(s, r)
        } else if let (r, g) = match("(?<!第)(上午|早上|中午|下午|晚上)?\\s*" + numPat + "\\s*[点时](半|" + numPat + "分?)?", in: s),
                  let h = number(g[2]!), h < 24,
                  // 「快一点」「第3点」这类不是时间：没有上午下午、也没有日期时只认阿拉伯数字
                  g[1] != nil || period != nil || day != nil || Int(g[2]!) != nil {
            period = g[1] ?? period; hour = h
            if let tail = g[3] {
                if tail == "半" { minute = 30 } else if let m = g[4].flatMap(number), m < 60 { minute = m }
            }
            s = cut(s, r)
        }

        guard day != nil || hour != nil else { return nil }
        var hasTime = false
        if var h = hour {
            switch period {
            case "下午", "晚上": if h < 12 { h += 12 }
            case "中午": if h < 6 { h += 12 }
            case nil: if h >= 1 && h <= 7 { h += 12 } // 「3点开会」按下午算
            default: break
            }
            hour = h
            hasTime = true
        }
        let base = day ?? today
        let due = hasTime ? cal.date(bySettingHour: hour!, minute: minute, second: 0, of: base)! : base

        var clean = s.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        for suffix in ["之前", "以前", "前", "截止"] where clean.hasPrefix(suffix) {
            clean = String(clean.dropFirst(suffix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        if clean.isEmpty { clean = raw.trimmingCharacters(in: .whitespaces) }
        return Result(text: clean, due: due, hasTime: hasTime)
    }

    private static func cut(_ s: String, _ r: NSRange) -> String {
        guard let rr = Range(r, in: s) else { return s }
        var t = s
        t.replaceSubrange(rr, with: " ")
        return t
    }

    /// 便笺上显示的短标签：今天 15:00 / 明天 / 周五 / 11月20日
    static func label(_ due: Date, hasTime: Bool, now: Date = Date()) -> String {
        let today = cal.startOfDay(for: now)
        let d = cal.startOfDay(for: due)
        let diff = cal.dateComponents([.day], from: today, to: d).day ?? 0
        var dayText: String
        switch diff {
        case 0: dayText = "今天"
        case 1: dayText = "明天"
        case 2: dayText = "后天"
        case -1: dayText = "昨天"
        case 3...6:
            let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            dayText = names[cal.component(.weekday, from: d) - 1]
        default:
            let f = DateFormatter()
            f.dateFormat = cal.component(.year, from: d) == cal.component(.year, from: today) ? "M月d日" : "yyyy年M月d日"
            dayText = f.string(from: d)
        }
        if hasTime {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            dayText += " " + f.string(from: due)
        }
        return dayText
    }

    static func isOverdue(_ due: Date, hasTime: Bool, now: Date = Date()) -> Bool {
        hasTime ? due < now : cal.startOfDay(for: due) < cal.startOfDay(for: now)
    }

    static func isToday(_ due: Date) -> Bool { cal.isDateInToday(due) }
}

/// 到点用系统通知提醒；只给有截止时间、还没完成的事项排
final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Reminders()
    private var enabled: Bool { Bundle.main.bundleIdentifier != nil }

    func setup() {
        guard enabled else { return }
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func reschedule(_ notes: [Note]) {
        guard enabled else { return }
        let c = UNUserNotificationCenter.current()
        c.removeAllPendingNotificationRequests()
        let now = Date()
        let cal = Calendar.current
        for n in notes {
            for it in n.items where !it.done {
                guard let due = it.due else { continue }
                let fire = it.dueHasTime ? due : cal.date(bySettingHour: 9, minute: 0, second: 0, of: due)!
                guard fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = it.text
                content.body = (n.title.isEmpty ? "" : n.title + "：") + DueParser.label(due, hasTime: it.dueHasTime) + " 到期"
                content.sound = .default
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let req = UNNotificationRequest(identifier: it.id.uuidString, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
                c.add(req)
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

import SwiftUI

struct Palette: Identifiable {
    let key: String
    let name: String
    let paper: Color
    let ink: Color
    let text: Color
    let dark: Bool
    var id: String { key }

    static let all: [Palette] = [
        Palette(key: "apricot", name: "杏", paper: Color(hex: 0xF5E9C8), ink: Color(hex: 0xB4862A), text: Color(hex: 0x3B3222), dark: false),
        Palette(key: "mint", name: "薄荷", paper: Color(hex: 0xDCEBDF), ink: Color(hex: 0x4C8A63), text: Color(hex: 0x24352A), dark: false),
        Palette(key: "mist", name: "雾蓝", paper: Color(hex: 0xDDE6F1), ink: Color(hex: 0x4E74A6), text: Color(hex: 0x232D3B), dark: false),
        Palette(key: "lotus", name: "藕粉", paper: Color(hex: 0xF1DEDD), ink: Color(hex: 0xA9585A), text: Color(hex: 0x3A2827), dark: false),
        Palette(key: "stone", name: "石灰", paper: Color(hex: 0xE8E6E0), ink: Color(hex: 0x77736A), text: Color(hex: 0x2E2C28), dark: false),
        Palette(key: "ink", name: "墨", paper: Color(hex: 0x2B2E33), ink: Color(hex: 0xE0B862), text: Color(hex: 0xE9E6DF), dark: true),
    ]

    static func named(_ key: String) -> Palette { all.first { $0.key == key } ?? all[0] }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

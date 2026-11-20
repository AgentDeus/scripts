import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// Colour palette of the chat UI, modelled after the Android client's themes.
struct ChatTheme {
    var isDark: Bool
    var background: Color
    var surface: Color          // toolbars, drawers
    var surfaceVariant: Color   // headers in drawers
    var primary: Color          // app bar
    var onPrimary: Color
    var accent: Color
    var text: Color
    var secondaryText: Color
    var timestamp: Color
    var serverText: Color
    var errorText: Color
    var actionText: Color
    var noticeText: Color
    var highlightBackground: Color
    var selfBackground: Color
    var markerLine: Color
    var activityHighlight: Color
    var activityMessage: Color
    var activityOther: Color
    var inactive: Color
    var awayNick: Color
    var nickColors: [Color]
    var selfNick: Color

    static func make(_ choice: ThemeChoice, scheme: ColorScheme) -> ChatTheme {
        switch choice {
        case .system: return scheme == .dark ? quasselDark : quasselLight
        case .quasselLight: return quasselLight
        case .quasselDark: return quasselDark
        case .materialLight: return materialLight
        case .materialDark: return materialDark
        case .solarizedLight: return solarizedLight
        case .solarizedDark: return solarizedDark
        case .amoled: return amoled
        }
    }

    var colorScheme: ColorScheme { isDark ? .dark : .light }

    static let quasselNickLight: [Color] = [
        0xcc0000, 0x006cad, 0x4d9900, 0x6600cc, 0xa67d00, 0x009927, 0x0030c0, 0xcc009a,
        0xb94600, 0x869900, 0x149900, 0x009960, 0x006cad, 0x0099cc, 0xb300cc, 0xcc004d,
    ].map { Color(hex: $0) }

    static let quasselNickDark: [Color] = [
        0xff6666, 0x52b8ff, 0x99ff33, 0xb366ff, 0xffcc33, 0x33ff66, 0x6699ff, 0xff66d9,
        0xff9933, 0xd9ff33, 0x66ff33, 0x33ffb3, 0x52b8ff, 0x33d6ff, 0xe666ff, 0xff6699,
    ].map { Color(hex: $0) }

    static let quasselLight = ChatTheme(
        isDark: false,
        background: Color(hex: 0xFAFAFA), surface: Color(hex: 0xFFFFFF), surfaceVariant: Color(hex: 0xEEEEEE),
        primary: Color(hex: 0x0A70C0), onPrimary: .white, accent: Color(hex: 0xFFAF3B),
        text: Color(hex: 0x212121), secondaryText: Color(hex: 0x757575), timestamp: Color(hex: 0x9E9E9E),
        serverText: Color(hex: 0x616161), errorText: Color(hex: 0xC62828), actionText: Color(hex: 0x1565C0),
        noticeText: Color(hex: 0x6D4C41), highlightBackground: Color(hex: 0xFFAF3B, alpha: 0.25),
        selfBackground: Color(hex: 0x0A70C0, alpha: 0.05), markerLine: Color(hex: 0xC62828),
        activityHighlight: Color(hex: 0xFFAF3B), activityMessage: Color(hex: 0x0A70C0),
        activityOther: Color(hex: 0x2E7D32), inactive: Color(hex: 0xB0B0B0), awayNick: Color(hex: 0x9E9E9E),
        nickColors: quasselNickLight, selfNick: Color(hex: 0x212121))

    static let quasselDark = ChatTheme(
        isDark: true,
        background: Color(hex: 0x303030), surface: Color(hex: 0x262626), surfaceVariant: Color(hex: 0x3A3A3A),
        primary: Color(hex: 0x1A3C5A), onPrimary: .white, accent: Color(hex: 0xFFAF3B),
        text: Color(hex: 0xEEEEEE), secondaryText: Color(hex: 0xAAAAAA), timestamp: Color(hex: 0x8A8A8A),
        serverText: Color(hex: 0xBDBDBD), errorText: Color(hex: 0xEF5350), actionText: Color(hex: 0x64B5F6),
        noticeText: Color(hex: 0xBCAAA4), highlightBackground: Color(hex: 0xFFAF3B, alpha: 0.22),
        selfBackground: Color(hex: 0xFFFFFF, alpha: 0.04), markerLine: Color(hex: 0xEF5350),
        activityHighlight: Color(hex: 0xFFAF3B), activityMessage: Color(hex: 0x64B5F6),
        activityOther: Color(hex: 0x81C784), inactive: Color(hex: 0x6E6E6E), awayNick: Color(hex: 0x8A8A8A),
        nickColors: quasselNickDark, selfNick: Color(hex: 0xEEEEEE))

    static let materialLight: ChatTheme = {
        var t = quasselLight
        t.primary = Color(hex: 0x3F51B5)
        t.accent = Color(hex: 0xFF4081)
        t.activityMessage = Color(hex: 0x3F51B5)
        t.activityHighlight = Color(hex: 0xFF4081)
        t.highlightBackground = Color(hex: 0xFF4081, alpha: 0.18)
        t.background = .white
        return t
    }()

    static let materialDark: ChatTheme = {
        var t = quasselDark
        t.primary = Color(hex: 0x212121)
        t.background = Color(hex: 0x121212)
        t.surface = Color(hex: 0x1E1E1E)
        t.surfaceVariant = Color(hex: 0x2C2C2C)
        t.accent = Color(hex: 0xFF4081)
        t.activityHighlight = Color(hex: 0xFF4081)
        t.highlightBackground = Color(hex: 0xFF4081, alpha: 0.2)
        return t
    }()

    static let solarizedLight: ChatTheme = {
        var t = quasselLight
        t.background = Color(hex: 0xFDF6E3)
        t.surface = Color(hex: 0xEEE8D5)
        t.surfaceVariant = Color(hex: 0xE4DCC5)
        t.primary = Color(hex: 0x268BD2)
        t.text = Color(hex: 0x586E75)
        t.secondaryText = Color(hex: 0x93A1A1)
        t.timestamp = Color(hex: 0x93A1A1)
        t.accent = Color(hex: 0xCB4B16)
        t.activityHighlight = Color(hex: 0xCB4B16)
        t.highlightBackground = Color(hex: 0xB58900, alpha: 0.2)
        t.selfNick = Color(hex: 0x586E75)
        return t
    }()

    static let solarizedDark: ChatTheme = {
        var t = quasselDark
        t.background = Color(hex: 0x002B36)
        t.surface = Color(hex: 0x073642)
        t.surfaceVariant = Color(hex: 0x0B4351)
        t.primary = Color(hex: 0x073642)
        t.text = Color(hex: 0x93A1A1)
        t.secondaryText = Color(hex: 0x657B83)
        t.timestamp = Color(hex: 0x657B83)
        t.accent = Color(hex: 0xCB4B16)
        t.activityHighlight = Color(hex: 0xCB4B16)
        t.highlightBackground = Color(hex: 0xB58900, alpha: 0.2)
        t.selfNick = Color(hex: 0x93A1A1)
        return t
    }()

    static let amoled: ChatTheme = {
        var t = quasselDark
        t.background = .black
        t.surface = .black
        t.surfaceVariant = Color(hex: 0x111111)
        t.primary = .black
        return t
    }()

    func nickColor(_ nick: String, isSelf: Bool, mode: ColorizeNicks) -> Color {
        if mode == .none || (isSelf && mode == .allButMine) { return isSelf ? selfNick : text }
        return nickColors[Int(NickHash.senderHash(nick)) % nickColors.count]
    }
}

/// Nick colour hash identical to Quassel's (qChecksum / CRC-16 X.25 of the lower-cased nick).
enum NickHash {
    static func senderHash(_ nick: String) -> UInt16 {
        var n = nick.lowercased()
        while n.count > 1, n.hasSuffix("_") { n.removeLast() }
        let bytes = Array(n.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) })
        var crc: UInt16 = 0xFFFF
        for b in bytes {
            crc ^= UInt16(b)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0x8408 : crc >> 1
            }
        }
        return (~crc) & 0xF
    }
}

/// The 99 mIRC colours.
enum MircColors {
    static let palette: [UInt32] = [
        0xFFFFFF, 0x000000, 0x00007F, 0x009300, 0xFF0000, 0x7F0000, 0x9C009C, 0xFC7F00,
        0xFFFF00, 0x00FC00, 0x009393, 0x00FFFF, 0x0000FC, 0xFF00FF, 0x7F7F7F, 0xD2D2D2,
        0x470000, 0x472100, 0x474700, 0x324700, 0x004700, 0x00472C, 0x004747, 0x002747,
        0x000047, 0x2E0047, 0x470047, 0x47002A, 0x740000, 0x743A00, 0x747400, 0x517400,
        0x007400, 0x007449, 0x007474, 0x004074, 0x000074, 0x4B0074, 0x740074, 0x740045,
        0xB50000, 0xB56300, 0xB5B500, 0x7DB500, 0x00B500, 0x00B571, 0x00B5B5, 0x0063B5,
        0x0000B5, 0x7500B5, 0xB500B5, 0xB5006B, 0xFF0000, 0xFF8C00, 0xFFFF00, 0xB2FF00,
        0x00FF00, 0x00FFA0, 0x00FFFF, 0x008CFF, 0x0000FF, 0xA500FF, 0xFF00FF, 0xFF0098,
        0xFF5959, 0xFFB459, 0xFFFF71, 0xCFFF60, 0x6FFF6F, 0x65FFC9, 0x6DFFFF, 0x59B4FF,
        0x5959FF, 0xC459FF, 0xFF66FF, 0xFF59BC, 0xFF9C9C, 0xFFD39C, 0xFFFF9C, 0xE2FF9C,
        0x9CFF9C, 0x9CFFDB, 0x9CFFFF, 0x9CD3FF, 0x9C9CFF, 0xDC9CFF, 0xFF9CFF, 0xFF94D3,
        0x000000, 0x131313, 0x282828, 0x363636, 0x4D4D4D, 0x656565, 0x818181, 0x9F9F9F,
        0xBCBCBC, 0xE2E2E2, 0xFFFFFF,
    ]

    static func color(_ i: Int) -> Color? {
        guard i >= 0, i < palette.count else { return nil }
        return Color(hex: palette[i])
    }
}

private struct ChatThemeKey: EnvironmentKey {
    static let defaultValue = ChatTheme.quasselLight
}

extension EnvironmentValues {
    var chatTheme: ChatTheme {
        get { self[ChatThemeKey.self] }
        set { self[ChatThemeKey.self] = newValue }
    }
}

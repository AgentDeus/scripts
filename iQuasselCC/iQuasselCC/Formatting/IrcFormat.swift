import SwiftUI

/// mIRC formatting code parser.
enum IrcFormat {
    static let bold: Character = "\u{02}"
    static let color: Character = "\u{03}"
    static let hexColor: Character = "\u{04}"
    static let monospace: Character = "\u{11}"
    static let reverse: Character = "\u{16}"
    static let italic: Character = "\u{1D}"
    static let strike: Character = "\u{1E}"
    static let underline: Character = "\u{1F}"
    static let reset: Character = "\u{0F}"

    private struct Style: Equatable {
        var bold = false, italic = false, underline = false, strike = false, mono = false, reverse = false
        var fg: Color?
        var bg: Color?
    }

    /// Remove all formatting codes.
    static func strip(_ s: String) -> String {
        guard s.unicodeScalars.contains(where: { $0.value < 0x20 }) else { return s }
        var out = ""
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case bold, monospace, reverse, italic, strike, underline, reset:
                i += 1
            case color:
                i += 1
                i = skipColor(chars, i, hex: false)
            case hexColor:
                i += 1
                i = skipColor(chars, i, hex: true)
            default:
                out.append(c)
                i += 1
            }
        }
        return out
    }

    private static func skipColor(_ chars: [Character], _ start: Int, hex: Bool) -> Int {
        max(readColor(chars, start, hex: hex).2, start)
    }

    /// Returns (fg, bg, nextIndex)
    private static func readColor(_ chars: [Character], _ start: Int, hex: Bool) -> (Color?, Color??, Int) {
        var i = start
        func readNum(max: Int) -> String {
            var s = ""
            while i < chars.count, s.count < max, chars[i].isASCII,
                  hex ? chars[i].isHexDigit : chars[i].isNumber {
                s.append(chars[i]); i += 1
            }
            return s
        }
        let maxLen = hex ? 6 : 2
        let fgStr = readNum(max: maxLen)
        guard !fgStr.isEmpty else { return (nil, nil, i) }
        var bg: Color?? = nil
        if i + 1 < chars.count, chars[i] == ",",
           hex ? chars[i + 1].isHexDigit : chars[i + 1].isNumber {
            i += 1
            let bgStr = readNum(max: maxLen)
            bg = .some(parse(bgStr, hex: hex))
        }
        return (parse(fgStr, hex: hex), bg, i)
    }

    private static func parse(_ s: String, hex: Bool) -> Color? {
        if hex {
            guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
            return Color(hex: v)
        }
        guard let n = Int(s), n != 99 else { return nil }
        return MircColors.color(n)
    }

    /// Build an attributed string honouring IRC formatting codes and detecting links.
    static func attributed(_ s: String, showFormatting: Bool = true, baseColor: Color? = nil,
                           channelTypes: String = "#") -> AttributedString {
        var result = AttributedString()
        var style = Style()
        var run = ""
        let chars = Array(s)

        func flush() {
            guard !run.isEmpty else { return }
            var a = AttributedString(run)
            if showFormatting {
                var intent: InlinePresentationIntent = []
                if style.bold { intent.insert(.stronglyEmphasized) }
                if style.italic { intent.insert(.emphasized) }
                if style.mono { intent.insert(.code) }
                if !intent.isEmpty { a.inlinePresentationIntent = intent }
                if style.underline { a.underlineStyle = Text.LineStyle.single }
                if style.strike { a.strikethroughStyle = Text.LineStyle.single }
                var fg = style.fg, bg = style.bg
                if style.reverse { swap(&fg, &bg) }
                if let fg = fg { a.foregroundColor = fg } else if let b = baseColor { a.foregroundColor = b }
                if let bg = bg { a.backgroundColor = bg }
            } else if let b = baseColor {
                a.foregroundColor = b
            }
            result += a
            run = ""
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case bold: flush(); style.bold.toggle(); i += 1
            case italic: flush(); style.italic.toggle(); i += 1
            case underline: flush(); style.underline.toggle(); i += 1
            case strike: flush(); style.strike.toggle(); i += 1
            case monospace: flush(); style.mono.toggle(); i += 1
            case reverse: flush(); style.reverse.toggle(); i += 1
            case reset: flush(); style = Style(); i += 1
            case color, hexColor:
                flush()
                let (fg, bg, next) = readColor(chars, i + 1, hex: c == hexColor)
                if next == i + 1 {
                    style.fg = nil; style.bg = nil
                } else {
                    style.fg = fg
                    if let bg = bg { style.bg = bg }
                }
                i = next
            default:
                run.append(c)
                i += 1
            }
        }
        flush()
        linkify(&result, channelTypes: channelTypes)
        return result
    }

    private static var regexCache = [String: NSRegularExpression]()
    private static let regexLock = NSLock()

    private static func channelRegex(_ types: String) -> NSRegularExpression? {
        regexLock.lock(); defer { regexLock.unlock() }
        if let r = regexCache[types] { return r }
        let r = try? NSRegularExpression(pattern: "(?:^|(?<=[\\s(]))([\(NSRegularExpression.escapedPattern(for: types))][^\\s,\\x07]+[^\\s,.:;!?)\\x07])")
        regexCache[types] = r
        return r
    }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func linkify(_ a: inout AttributedString, channelTypes: String) {
        let plain = String(a.characters)
        guard !plain.isEmpty else { return }
        let ns = plain as NSString
        let mayHaveLink = plain.contains(".") || plain.contains(":")
        let matches = mayHaveLink ? (detector?.matches(in: plain, range: NSRange(location: 0, length: ns.length)) ?? []) : []
        var covered = [NSRange]()
        for m in matches {
            guard let url = m.url, let b = bounds(m.range, plain, a) else { continue }
            a[b.0..<b.1].link = url
            a[b.0..<b.1].underlineStyle = Text.LineStyle.single
            covered.append(m.range)
        }
        // Channel names become tappable "join" links.
        guard !channelTypes.isEmpty, plain.contains(where: { channelTypes.contains($0) }),
              let re = channelRegex(channelTypes) else { return }
        for m in re.matches(in: plain, range: NSRange(location: 0, length: ns.length)) {
            let range = m.range(at: 1)
            if covered.contains(where: { NSIntersectionRange($0, range).length > 0 }) { continue }
            let name = ns.substring(with: range)
            guard let b = bounds(range, plain, a),
                  var comps = URLComponents(string: "iquasselcc://join") else { continue }
            comps.queryItems = [URLQueryItem(name: "channel", value: name)]
            if let url = comps.url { a[b.0..<b.1].link = url }
        }
    }

    private static func bounds(_ range: NSRange, _ plain: String, _ a: AttributedString)
        -> (AttributedString.Index, AttributedString.Index)? {
        guard let r = Range(range, in: plain) else { return nil }
        let start = plain.distance(from: plain.startIndex, to: r.lowerBound)
        let len = plain.distance(from: r.lowerBound, to: r.upperBound)
        let lower = a.index(a.startIndex, offsetByCharacters: start)
        let upper = a.index(lower, offsetByCharacters: len)
        return (lower, upper)
    }
}

import SwiftUI

/// Converts Quassel messages into display text, following the Android client's wording.
struct MessageRenderer {
    let theme: ChatTheme
    let settings: AppSettings
    let network: Network?

    private func nickText(_ nick: String, prefixes: String = "", isSelf: Bool, brackets: Bool = false) -> AttributedString {
        var shownPrefix = ""
        switch settings.prefixMode {
        case .all: shownPrefix = prefixes
        case .highest: shownPrefix = prefixes.first.map { String($0) } ?? ""
        case .none: shownPrefix = ""
        }
        var s = AttributedString(brackets ? "<\(shownPrefix)\(nick)>" : "\(shownPrefix)\(nick)")
        s.foregroundColor = theme.nickColor(nick, isSelf: isSelf, mode: settings.colorizeNicks)
        s.inlinePresentationIntent = .stronglyEmphasized
        if let url = URL(string: "iquasselcc://nick?name=\(nick.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? nick)") {
            s.link = url
        }
        return s
    }

    private func plain(_ s: String, color: Color? = nil) -> AttributedString {
        var a = AttributedString(s)
        a.foregroundColor = color ?? theme.serverText
        return a
    }

    private func formatted(_ s: String, color: Color? = nil) -> AttributedString {
        IrcFormat.attributed(s, showFormatting: settings.showFormatting, baseColor: color,
                             channelTypes: network?.channelTypes ?? "#")
    }

    private func hostmaskSuffix(_ sender: String) -> AttributedString {
        guard settings.showHostmask else { return AttributedString() }
        let u = IrcMask.user(sender), h = IrcMask.host(sender)
        guard !u.isEmpty || !h.isEmpty else { return AttributedString() }
        return plain(" (\(u)@\(h))", color: theme.secondaryText)
    }

    /// Whether the message is rendered in the compact "nick: text" layout.
    static func isConversation(_ m: IrcMessage) -> Bool {
        m.type == .plain || m.type == .action || m.type == .notice
    }

    func render(_ m: IrcMessage) -> AttributedString {
        let nick = m.senderNick
        let isSelf = m.flags.contains(.selfMsg)
        let prefixes = m.senderPrefixes
        var out = AttributedString()

        if m.type.contains(.plain) {
            out += nickText(nick, prefixes: prefixes, isSelf: isSelf, brackets: settings.nicksInBrackets)
            if settings.showRealNames && !m.realName.isEmpty && m.realName != nick {
                out += plain(" (\(IrcFormat.strip(m.realName)))", color: theme.secondaryText)
            }
            out += AttributedString(settings.nicksInBrackets ? " " : ": ")
            out += formatted(m.content, color: theme.text)
        } else if m.type.contains(.action) {
            out += plain("* ", color: theme.actionText)
            out += nickText(nick, prefixes: prefixes, isSelf: isSelf)
            out += AttributedString(" ")
            out += formatted(m.content, color: theme.actionText)
        } else if m.type.contains(.notice) {
            out += plain("[", color: theme.noticeText)
            out += nickText(nick, isSelf: isSelf)
            out += plain("] ", color: theme.noticeText)
            out += formatted(m.content, color: theme.noticeText)
        } else if m.type.contains(.nick) {
            if nick == m.content {
                out += plain("You are now known as ")
                out += nickText(m.content, isSelf: true)
            } else {
                out += nickText(nick, isSelf: isSelf)
                out += plain(" is now known as ")
                out += nickText(m.content, isSelf: isSelf)
            }
        } else if m.type.contains(.mode) {
            out += plain("Mode ")
            out += formatted(m.content, color: theme.serverText)
            out += plain(" by ")
            out += nickText(nick, isSelf: isSelf)
        } else if m.type.contains(.join) {
            out += plain("→ ", color: theme.activityOther)
            out += nickText(nick, isSelf: isSelf)
            out += hostmaskSuffix(m.sender)
            out += plain(" has joined \(m.content)")
        } else if m.type.contains(.part) {
            out += plain("← ", color: theme.errorText)
            out += nickText(nick, isSelf: isSelf)
            out += hostmaskSuffix(m.sender)
            out += plain(" has left \(m.bufferInfo.name)")
            if !m.content.isEmpty {
                out += plain(" (")
                out += formatted(m.content, color: theme.serverText)
                out += plain(")")
            }
        } else if m.type.contains(.quit) {
            out += plain("← ", color: theme.errorText)
            out += nickText(nick, isSelf: isSelf)
            out += hostmaskSuffix(m.sender)
            out += plain(" has quit")
            if !m.content.isEmpty {
                out += plain(" (")
                out += formatted(m.content, color: theme.serverText)
                out += plain(")")
            }
        } else if m.type.contains(.kick) {
            let parts = m.content.split(separator: " ", maxSplits: 1).map(String.init)
            let victim = parts.first ?? ""
            out += plain("← ", color: theme.errorText)
            out += nickText(nick, isSelf: isSelf)
            out += plain(" has kicked ")
            out += nickText(victim, isSelf: false)
            out += plain(" from \(m.bufferInfo.name)")
            if parts.count > 1 {
                out += plain(" (")
                out += formatted(parts[1], color: theme.serverText)
                out += plain(")")
            }
        } else if m.type.contains(.kill) {
            out += plain("☠ ", color: theme.errorText)
            out += formatted(m.content, color: theme.serverText)
        } else if m.type.contains(.netsplitJoin) || m.type.contains(.netsplitQuit) {
            let parts = m.content.components(separatedBy: "#:#")
            let servers = (parts.last ?? "").split(separator: " ").map(String.init)
            let nicks = parts.dropLast().map { IrcMask.nick($0) }
            let joined = m.type.contains(.netsplitJoin)
            out += plain(joined ? "⇢ " : "⇠ ", color: joined ? theme.activityOther : theme.errorText)
            let between = servers.count == 2 ? "\(servers[0]) ↔ \(servers[1])" : servers.joined(separator: " ")
            out += plain("\(joined ? "Netsplit is over" : "Netsplit") (\(between)): ")
            out += plain(nicks.joined(separator: ", "), color: theme.secondaryText)
        } else if m.type.contains(.dayChange) {
            let f = DateFormatter()
            f.dateStyle = .full
            f.timeStyle = .none
            out += plain("— \(f.string(from: m.time)) —", color: theme.secondaryText)
        } else if m.type.contains(.topic) {
            out += formatted(m.content, color: theme.serverText)
        } else if m.type.contains(.invite) {
            out += plain("✉ ", color: theme.activityMessage)
            out += formatted(m.content, color: theme.serverText)
        } else if m.type.contains(.error) {
            out += formatted(m.content, color: theme.errorText)
        } else {
            // Server / Info / anything else
            if !nick.isEmpty && m.type.contains(.server) == false && m.type.contains(.info) == false {
                out += nickText(nick, isSelf: isSelf)
                out += AttributedString(" ")
            }
            out += formatted(m.content, color: theme.serverText)
        }
        return out
    }

    /// Plain-text version used for notifications and copying.
    static func plainText(_ m: IrcMessage) -> String {
        let nick = m.senderNick
        let c = IrcFormat.strip(m.content)
        if m.type.contains(.plain) { return "<\(nick)> \(c)" }
        if m.type.contains(.action) { return "* \(nick) \(c)" }
        if m.type.contains(.notice) { return "[\(nick)] \(c)" }
        if m.type.contains(.join) { return "\(nick) has joined \(c)" }
        if m.type.contains(.part) { return "\(nick) has left \(m.bufferInfo.name) \(c)" }
        if m.type.contains(.quit) { return "\(nick) has quit \(c)" }
        if m.type.contains(.nick) { return "\(nick) is now known as \(c)" }
        return c
    }
}

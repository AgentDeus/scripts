import Foundation
import Observation

enum ThemeChoice: String, CaseIterable, Identifiable {
    case system, quasselLight, quasselDark, materialLight, materialDark, solarizedLight, solarizedDark, amoled
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System (Quassel)"
        case .quasselLight: return "Quassel Light"
        case .quasselDark: return "Quassel Dark"
        case .materialLight: return "Material Light"
        case .materialDark: return "Material Dark"
        case .solarizedLight: return "Solarized Light"
        case .solarizedDark: return "Solarized Dark"
        case .amoled: return "AMOLED Black"
        }
    }
}

enum ColorizeNicks: String, CaseIterable, Identifiable {
    case all, allButMine, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All nicknames"
        case .allButMine: return "All but my own"
        case .none: return "None"
        }
    }
}

enum PrefixMode: String, CaseIterable, Identifiable {
    case all, highest, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All prefixes"
        case .highest: return "Highest prefix"
        case .none: return "No prefixes"
        }
    }
}

/// User preferences, persisted in UserDefaults.
@Observable
final class AppSettings {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    var theme: ThemeChoice { didSet { d.set(theme.rawValue, forKey: "theme") } }
    var fontSize: Double { didSet { d.set(fontSize, forKey: "fontSize") } }
    var showSeconds: Bool { didSet { d.set(showSeconds, forKey: "showSeconds") } }
    var use24h: Bool { didSet { d.set(use24h, forKey: "use24h") } }
    var showTimestamps: Bool { didSet { d.set(showTimestamps, forKey: "showTimestamps") } }
    var colorizeNicks: ColorizeNicks { didSet { d.set(colorizeNicks.rawValue, forKey: "colorizeNicks") } }
    var prefixMode: PrefixMode { didSet { d.set(prefixMode.rawValue, forKey: "prefixMode") } }
    var showHostmask: Bool { didSet { d.set(showHostmask, forKey: "showHostmask") } }
    var showRealNames: Bool { didSet { d.set(showRealNames, forKey: "showRealNames") } }
    var showFormatting: Bool { didSet { d.set(showFormatting, forKey: "showFormatting") } }
    var nicksInBrackets: Bool { didSet { d.set(nicksInBrackets, forKey: "nicksInBrackets") } }
    var hideJoinPartQuit: Bool { didSet { d.set(hideJoinPartQuit, forKey: "hideJoinPartQuit") } }
    var hideNickChanges: Bool { didSet { d.set(hideNickChanges, forKey: "hideNickChanges") } }
    var hideModeChanges: Bool { didSet { d.set(hideModeChanges, forKey: "hideModeChanges") } }
    var hideDayChange: Bool { didSet { d.set(hideDayChange, forKey: "hideDayChange") } }
    var showMarkerLine: Bool { didSet { d.set(showMarkerLine, forKey: "showMarkerLine") } }
    var initialBacklog: Int { didSet { d.set(initialBacklog, forKey: "initialBacklog") } }
    var pageBacklog: Int { didSet { d.set(pageBacklog, forKey: "pageBacklog") } }
    var notifyHighlights: Bool { didSet { d.set(notifyHighlights, forKey: "notifyHighlights") } }
    var notifyQueries: Bool { didSet { d.set(notifyQueries, forKey: "notifyQueries") } }
    var notifyAllChannelMessages: Bool { didSet { d.set(notifyAllChannelMessages, forKey: "notifyAll") } }
    var notificationSound: Bool { didSet { d.set(notificationSound, forKey: "notificationSound") } }
    var connectAllOnLaunch: Bool { didSet { d.set(connectAllOnLaunch, forKey: "connectAllOnLaunch") } }
    var showInputFormattingBar: Bool { didSet { d.set(showInputFormattingBar, forKey: "showInputFormattingBar") } }
    var showNickListButton: Bool { didSet { d.set(showNickListButton, forKey: "showNickListButton") } }
    var sendOnReturn: Bool { didSet { d.set(sendOnReturn, forKey: "sendOnReturnV2") } }
    var hideInactiveBuffersLocally: Bool { didSet { d.set(hideInactiveBuffersLocally, forKey: "hideInactiveBuffers") } }
    var inputHistorySize: Int { didSet { d.set(inputHistorySize, forKey: "inputHistorySize") } }

    private init() {
        let d = UserDefaults.standard
        func b(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }
        func i(_ k: String, _ def: Int) -> Int { d.object(forKey: k) as? Int ?? def }
        theme = ThemeChoice(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        fontSize = d.object(forKey: "fontSize") as? Double ?? 15
        showSeconds = b("showSeconds", false)
        use24h = b("use24h", true)
        showTimestamps = b("showTimestamps", true)
        colorizeNicks = ColorizeNicks(rawValue: d.string(forKey: "colorizeNicks") ?? "") ?? .all
        prefixMode = PrefixMode(rawValue: d.string(forKey: "prefixMode") ?? "") ?? .highest
        showHostmask = b("showHostmask", false)
        showRealNames = b("showRealNames", false)
        showFormatting = b("showFormatting", true)
        nicksInBrackets = b("nicksInBrackets", false)
        hideJoinPartQuit = b("hideJoinPartQuit", false)
        hideNickChanges = b("hideNickChanges", false)
        hideModeChanges = b("hideModeChanges", false)
        hideDayChange = b("hideDayChange", false)
        showMarkerLine = b("showMarkerLine", true)
        initialBacklog = i("initialBacklog", 100)
        pageBacklog = i("pageBacklog", 75)
        notifyHighlights = b("notifyHighlights", true)
        notifyQueries = b("notifyQueries", true)
        notifyAllChannelMessages = b("notifyAll", false)
        notificationSound = b("notificationSound", true)
        connectAllOnLaunch = b("connectAllOnLaunch", true)
        showInputFormattingBar = b("showInputFormattingBar", false)
        showNickListButton = b("showNickListButton", true)
        // Default: the keyboard return key inserts a new line, the send button sends.
        sendOnReturn = b("sendOnReturnV2", false)
        hideInactiveBuffersLocally = b("hideInactiveBuffers", false)
        inputHistorySize = i("inputHistorySize", 50)
    }

    var hiddenTypes: MessageType {
        var t: MessageType = []
        if hideJoinPartQuit { t.formUnion(.joinPartQuit) }
        if hideNickChanges { t.insert(.nick) }
        if hideModeChanges { t.insert(.mode) }
        if hideDayChange { t.insert(.dayChange) }
        return t
    }
}

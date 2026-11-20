import SwiftUI

@main
struct iQuasselCCApp: App {
    @State private var manager = SessionManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Notifier.shared.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(manager)
                .onAppear {
                    manager.autoConnect()
                    Notifier.shared.onOpen = { account, buffer in
                        guard let a = manager.store.account(account) else { return }
                        manager.connect(a)
                        manager.select(buffer: buffer, in: account)
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                AppLifecycle.shared.becameActive()
                manager.appBecameActive()
            case .background:
                AppLifecycle.shared.enteredBackground()
                for s in manager.sessions.values {
                    if let b = manager.selectedBuffer[s.id] { s.setMarkerLine(b) }
                }
            default:
                break
            }
        }
    }
}

struct RootView: View {
    @Environment(SessionManager.self) private var manager
    @Environment(\.colorScheme) private var systemScheme
    @State private var settings = AppSettings.shared

    var body: some View {
        let theme = ChatTheme.make(settings.theme, scheme: systemScheme)
        Group {
            if let s = manager.activeSession {
                MainChatView(session: s)
                    .id(s.id)
            } else {
                NavigationStack {
                    AccountsView()
                }
            }
        }
        .environment(\.chatTheme, theme)
        .tint(theme.isDark ? theme.accent : theme.primary)
        .preferredColorScheme(settings.theme == .system ? nil : theme.colorScheme)
        .dynamicTypeSize(.xSmall ... .accessibility2)
    }
}

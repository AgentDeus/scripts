import Foundation
import Observation
import UIKit

/// Owns every core connection. Multiple cores can be connected at the same time;
/// one of them is "active" (shown in the chat UI) and the drawer lets the user switch.
@Observable
final class SessionManager {
    let store = AccountStore()
    var sessions: [UUID: CoreSession] = [:]
    var activeSessionId: UUID? {
        didSet { UserDefaults.standard.set(activeSessionId?.uuidString, forKey: "iQuasselCC.activeAccount") }
    }
    /// Selected buffer per session.
    var selectedBuffer: [UUID: BufferId] = [:]
    /// Selected chat list (buffer view) per session; nil = all chats.
    var selectedView: [UUID: Int32] = [:]

    init() {
        if let s = UserDefaults.standard.string(forKey: "iQuasselCC.activeAccount"), let id = UUID(uuidString: s),
           store.account(id) != nil {
            activeSessionId = id
        }
        if let d = UserDefaults.standard.dictionary(forKey: "iQuasselCC.selectedBuffers") as? [String: Int] {
            for (k, v) in d { if let id = UUID(uuidString: k) { selectedBuffer[id] = Int32(v) } }
        }
    }

    var activeSession: CoreSession? { activeSessionId.flatMap { sessions[$0] } }

    var connectedSessions: [CoreSession] {
        store.accounts.compactMap { sessions[$0.id] }
    }

    func session(for account: Account) -> CoreSession {
        if let s = sessions[account.id] {
            s.account = account
            return s
        }
        let s = CoreSession(account: account)
        s.onCertificateAccepted = { [weak self] fp in
            guard var a = self?.store.account(account.id) else { return }
            a.trustedFingerprint = fp
            self?.store.upsert(a)
        }
        sessions[account.id] = s
        return s
    }

    func connect(_ account: Account, activate: Bool = true) {
        var a = account
        a.lastUsed = Date()
        store.upsert(a)
        let s = session(for: a)
        if !s.phase.isActive { s.connect() }
        if activate { activeSessionId = a.id }
    }

    func disconnect(_ id: UUID) {
        sessions[id]?.disconnect()
        sessions.removeValue(forKey: id)
        if activeSessionId == id {
            activeSessionId = sessions.keys.first
        }
    }

    func disconnectAll() {
        for id in Array(sessions.keys) { disconnect(id) }
    }

    func remove(_ account: Account) {
        disconnect(account.id)
        store.remove(account)
    }

    func select(buffer: BufferId?, in session: UUID) {
        selectedBuffer[session] = buffer
        var d = [String: Int]()
        for (k, v) in selectedBuffer { d[k.uuidString] = Int(v) }
        UserDefaults.standard.set(d, forKey: "iQuasselCC.selectedBuffers")
    }

    /// Reconnect automatically at launch to the cores that are flagged for it.
    func autoConnect() {
        for a in store.accounts where a.autoConnect && (a.id == activeSessionId || AppSettings.shared.connectAllOnLaunch) {
            connect(a, activate: a.id == activeSessionId)
        }
    }

    func appBecameActive() {
        for s in sessions.values { s.ensureConnected() }
    }
}

/// Tracks whether the app is in the foreground.
final class AppLifecycle {
    static let shared = AppLifecycle()
    var isActive = true
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    /// Ask iOS for some extra time so connections survive brief app switches.
    @MainActor func enteredBackground() {
        isActive = false
        guard bgTask == .invalid else { return }
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "iQuasselCC.keepalive") { [weak self] in
            MainActor.assumeIsolated { self?.endBackgroundTask() }
        }
    }

    @MainActor func becameActive() {
        isActive = true
        endBackgroundTask()
    }

    @MainActor private func endBackgroundTask() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }
}

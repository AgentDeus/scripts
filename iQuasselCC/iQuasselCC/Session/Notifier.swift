import Foundation
import UserNotifications

/// Local notifications for highlights and private messages.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    /// Called when the user taps a notification: (account, buffer).
    var onOpen: ((UUID, BufferId) -> Void)?

    func requestAuthorization() {
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func notifyIfNeeded(_ m: IrcMessage, session: CoreSession) {
        let s = AppSettings.shared
        guard !m.flags.contains(.selfMsg), !m.flags.contains(.ignored), !m.flags.contains(.backlog) else { return }
        guard m.type.intersection(.conversation) != [] else { return }
        let isQuery = m.bufferInfo.type.contains(.query)
        let isHighlight = m.flags.contains(.highlight)
        let wanted = (isHighlight && s.notifyHighlights) || (isQuery && s.notifyQueries)
            || (s.notifyAllChannelMessages && m.bufferInfo.type.contains(.channel))
        guard wanted else { return }

        let content = UNMutableNotificationContent()
        let network = session.networks[m.bufferInfo.networkId]?.networkName ?? ""
        content.title = isQuery ? m.senderNick : "\(m.bufferInfo.name)"
        content.subtitle = isQuery ? network : "\(m.senderNick) · \(network)"
        let text = IrcFormat.strip(m.content)
        content.body = m.type.contains(.action) ? "* \(m.senderNick) \(text)" : text
        content.threadIdentifier = "\(session.id.uuidString)/\(m.bufferInfo.bufferId)"
        content.userInfo = ["account": session.id.uuidString, "buffer": Int(m.bufferInfo.bufferId)]
        if s.notificationSound { content.sound = .default }
        let req = UNNotificationRequest(identifier: "\(session.id.uuidString)-\(m.msgId)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    func clear(account: UUID, buffer: BufferId) {
        let thread = "\(account.uuidString)/\(buffer)"
        let c = UNUserNotificationCenter.current()
        c.getDeliveredNotifications { list in
            let ids = list.filter { $0.request.content.threadIdentifier == thread }.map { $0.request.identifier }
            c.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let a = (info["account"] as? String).flatMap(UUID.init(uuidString:)), let b = info["buffer"] as? Int {
            DispatchQueue.main.async { self.onOpen?(a, Int32(b)) }
        }
        completionHandler()
    }
}

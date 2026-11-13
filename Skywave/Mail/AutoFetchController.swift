import Foundation
import UserNotifications

/// Zeitgesteuerter Telnet-Abruf im Hintergrund: tickt alle 30 Sekunden,
/// startet bei fälligem Intervall einen normalen CMS-Austausch und
/// meldet neu empfangene Post als macOS-Mitteilung. Läuft app-weit
/// (unabhängig von offenen Fenstern), damit der Abruf auch mit
/// geschlossenem Hauptfenster weiterläuft.
@MainActor @Observable final class AutoFetchController {

    /// Nächster geplanter Abruf; nil solange der Auto-Abruf aus ist.
    private(set) var nextFetch: Date?

    private var ticker: Task<Void, Never>?

    /// Prüfintervall des Tickers — klein gegenüber dem Abrufintervall,
    /// damit Einstellungs-Änderungen zeitnah greifen.
    private static let tick: Duration = .seconds(30)

    func start(app: AppModel, exchange: ExchangeController) {
        guard ticker == nil else { return }
        ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tick)
                await tickOnce(app: app, exchange: exchange)
            }
        }
    }

    private func tickOnce(app: AppModel, exchange: ExchangeController) async {
        guard let workspace = app.workspace else { return }
        let settings = workspace.settings
        guard settings.autoFetchEnabled, !settings.effectiveCallsign.isEmpty else {
            nextFetch = nil
            return
        }

        let interval = TimeInterval(max(5, settings.autoFetchIntervalMinutes) * 60)
        guard let due = nextFetch else {
            // Frisch aktiviert: erst in einem vollen Intervall abrufen,
            // nicht sofort — der Nutzer hat gerade selbst Kontrolle.
            nextFetch = Date().addingTimeInterval(interval)
            return
        }
        guard Date() >= due, !exchange.isRunning else { return }

        nextFetch = Date().addingTimeInterval(interval)
        await exchange.exchange(
            store: workspace.store, settings: settings, history: workspace.history)
        if let received = exchange.lastStats?.received.count,
            exchange.lastSuccessDate.map({ Date().timeIntervalSince($0) < 60 }) == true,
            received > 0 {
            await notify(received: received)
        }
    }

    private func notify(received: Int) async {
        let center = UNUserNotificationCenter.current()
        let granted =
            (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = "Skywave"
        content.body =
            received == 1
            ? String(localized: "1 neue Nachricht empfangen")
            : String(localized: "\(received) neue Nachrichten empfangen")
        content.sound = .default
        try? await center.add(
            UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

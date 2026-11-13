import Foundation

/// Hält die Gateway-Liste im Hintergrund aktuell.
///
/// Tickt bewusst nur alle 30 Minuten statt alle 30 Sekunden wie der
/// Auto-Abruf: das Ziel ist ein Tagesraster, da braucht es keine
/// Sekundenauflösung. Ob wirklich ein Request rausgeht, entscheidet
/// `GatewayStore.refresh` — dort sitzen die 24-Stunden-Regel, das
/// Backoff nach Fehlern und die harte Stundengrenze. Winlink verlangt
/// sparsame Abfrage, deshalb steckt die Politik im Store und nicht hier.
@MainActor final class GatewayRefreshController {
    private var ticker: Task<Void, Never>?

    private static let tick: Duration = .seconds(30 * 60)
    /// Kurz nach dem Start einmal prüfen, damit eine tagealte Liste
    /// nicht bis zum ersten Tick wartet.
    private static let initialDelay: Duration = .seconds(20)

    func start(app: AppModel) {
        guard ticker == nil else { return }
        ticker = Task {
            try? await Task.sleep(for: Self.initialDelay)
            while !Task.isCancelled {
                await tickOnce(app: app)
                try? await Task.sleep(for: Self.tick)
            }
        }
    }

    private func tickOnce(app: AppModel) async {
        guard let workspace = app.workspace else { return }
        await workspace.gateways.refresh(settings: workspace.settings, force: false)
    }
}

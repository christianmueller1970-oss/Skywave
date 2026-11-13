import SwiftUI
import WinlinkKit

/// Root of the main window: the mailbox, or an onboarding hint until
/// callsign and password are configured.
struct ContentView: View {
    @Environment(AppSettingsStore.self) private var settings

    var body: some View {
        // Observing settings.callsign re-evaluates as soon as it is
        // entered in the settings window.
        if settings.effectiveCallsign.isEmpty {
            onboarding
        } else {
            MailboxView()
        }
    }

    private var onboarding: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope.badge.person.crop")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Willkommen bei Skywave")
                .font(.largeTitle.bold())
            Text("Winlink-Mail, nativ auf dem Mac")
                .foregroundStyle(.secondary)

            Divider().frame(width: 280)

            Label(
                "Hinterlege zuerst Rufzeichen und Winlink-Passwort in den Einstellungen (⌘,).",
                systemImage: "gearshape"
            )
            .foregroundStyle(.statusWarn)

            SettingsLink {
                Text("Einstellungen öffnen …")
            }
            .padding(.top, 4)

            Text("Protokoll: WinlinkKit \(WinlinkKit.version)")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .padding(48)
        .frame(minWidth: 520, minHeight: 400)
    }
}

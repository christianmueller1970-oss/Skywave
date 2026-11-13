import SwiftUI

/// First-launch screen: shown instead of the mailbox until the user
/// granted a data folder.
struct StorageSetupView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Wo soll Skywave deine Daten ablegen?")
                .font(.largeTitle.bold())
            Text("Nachrichten, Adressbuch und Einstellungen als normale Dateien")
                .foregroundStyle(.secondary)

            Divider().frame(width: 320)

            Text("""
                Empfohlen: ein neuer Ordner «Skywave» in deinen Dokumenten. \
                Du wählst ihn einmal aus, danach merkt sich die App die Freigabe. \
                Vorhandene Daten werden automatisch übernommen.
                """)
            .frame(maxWidth: 420)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)

            Button {
                app.chooseFolder()
            } label: {
                Label("Ordner wählen …", systemImage: "folder")
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .padding(.top, 4)

            Text("Das Winlink-Passwort bleibt weiterhin sicher im Schlüsselbund.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .padding(48)
        .frame(minWidth: 560, minHeight: 440)
    }
}

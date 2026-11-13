import SwiftUI
import Sparkle

@main
struct SkywaveApp: App {
    // Die app-weiten Objekte liegen in `AppServices`, nicht als frische
    // @State-Werte: `init()` unten braucht dieselben Instanzen wie die
    // Fenster. Über `_state.wrappedValue` bekam es andere — der Abbau
    // beim Beenden lief dann auf einem Objekt, das nie verbunden war,
    // und rigctld blieb als Waise zurück (2026-11-11 am Gerät gesehen).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var app = AppServices.app
    @State private var exchange = AppServices.exchange
    @State private var rig = AppServices.rig
    @State private var navigation = AppServices.navigation
    @State private var commands = AppServices.commands
    @State private var autoFetch = AppServices.autoFetch
    @State private var gatewayRefresh = AppServices.gatewayRefresh

    // App-weite UI-Präferenz, bewusst in UserDefaults statt
    // settings.json: die Scene braucht den Wert schon bevor ein
    // Workspace existiert, und @AppStorage triggert die
    // Scene-Neubewertung zuverlässig.
    @AppStorage("showMenuBarStatus") private var showMenuBarStatus = true

    // Sparkle auto-updater. `startingUpdater: true` enables background
    // checks against the appcast named by SUFeedURL in Info.plist.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    init() {
        // Vor allem anderen: die Sprachwahl muss stehen, bevor der erste
        // Text nachgeschlagen wird. Nicht im Testlauf, der Deutsch erzwingt
        // und die echten Vorgaben nicht anfassen soll.
        if !RigController.isRunningTests {
            // Musste die Vorgabe erst jetzt gesetzt werden, läuft dieser
            // Prozess womöglich in der falschen Sprache: einmal neu
            // starten. Beim nächsten Start stimmt die Vorgabe, es gibt
            // also keine Schleife.
            if AppLanguage.applyAtLaunch(), AppLanguage.active != AppLanguage.selected() {
                AppRelauncher.relaunchBeforeStart()
            }
        }
        AppServices.bootstrap()
    }

    var body: some Scene {
        // The workspace check lives in root VIEWS, not here: scene
        // bodies do not reliably re-evaluate on @Observable changes,
        // view bodies do.
        WindowGroup(id: "mailbox") {
            MainRootView()
                .environment(app)
                .environment(exchange)
                .environment(rig)
                .environment(navigation)
                .environment(commands)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Nach Updates suchen …") {
                    updaterController.updater.checkForUpdates()
                }
            }
            CommandGroup(replacing: .newItem) {
                OpenComposeWindowButton()
            }
            SkywaveCommands()
        }

        // Opened plain (⌘N) for a fresh message, or with a ComposeIntent
        // value to prefill a reply, forward or draft.
        WindowGroup("Neue Nachricht", id: "compose", for: ComposeIntent.self) { $intent in
            ComposeRootView(intent: intent)
                .environment(app)
                .environment(exchange)
                .environment(rig)
        }
        .defaultSize(width: 560, height: 480)

        // Das Gateway-Verzeichnis lässt sich zusätzlich als eigenes Fenster
        // öffnen (neben dem Postfach, beim Verbinden). Kontakte,
        // Positionsmeldung und GRIB-Assistent sind Bereiche des Hauptfensters.
        Window("Gateways", id: "gateways") {
            GatewayRootView()
                .environment(app)
                .environment(exchange)
                .environment(rig)
        }
        .defaultSize(width: 900, height: 520)

        Settings {
            SettingsRootView()
                .environment(app)
                // Der Pegel-Assistent (Sheet in den Einstellungen) braucht den
                // ExchangeController — ohne ihn stürzt das Sheet beim Öffnen ab.
                .environment(exchange)
                .environment(rig)
        }

        MenuBarExtra(
            "Skywave", systemImage: "antenna.radiowaves.left.and.right",
            isInserted: $showMenuBarStatus
        ) {
            MenuBarStatusView()
                .environment(app)
                .environment(exchange)
                .environment(rig)
                .environment(autoFetch)
        }
    }
}

/// Main window: mailbox once a data folder is granted, the storage
/// setup otherwise.
private struct MainRootView: View {
    @Environment(AppModel.self) private var app
    @Environment(RigController.self) private var rig

    var body: some View {
        if let workspace = app.workspace {
            ContentView()
                .workspaceEnvironment(workspace)
                // Funkgerät beim Start verbinden, sofern eingerichtet und
                // gewünscht. Ein Fehlschlag steht danach im Status des
                // Tabs «Funkgerät» — kein Dialog beim App-Start.
                .task {
                    let settings = workspace.settings
                    // Nicht im Testlauf: die Test-App liefe sonst mit den echten
                    // Einstellungen auf das echte Funkgerät los.
                    guard !RigController.isRunningTests,
                        settings.rigAutoConnect, rig.status == .disconnected,
                        let target = settings.rigLink
                    else { return }
                    await rig.connect(target.link, name: target.name)
                }
        } else {
            StorageSetupView()
        }
    }
}

private struct ComposeRootView: View {
    @Environment(AppModel.self) private var app

    let intent: ComposeIntent?

    var body: some View {
        if let workspace = app.workspace {
            ComposeView(intent: intent)
                .workspaceEnvironment(workspace)
        }
    }
}

private struct GatewayRootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let workspace = app.workspace {
            GatewayDirectoryView()
                .workspaceEnvironment(workspace)
        }
    }
}

private struct SettingsRootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let workspace = app.workspace {
            SettingsView()
                .environment(workspace.settings)
                .environment(workspace.signatures)
                .environment(workspace.queries)
        }
    }
}

extension View {
    /// Injects one workspace's stores into a window's environment.
    fileprivate func workspaceEnvironment(_ workspace: Workspace) -> some View {
        self
            .environment(workspace.settings)
            .environment(workspace.store)
            .environment(workspace.contacts)
            .environment(workspace.signatures)
            .environment(workspace.gateways)
            .environment(workspace.queries)
            .environment(workspace.history)
    }
}

/// ⌘N in the main menu — needs its own view to reach openWindow.
private struct OpenComposeWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Neue Nachricht") {
            openWindow(id: "compose")
        }
        .keyboardShortcut("n")
    }
}

/// Hält das App-Ende kurz auf, solange Skywave den Sender selbst tastet:
/// erst entsichern, dann beenden. `willTerminate` (siehe `AppServices`)
/// beendet danach die Hilfsprozesse; rigctld allein löst die PTT nicht.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let exchange = AppServices.exchange
        guard exchange.needsUnkeyOnTermination else { return .terminateNow }
        Task { @MainActor in
            await exchange.unkeyForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// Die app-weiten Objekte, je genau einmal — für die Fenster (über
/// @State in `SkywaveApp`) wie für den Start- und Beenden-Code.
@MainActor enum AppServices {
    static let app = AppModel()
    static let exchange = ExchangeController()
    static let rig = RigController()
    static let navigation = AppNavigation()
    static let commands = MailboxCommandCenter()
    static let autoFetch = AutoFetchController()
    static let gatewayRefresh = GatewayRefreshController()

    private static var didBootstrap = false

    /// Verdrahtet die Objekte und hängt den Abbau ans App-Ende. Läuft
    /// nur einmal, auch wenn SwiftUI die App-Struktur mehrfach anlegt.
    static func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        exchange.rig = rig
        // Keine Hilfsprozesse zurücklassen, wenn die App endet. Die
        // Meldung kommt auf dem Main-Thread; beide Aufrufe sind synchron
        // (Signal an das Kind), es braucht hier keine async-Arbeit.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                exchange.killModemOnTerminate()
                // Sonst hielte rigctld weiter den seriellen Port.
                rig.killOnTerminate()
            }
        }
        autoFetch.start(app: app, exchange: exchange)
        gatewayRefresh.start(app: app)
    }
}

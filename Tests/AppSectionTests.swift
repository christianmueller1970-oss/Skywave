import Testing

@testable import Skywave

/// Bereiche des Hauptfensters und der Wechsel zwischen ihnen.
@MainActor
@Suite struct AppSectionTests {
    @Test func startsInTheInbox() {
        let nav = AppNavigation()
        #expect(nav.section == .folder(.inbox))
        #expect(nav.lastFolder == .inbox)
    }

    /// Der zuletzt gezeigte Ordner bleibt stehen, während ein Bereich
    /// ausserhalb des Postfachs offen ist — Ordner-Dialoge brauchen ihn.
    @Test func lastFolderSurvivesLeavingTheMailbox() {
        let nav = AppNavigation()
        nav.show(.folder(.custom("QSL/2026")))
        nav.show(.gateways)
        #expect(nav.section == .gateways)
        #expect(nav.section.folder == nil)
        #expect(nav.lastFolder == .custom("QSL/2026"))

        nav.show(.folder(.outbox))
        #expect(nav.lastFolder == .outbox)
    }

    /// Jeder Bereich der Seitenleiste hat Titel und Symbol, kein Titel
    /// kommt doppelt vor.
    @Test func sidebarSectionsAreNamedAndDistinct() {
        let mailbox: [AppSection] = [.inbox, .drafts, .outbox, .sent, .trash].map { .folder($0) }
        let all = mailbox + AppSection.radio + AppSection.tools
        for section in all {
            #expect(!section.title.isEmpty)
            #expect(!section.symbol.isEmpty)
        }
        #expect(Set(all.map(\.title)).count == all.count)
        #expect(AppSection.folder(.custom("QSL/2026")).title == "2026")
    }
}

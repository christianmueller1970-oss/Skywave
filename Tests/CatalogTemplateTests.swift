import Testing
@testable import Skywave

struct CatalogTemplateTests {

    /// Jede Vorlage liefert einen sendefähigen Entwurf: Empfänger und
    /// Subject gesetzt (B2F verlangt beides).
    @Test func allTemplatesProduceAddressedDrafts() {
        for template in CatalogTemplate.allCases {
            let draft = template.draft
            #expect(!draft.to.isEmpty)
            #expect(!draft.subject.isEmpty)
            #expect(!template.menuTitle.isEmpty)
            #expect(!template.help.isEmpty)
        }
    }

    @Test func winlinkHelpRequestsTheCatalogHelpFile() {
        let draft = CatalogTemplate.winlinkHelp.draft
        #expect(draft.to == ["INQUIRY"])
        #expect(draft.subject == "REQUEST")
        #expect(draft.body == "WL2K_HELP")
    }

    /// Die Template-ID übersteht die Reise durch den ComposeIntent.
    @Test func templateRoundTripsThroughComposeIntent() {
        let intent = ComposeIntent(mode: .catalog, mid: CatalogTemplate.saildocsWeb.rawValue)
        #expect(CatalogTemplate(rawValue: intent.mid) == .saildocsWeb)
    }
}

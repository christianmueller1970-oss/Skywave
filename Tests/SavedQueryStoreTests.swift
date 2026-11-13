import Foundation
import Testing

@testable import Skywave

@MainActor
@Suite struct SavedQueryStoreTests {

    private func makeFileURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("queries.json")
    }

    @Test func addUpdateRemovePersist() {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = SavedQueryStore(fileURL: url)
        let query = store.add(
            name: " Wetter Bodensee ", to: "query@saildocs.com",
            subject: "Saildocs request", body: "send GFS:48N,47N,8E,10E|0.5,0.5|0,24|WIND")
        #expect(query.name == "Wetter Bodensee")
        #expect(store.add().name == "Abfrage")
        #expect(store.add().name == "Abfrage 2")

        var edited = query
        edited.body = "send GFS:48N,47N,8E,10E|0.25,0.25|0,24|WIND,GUST"
        store.update(edited)

        let reopened = SavedQueryStore(fileURL: url)
        #expect(reopened.queries.count == 3)
        #expect(reopened.query(id: query.id)?.body == edited.body)

        reopened.remove(edited)
        #expect(SavedQueryStore(fileURL: url).queries.count == 2)
    }

    @Test func recognisesQueryServices() {
        #expect(SavedQueryStore.isQueryAddress("INQUIRY"))
        #expect(SavedQueryStore.isQueryAddress("service"))
        #expect(SavedQueryStore.isQueryAddress("SMTP:query@saildocs.com"))
        #expect(SavedQueryStore.isQueryAddress("reply@saildocs.com"))
        #expect(!SavedQueryStore.isQueryAddress("HB9ABC"))
        #expect(!SavedQueryStore.isQueryAddress("rene@example.com"))
    }
}

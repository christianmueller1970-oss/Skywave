import SwiftUI
import UniformTypeIdentifiers
import WinlinkKit

/// The reading pane: headers, body and attachments of one message.
struct MessageDetailView: View {
    @Environment(MailStore.self) private var store

    let item: MailItem

    @State private var exportingAttachment: B2File?

    var body: some View {
        if let message = store.message(for: item) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header(message)
                    if !message.files.isEmpty {
                        attachments(message)
                    }
                    Divider()
                    Text(message.bodyText)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .task(id: item.id) {
                if !item.isRead {
                    store.markRead(item)
                }
            }
            .fileExporter(
                isPresented: Binding(
                    get: { exportingAttachment != nil },
                    set: { if !$0 { exportingAttachment = nil } }
                ),
                document: AttachmentDocument(data: exportingAttachment?.data ?? Data()),
                contentType: .data,
                defaultFilename: exportingAttachment?.name
            ) { _ in
                exportingAttachment = nil
            }
        } else {
            ContentUnavailableView(
                "Nachricht kann nicht gelesen werden",
                systemImage: "exclamationmark.triangle")
        }
    }

    private func header(_ message: B2Message) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.subject)
                .font(.title2.bold())
                .textSelection(.enabled)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                GridRow {
                    Text("Von:").foregroundStyle(.secondary)
                    Text(message.from.description).textSelection(.enabled)
                }
                GridRow {
                    Text("An:").foregroundStyle(.secondary)
                    Text(message.to.map(\.description).joined(separator: ", "))
                        .textSelection(.enabled)
                }
                if !message.cc.isEmpty {
                    GridRow {
                        Text("Cc:").foregroundStyle(.secondary)
                        Text(message.cc.map(\.description).joined(separator: ", "))
                            .textSelection(.enabled)
                    }
                }
                if let date = message.date {
                    GridRow {
                        Text("Datum:").foregroundStyle(.secondary)
                        Text(date.formatted(date: .long, time: .shortened))
                    }
                }
                GridRow {
                    Text("MID:").foregroundStyle(.secondary)
                    Text(message.mid).font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.callout)
        }
    }

    private func attachments(_ message: B2Message) -> some View {
        HStack(spacing: 8) {
            ForEach(message.files.indices, id: \.self) { index in
                let file = message.files[index]
                Button {
                    exportingAttachment = file
                } label: {
                    Label(
                        "\(file.name) (\(file.size.formatted(.byteCount(style: .file))))",
                        systemImage: "paperclip")
                }
                .buttonStyle(.bordered)
                .help("Anhang sichern")
            }
        }
    }
}

/// Wraps attachment bytes for SwiftUI's fileExporter.
struct AttachmentDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.data]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

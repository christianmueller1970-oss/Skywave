import SwiftUI
import WinlinkKit

/// What a compose window is opened for: a reply or forward of an
/// existing message, or continuing a saved draft, identified by MID.
/// A window opened without an intent (⌘N) composes a fresh message.
struct ComposeIntent: Codable, Hashable {
    enum Mode: String, Codable {
        case reply, replyAll, forward, editDraft
        /// Vorbefüllte Katalog-/Saildocs-Abfrage; `mid` trägt dann die
        /// `CatalogTemplate`-ID statt einer Message-ID.
        case catalog
        /// Gespeicherte Abfrage; `mid` trägt die `SavedQuery`-ID.
        case savedQuery
        /// GRIB-Anfrage aus dem Assistenten; `mid` trägt die
        /// Saildocs-Spezifikation.
        case gribSpec
    }

    var mode: Mode
    var mid: String
}

/// Ein Anhang im Compose: das Original bleibt erhalten, damit ein
/// Wechsel der Ziel-Bildgrösse verlustfrei neu optimieren kann;
/// gesendet wird `file` (die optimierte Fassung, falls vorhanden).
private struct ComposeAttachment: Identifiable {
    let id = UUID()
    var originalName: String
    var originalData: Data
    var optimized: B2File?

    var file: B2File { optimized ?? B2File(name: originalName, data: originalData) }
}

/// The compose window: recipient, subject, body, attachments.
/// Saving queues the message in the outbox; it is transmitted with
/// the next CMS exchange.
struct ComposeView: View {
    @Environment(MailStore.self) private var store
    @Environment(AppSettingsStore.self) private var settings
    @Environment(ContactsStore.self) private var contacts
    @Environment(SignatureStore.self) private var signatures
    @Environment(SavedQueryStore.self) private var queries
    @Environment(\.dismiss) private var dismiss

    /// Set when the window replies to or forwards an existing message.
    var intent: ComposeIntent?

    @State private var to = ""
    @State private var cc = ""
    @State private var subject = ""
    @State private var body_ = ""
    @State private var attachments = [ComposeAttachment]()

    /// MID of the draft this window edits; repeated saves overwrite
    /// that file. Set on first ⌘S or when opened via `.editDraft`.
    @State private var draftMID: String?

    /// Text of the signature currently at the end of the body, so
    /// switching signatures replaces instead of stacking them.
    @State private var appliedSignature: String?

    @State private var importingAttachment = false
    @State private var errorMessage: String?

    /// Name-Abfrage für «Als Abfrage speichern».
    @State private var savingQuery = false
    @State private var queryName = ""

    /// Mehrere Empfänger, darunter ein reines Rufzeichen: über eine
    /// Direktverbindung (P2P) ginge diese Nachricht nicht mit.
    private var p2pHint: Bool {
        let recipients = (to + "," + cc).split(whereSeparator: { ",;".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return recipients.count > 1 && recipients.contains { !$0.contains("@") }
    }

    /// Die Nachricht geht an einen Abfragedienst (INQUIRY, Saildocs) —
    /// dann lohnt es sich, sie als Abfrage zu speichern.
    private var addressesQueryService: Bool {
        to.split(whereSeparator: { ",;".contains($0) })
            .contains { SavedQueryStore.isQueryAddress(String($0)) }
    }

    private var mycall: String { settings.effectiveCallsign }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                LabeledContent("An:") {
                    TextField(
                        "An:", text: $to,
                        prompt: Text("HB9XYZ oder name@example.com")
                    )
                    .labelsHidden()
                    .autocorrectionDisabled()
                    .onChange(of: to) { _, new in
                        let cleaned = SingleLineInput.clean(new)
                        if cleaned != new { to = cleaned }
                    }
                    contactsMenu(into: $to, help: String(localized: "Empfänger aus den Kontakten übernehmen"))
                }
                LabeledContent("Cc:") {
                    TextField("Cc:", text: $cc)
                        .labelsHidden()
                        .autocorrectionDisabled()
                        .onChange(of: cc) { _, new in
                            let cleaned = SingleLineInput.clean(new)
                            if cleaned != new { cc = cleaned }
                        }
                    contactsMenu(into: $cc, help: String(localized: "Cc-Empfänger aus den Kontakten übernehmen"))
                }
                TextField("Betreff:", text: $subject)
                    // Eingefügter Text bringt Leerraum und Umbrüche mit;
                    // siehe `SingleLineInput`.
                    .onChange(of: subject) { _, new in
                        let cleaned = SingleLineInput.clean(new)
                        if cleaned != new { subject = cleaned }
                    }
                if p2pHint {
                    Text("Hinweis: Über eine Direktverbindung (P2P) geht nur Post, die ausschliesslich an das Rufzeichen der Gegenstation adressiert ist.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.columns)
            .padding([.horizontal, .top])

            HStack {
                Button {
                    importingAttachment = true
                } label: {
                    Label("Anhängen …", systemImage: "paperclip")
                }
                if !signatures.signatures.isEmpty {
                    Menu {
                        ForEach(signatures.signatures) { signature in
                            Button(signature.name) {
                                apply(signature)
                            }
                        }
                    } label: {
                        Label("Signatur", systemImage: "signature")
                    }
                    .fixedSize()
                    .help("Signatur ans Ende der Nachricht setzen")
                }
                Menu {
                    Picker("Bildgrösse", selection: Binding(
                        get: { settings.imageAttachmentTarget },
                        set: { settings.imageAttachmentTarget = $0 }
                    )) {
                        ForEach(ImageAttachmentTarget.allCases) { target in
                            Text(target.displayName).tag(target)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(
                        "Bilder: \(settings.imageAttachmentTarget.displayName)",
                        systemImage: "photo")
                }
                .fixedSize()
                .help("Bild-Anhänge fürs Funkbudget auf diese Zielgrösse verkleinern")
                if addressesQueryService {
                    Button {
                        queryName = subject == "REQUEST" || subject == "Saildocs request" ? "" : subject
                        savingQuery = true
                    } label: {
                        Label("Als Abfrage speichern", systemImage: "bookmark")
                    }
                    .fixedSize()
                    .help("Empfänger, Betreff und Text als Abfrage merken — fürs «Abfragen»-Menü")
                }
                ForEach(attachments) { attachment in
                    HStack(spacing: 2) {
                        Text(attachment.file.name)
                            .lineLimit(1)
                        Text(attachment.file.data.count.formatted(.byteCount(style: .file)))
                            .foregroundStyle(.secondary)
                        Button {
                            attachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .help(
                        attachment.optimized == nil
                            ? attachment.originalName
                            : String(localized: "Original \(attachment.originalData.count.formatted(.byteCount(style: .file))) → \(attachment.file.data.count.formatted(.byteCount(style: .file)))")
                    )
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            if !attachments.isEmpty {
                let total = attachments.map(\.file.data.count).reduce(0, +)
                Text(
                    "Gesamt \(total.formatted(.byteCount(style: .file))) — \(TransferTimeEstimator.formatted(bytes: total, mode: .ardop500)) ARDOP 500 · \(TransferTimeEstimator.formatted(bytes: total, mode: .ardop2000)) ARDOP 2000"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 6)
                .help("Grobe Übertragungszeit der Anhänge, ohne Verbindungsaufbau")
            }

            Divider()

            TextEditor(text: $body_)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(8)
        }
        .frame(minWidth: 520, minHeight: 420)
        .navigationTitle(subject.isEmpty ? String(localized: "Neue Nachricht") : subject)
        .onAppear {
            prefill()
            // A fresh window starts with the default signature in place;
            // replies and forwards leave the quoted text untouched. Bei
            // Katalog-Abfragen stört eine Signatur die Anfrage-Syntax.
            if intent?.mode != .catalog, body_.isEmpty,
                let signature = signatures.defaultSignature {
                apply(signature)
            }
        }
        .onChange(of: settings.imageAttachmentTarget) {
            // Verlustfrei aus dem behaltenen Original neu optimieren.
            for index in attachments.indices {
                attachments[index].optimized = optimizedImage(
                    name: attachments[index].originalName,
                    data: attachments[index].originalData)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    saveDraft()
                } label: {
                    Label("Als Entwurf speichern", systemImage: "doc.badge.ellipsis")
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(mycall.isEmpty)
                .help(
                    mycall.isEmpty
                        ? "Zuerst das Rufzeichen in den Einstellungen (⌘,) hinterlegen"
                        : "Nachricht unter «Entwürfe» ablegen und später weiterschreiben (⌘S)")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    queueMessage()
                } label: {
                    Label("In Postausgang legen", systemImage: "tray.and.arrow.down")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(mycall.isEmpty)
                .help(
                    mycall.isEmpty
                        ? "Zuerst das Rufzeichen in den Einstellungen (⌘,) hinterlegen"
                        : "Nachricht in den Postausgang legen (⌘⏎)")
            }
        }
        .fileImporter(
            isPresented: $importingAttachment,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            addAttachments(from: result)
        }
        .alert(
            "Nachricht kann nicht gespeichert werden",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Als Abfrage speichern", isPresented: $savingQuery) {
            TextField("Name", text: $queryName, prompt: Text("Wetter Bodensee"))
            Button("Speichern") { saveAsQuery() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Empfänger, Betreff und Text landen unter diesem Namen im «Abfragen»-Menü.")
        }
    }

    /// Fills the fields from the message this window replies to,
    /// forwards or continues editing. No-op for fresh windows or when
    /// the original is gone.
    private func prefill() {
        guard let intent else { return }

        if intent.mode == .catalog {
            guard let template = CatalogTemplate(rawValue: intent.mid) else { return }
            let draft = template.draft
            to = draft.to.joined(separator: ", ")
            subject = draft.subject
            body_ = draft.body
            return
        }
        if intent.mode == .savedQuery {
            guard let id = UUID(uuidString: intent.mid), let query = queries.query(id: id)
            else { return }
            to = query.to
            subject = query.subject
            body_ = query.body
            return
        }
        if intent.mode == .gribSpec {
            let draft = CatalogRequest.saildocsGRIB(intent.mid)
            to = draft.to.joined(separator: ", ")
            subject = draft.subject
            body_ = draft.body
            return
        }

        guard let message = store.message(withMID: intent.mid) else { return }

        if intent.mode == .editDraft {
            to = message.to.map(\.description).joined(separator: ", ")
            cc = message.cc.map(\.description).joined(separator: ", ")
            subject = message.subject
            body_ = message.bodyText
            attachments = message.files.map {
                ComposeAttachment(originalName: $0.name, originalData: $0.data)
            }
            draftMID = intent.mid
            return
        }

        let draft: MessageDraft =
            switch intent.mode {
            case .reply: message.replyDraft(mycall: mycall)
            case .replyAll: message.replyDraft(mycall: mycall, all: true)
            // Die Abfrage-Modi kehren oben zurück und erreichen diesen Switch nie.
            case .forward, .editDraft, .catalog, .savedQuery, .gribSpec: message.forwardDraft()
            }
        to = draft.to.joined(separator: ", ")
        cc = draft.cc.joined(separator: ", ")
        subject = draft.subject
        body_ = draft.body
        attachments = draft.attachments.map {
            ComposeAttachment(originalName: $0.name, originalData: $0.data)
        }
    }

    /// Picker next to a recipient field: favorites first, then the
    /// rest — each address of a contact is one entry. Hidden while
    /// there are no contacts.
    @ViewBuilder
    private func contactsMenu(into field: Binding<String>, help: String) -> some View {
        if !contacts.contacts.isEmpty {
            Menu {
                ForEach(contacts.sorted.filter(\.isFavorite)) { contact in
                    contactEntry(contact, into: field)
                }
                if contacts.contacts.contains(where: \.isFavorite) {
                    Divider()
                }
                ForEach(contacts.sorted.filter { !$0.isFavorite }) { contact in
                    contactEntry(contact, into: field)
                }
            } label: {
                Image(systemName: "person.crop.circle.badge.plus")
            }
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)
            .fixedSize()
            .help(help)
        }
    }

    /// One contacts-menu entry: a plain button for a single address,
    /// a submenu when the contact has several.
    @ViewBuilder
    private func contactEntry(_ contact: Contact, into field: Binding<String>) -> some View {
        let addresses = contact.allAddresses
        if addresses.count == 1, let only = addresses.first {
            Button("\(contact.displayName) — \(only)") {
                insertRecipient(only, into: field)
            }
        } else if addresses.count > 1 {
            Menu(contact.displayName) {
                ForEach(addresses, id: \.self) { address in
                    Button(address) {
                        insertRecipient(address, into: field)
                    }
                }
            }
        }
    }

    /// Appends an address to the given field (comma-separated),
    /// skipping addresses that are already there.
    private func insertRecipient(_ address: String, into field: Binding<String>) {
        let existing = field.wrappedValue.split(whereSeparator: { ",;".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !existing.contains(where: { $0.caseInsensitiveCompare(address) == .orderedSame })
        else { return }
        let trimmed = field.wrappedValue.trimmingCharacters(in: .whitespaces)
        field.wrappedValue = trimmed.isEmpty ? address : "\(trimmed), \(address)"
    }

    /// Puts a signature at the end of the body; a previously inserted
    /// signature is replaced instead of stacked.
    private func apply(_ signature: Signature) {
        let text = signature.text.trimmingCharacters(in: .newlines)
        guard !text.isEmpty else { return }
        if let applied = appliedSignature, body_.hasSuffix(applied) {
            body_.removeLast(applied.count)
            body_ = body_.trimmingCharacters(in: .newlines)
        }
        body_ = body_.isEmpty ? "\n\n\(text)" : "\(body_)\n\n\(text)"
        appliedSignature = text
    }

    private func saveAsQuery() {
        queries.add(name: queryName, to: to, subject: subject, body: body_)
        savingQuery = false
    }

    private func queueMessage() {
        Task {
            do {
                try await store.compose(
                    mycall: mycall, to: to, cc: cc, subject: subject,
                    body: body_, attachments: attachments.map(\.file))
                // The message is queued — its draft copy is obsolete.
                if let draftMID {
                    store.deleteDraft(mid: draftMID)
                }
                dismiss()
            } catch let error as WinlinkError {
                errorMessage = describe(error)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func saveDraft() {
        do {
            draftMID = try store.saveDraft(
                mid: draftMID, mycall: mycall, to: to, cc: cc,
                subject: subject, body: body_, attachments: attachments.map(\.file))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addAttachments(from result: Result<[URL], any Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: url) {
                let name = url.lastPathComponent
                attachments.append(
                    ComposeAttachment(
                        originalName: name, originalData: data,
                        optimized: optimizedImage(name: name, data: data)))
            }
        }
    }

    /// Optimierte JPEG-Fassung eines Bild-Anhangs gemäss Ziel-Setting;
    /// nil bei Nicht-Bildern, «Original» oder wenn nichts zu tun ist.
    private func optimizedImage(name: String, data: Data) -> B2File? {
        guard let targetBytes = settings.imageAttachmentTarget.targetBytes,
            let result = ImageAttachmentOptimizer.optimize(data, targetBytes: targetBytes),
            result.data != data
        else { return nil }
        return B2File(
            name: ImageAttachmentOptimizer.optimizedName(for: name), data: result.data)
    }

    private func describe(_ error: WinlinkError) -> String {
        if case .validation(let field, let reason) = error {
            switch (field, reason) {
            case ("To/Cc", _): return String(localized: "Bitte mindestens einen Empfänger angeben.")
            case ("Subject", "Empty subject"): return String(localized: "Bitte einen Betreff angeben.")
            case ("Subject", _): return String(localized: "Der Betreff ist zu lang (max. 128 Zeichen).")
            case ("Body", _): return String(localized: "Die Nachricht braucht einen Text.")
            default: return String(localized: "Ungültige Nachricht: \(field) — \(reason)")
            }
        }
        return String(describing: error)
    }
}

/// Eingaben für einzeilige Felder (An, Cc, Betreff) von dem befreien, was
/// beim Einfügen aus der Zwischenablage mitkommt.
enum SingleLineInput {
    /// Leerraum am Anfang fällt weg, Umbrüche im Text werden zu einem
    /// Leerzeichen, Leerraum am Ende schrumpft auf höchstens ein Leerzeichen.
    ///
    /// Der Anlass (2026-11-13): eine aus dem Terminal kopierte Zeile bringt
    /// hunderte Leerzeichen am Ende mit. Das Feld rollt dann ans Ende und
    /// sieht leer aus, obwohl der Text im Fenstertitel steht. Ein einzelnes
    /// Leerzeichen am Ende bleibt, sonst liesse sich beim Tippen kein Wort
    /// anhängen.
    static func clean(_ text: String) -> String {
        let parts = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var result = parts.joined(separator: " ")
        if !result.isEmpty, let last = text.last, last.isWhitespace, !last.isNewline {
            result += " "
        }
        return result
    }
}

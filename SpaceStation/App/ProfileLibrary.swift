// Local profile library — Space Station's "inactive configs" rail: profiles kept on this Mac (not on the pad),
// which you can load into the editor and Apply to any of the four slots, rename, duplicate, export/import
// as files. Stored as raw 790-byte blobs + a JSON index in Application Support.
//
// Not done (yet): SS4's share codes. Its payload is the hex-dash serialisation of the *protobuf* profile bean
// (`ControllerMappingConfigBean`), not the device blob, so exchanging codes with SS4 needs the bean ↔ blob
// conversion (MappingConfigParser) — see docs/ss4-gap-analysis.md.

import SwiftUI
import UniformTypeIdentifiers
import FlydigiKit

struct SavedProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var date: Date
    var file: String                 // "<uuid>.bin" next to the index
}

@MainActor @Observable
final class ProfileLibrary {
    private(set) var entries: [SavedProfile] = []
    var lastError: String?

    private static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Space Station/profiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private static var index: URL { dir.appendingPathComponent("index.json") }

    init() {
        if let d = try? Data(contentsOf: Self.index), let e = try? JSONDecoder().decode([SavedProfile].self, from: d) { entries = e }
    }
    private func persist() {
        do { try JSONEncoder().encode(entries).write(to: Self.index) } catch { lastError = "\(error)" }
    }

    func bytes(of p: SavedProfile) -> [UInt8]? { (try? Data(contentsOf: Self.dir.appendingPathComponent(p.file))).map { [UInt8]($0) } }
    func config(of p: SavedProfile) -> GamepadConfig? { bytes(of: p).flatMap { GamepadConfig(bytes: $0) } }

    @discardableResult
    func save(_ config: GamepadConfig, title: String) -> SavedProfile? {
        let p = SavedProfile(title: title.isEmpty ? String(localized: "Profile") : title, date: Date(), file: "\(UUID().uuidString).bin")
        do { try Data(config.bytes).write(to: Self.dir.appendingPathComponent(p.file)) } catch { lastError = "\(error)"; return nil }
        entries.insert(p, at: 0); persist()
        return p
    }
    func rename(_ p: SavedProfile, to title: String) {
        guard let i = entries.firstIndex(of: p) else { return }
        entries[i].title = String(title.prefix(10)); persist()
    }
    func duplicate(_ p: SavedProfile) {
        guard let c = config(of: p) else { return }
        save(c, title: String((p.title + " 2").prefix(10)))
    }
    func delete(_ p: SavedProfile) {
        try? FileManager.default.removeItem(at: Self.dir.appendingPathComponent(p.file))
        entries.removeAll { $0.id == p.id }; persist()
    }
    func move(_ p: SavedProfile, up: Bool) {
        guard let i = entries.firstIndex(of: p) else { return }
        let j = up ? i - 1 : i + 1
        guard entries.indices.contains(j) else { return }
        entries.swapAt(i, j); persist()
    }

    /// `.fdgprofile` = the raw 790-byte blob; the title travels inside it (bytes 770…789).
    func export(_ p: SavedProfile, to url: URL) {
        guard let b = bytes(of: p) else { return }
        do { try Data(b).write(to: url) } catch { lastError = "\(error)" }
    }
    func importFile(_ url: URL) {
        guard let d = try? Data(contentsOf: url), d.count == 790, let c = GamepadConfig(bytes: [UInt8](d)) else {
            lastError = String(localized: "Not a Space Station for Mac profile (expected a 790-byte .fdgprofile)."); return
        }
        save(c, title: c.title.isEmpty ? url.deletingPathExtension().lastPathComponent : c.title)
    }
}

extension UTType {
    static let fdgProfile = UTType(exportedAs: "com.uiltonlopes.spacestation.profile", conformingTo: .data)
}

/// Sheet: the library list with load / save / rename / duplicate / export / import / delete.
struct ProfileLibrarySheet: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(ProfileLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: SavedProfile?
    @State private var newTitle = ""
    @State private var exporting: SavedProfile?
    @State private var importing = false
    @State private var confirmDelete: SavedProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saved profiles").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    Text("Profiles kept on this Mac. Load one into the editor, then Apply to write it to the selected slot.").font(.system(size: 12)).foregroundStyle(SS.n300)
                }
                Spacer()
                GhostButton(title: "Import…", icon: "square.and.arrow.down") { importing = true }
                PrimaryButton(title: "Save current profile", icon: "plus", enabled: profiles.draft != nil) {
                    if let d = profiles.draft { library.save(d, title: d.title.isEmpty ? "Slot \(profiles.activeSlot + 1)" : d.title) }
                }
            }
            if library.entries.isEmpty {
                Text("Nothing saved yet. “Save current profile” keeps a copy of what is in the editor.").font(.system(size: 12)).foregroundStyle(SS.n400).padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(library.entries) { p in row(p) }
                    }
                }
                .frame(maxHeight: 360)
            }
            if let e = library.lastError { Text(e).font(.system(size: 12)).foregroundStyle(SS.red) }
            HStack { Spacer(); GhostButton(title: "Close") { dismiss() } }
        }
        .padding(20).frame(width: 640)
        .background(SS.n800)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.fdgProfile, .data]) { if case let .success(u) = $0 { library.importFile(u) } }
        .fileExporter(isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
                      document: exporting.flatMap { p in library.bytes(of: p).map { BlobDocument(bytes: $0) } },
                      contentType: .fdgProfile, defaultFilename: (exporting?.title ?? "profile") + ".fdgprofile") { _ in exporting = nil }
        .confirmationDialog("Delete this saved profile?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Delete", role: .destructive) { if let p = confirmDelete { library.delete(p) }; confirmDelete = nil }
        }
        .popover(item: $renaming) { p in
            VStack(alignment: .leading, spacing: 10) {
                Text("Profile name (up to 10 characters)").font(.system(size: 12))
                TextField("Name", text: $newTitle).textFieldStyle(.roundedBorder).frame(width: 220)
                    .onChange(of: newTitle) { _, v in if v.count > 10 { newTitle = String(v.prefix(10)) } }
                    .onSubmit { library.rename(p, to: newTitle); renaming = nil }
                HStack { Spacer(); Button("Save") { library.rename(p, to: newTitle); renaming = nil }.keyboardShortcut(.defaultAction) }
            }
            .padding(14)
        }
    }

    private func row(_ p: SavedProfile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text").foregroundStyle(SS.n300)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                Text(p.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(SS.n400)
            }
            Spacer()
            GhostButton(title: "Load into editor", icon: "arrow.down.doc") {
                if var c = library.config(of: p) { c.title = p.title; profiles.draft = c; dismiss() }
            }
            Menu {
                Button("Rename…") { newTitle = p.title; renaming = p }
                Button("Duplicate") { library.duplicate(p) }
                Button("Export…") { exporting = p }
                Divider()
                Button("Move up") { library.move(p, up: true) }
                Button("Move down") { library.move(p, up: false) }
                Divider()
                Button("Delete…", role: .destructive) { confirmDelete = p }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 15)).foregroundStyle(SS.n300).frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        }
        .padding(.horizontal, 12).frame(height: 48)
        .background(SS.n700, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Minimal FileDocument for exporting a raw blob.
struct BlobDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.fdgProfile, .data] }
    var bytes: [UInt8]
    init(bytes: [UInt8]) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws { bytes = [UInt8](configuration.file.regularFileContents ?? Data()) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(bytes)) }
}

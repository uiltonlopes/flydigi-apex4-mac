// Local macro library — Space Station's "local macro configs": macros kept on this Mac, independent of the
// profile slots. Save one from a profile, add it to any profile bound to any free button, rename, duplicate,
// export/import as `.fdgmacro` (JSON). SS4 share codes for macros (decimal-dash bytes of its protobuf
// MacroItem) are not interoperable yet — same reason as profiles, see docs/ss4-gap-analysis.md.

import SwiftUI
import UniformTypeIdentifiers
import FlydigiKit

struct SavedMacro: Codable, Identifiable, Hashable {
    struct Step: Codable, Hashable { var durationMs: Int; var key: UInt8; var event: UInt8 }
    var id = UUID()
    var name: String
    var date: Date
    var enable: UInt8
    var steps: [Step]

    init(name: String, macro: GamepadConfig.Macro) {
        self.name = name; date = Date(); enable = macro.enable.rawValue
        steps = macro.actions.map { .init(durationMs: $0.durationMs, key: $0.key, event: $0.event.rawValue) }
    }
    /// Back to a slot macro, bound to `key`.
    func macro(for key: ControllerKey) -> GamepadConfig.Macro {
        let actions = steps.map { GamepadConfig.MacroAction(durationMs: $0.durationMs, key: $0.key, event: .init(rawValue: $0.event) ?? .press) }
        return .init(key: key.rawValue, count: actions.count, enable: .init(rawValue: enable) ?? .once, actions: actions)
    }
}

@MainActor @Observable
final class MacroLibrary {
    private(set) var entries: [SavedMacro] = []
    var lastError: String?
    private static var file: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Space Station", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("macros.json")
    }
    init() { if let d = try? Data(contentsOf: Self.file), let e = try? JSONDecoder().decode([SavedMacro].self, from: d) { entries = e } }
    private func persist() { do { try JSONEncoder().encode(entries).write(to: Self.file) } catch { lastError = "\(error)" } }

    func save(_ m: GamepadConfig.Macro, name: String) { entries.insert(SavedMacro(name: name, macro: m), at: 0); persist() }
    func rename(_ e: SavedMacro, to name: String) { if let i = entries.firstIndex(of: e) { entries[i].name = name; persist() } }
    func duplicate(_ e: SavedMacro) { var c = e; c.id = UUID(); c.name = e.name + " 2"; c.date = Date(); entries.insert(c, at: 0); persist() }
    func delete(_ e: SavedMacro) { entries.removeAll { $0.id == e.id }; persist() }
    func exportData(_ e: SavedMacro) -> Data? { try? JSONEncoder().encode(e) }
    func importFile(_ url: URL) {
        guard let d = try? Data(contentsOf: url), var e = try? JSONDecoder().decode(SavedMacro.self, from: d) else {
            lastError = String(localized: "Not a Space Station for Mac macro (.fdgmacro)."); return
        }
        e.id = UUID(); entries.insert(e, at: 0); persist()
    }
}

extension UTType {
    static let fdgMacro = UTType(exportedAs: "com.uiltonlopes.spacestation.macro", conformingTo: .json)
}

struct MacroLibrarySheet: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(MacroLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    /// Called with the index of the macro added to the profile, so the page can select it.
    var onAdded: (Int) -> Void = { _ in }
    @State private var renaming: SavedMacro?
    @State private var newName = ""
    @State private var exporting: SavedMacro?
    @State private var importing = false

    private var freeKeys: [ControllerKey] {
        Apex4Render.mappableKeys.filter { k in !(profiles.draft?.macros.contains { $0.key == k.rawValue } ?? false) }
    }
    private var full: Bool { (profiles.draft?.macros.count ?? 0) >= profiles.maxMacros }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Macro library").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    Text("Macros kept on this Mac. Add one to the current profile and pick the button that runs it.").font(.system(size: 12)).foregroundStyle(SS.n300)
                }
                Spacer()
                GhostButton(title: "Import…", icon: "square.and.arrow.down") { importing = true }
            }
            if library.entries.isEmpty {
                Text("Nothing saved yet. Right-click a macro in a profile and choose “Save to library”.").font(.system(size: 12)).foregroundStyle(SS.n400).padding(.vertical, 20)
            } else {
                ScrollView { VStack(spacing: 6) { ForEach(library.entries) { e in row(e) } } }.frame(maxHeight: 360)
            }
            if full { Text("This profile already has the maximum number of macros.").font(.system(size: 12)).foregroundStyle(SS.yellow) }
            if let e = library.lastError { Text(e).font(.system(size: 12)).foregroundStyle(SS.red) }
            HStack { Spacer(); GhostButton(title: "Close") { dismiss() } }
        }
        .padding(20).frame(width: 640).background(SS.n800)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.fdgMacro, .json]) { if case let .success(u) = $0 { library.importFile(u) } }
        .fileExporter(isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
                      document: exporting.flatMap { e in library.exportData(e).map { BlobDocument(bytes: [UInt8]($0)) } },
                      contentType: .fdgMacro, defaultFilename: (exporting?.name ?? "macro") + ".fdgmacro") { _ in exporting = nil }
        .popover(item: $renaming) { e in
            VStack(alignment: .leading, spacing: 10) {
                Text("Macro name").font(.system(size: 12))
                TextField("Name", text: $newName).textFieldStyle(.roundedBorder).frame(width: 220).onSubmit { library.rename(e, to: newName); renaming = nil }
                HStack { Spacer(); Button("Save") { library.rename(e, to: newName); renaming = nil }.keyboardShortcut(.defaultAction) }
            }
            .padding(14)
        }
    }

    private func row(_ e: SavedMacro) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "list.number").foregroundStyle(SS.n300)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                Text("\(e.steps.count) steps · \(e.date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 11)).foregroundStyle(SS.n400)
            }
            Spacer()
            Menu {
                ForEach(freeKeys, id: \.self) { k in
                    Button(String(describing: k)) {
                        guard let i = profiles.addMacro(for: k) else { return }
                        let m = e.macro(for: k)
                        profiles.updateMacro(at: i) { $0.actions = m.actions; $0.enable = m.enable }
                        onAdded(i); dismiss()
                    }
                }
            } label: {
                HStack(spacing: 6) { Image(systemName: "plus"); Text("Add to profile") }.font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white).padding(.horizontal, 10).frame(height: 28)
                    .background(full || freeKeys.isEmpty ? SS.n500 : SS.brand500, in: RoundedRectangle(cornerRadius: 6, style: .continuous)).contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).disabled(full || freeKeys.isEmpty)
            Menu {
                Button("Rename…") { newName = e.name; renaming = e }
                Button("Duplicate") { library.duplicate(e) }
                Button("Export…") { exporting = e }
                Divider()
                Button("Delete", role: .destructive) { library.delete(e) }
            } label: { Image(systemName: "ellipsis.circle").font(.system(size: 15)).foregroundStyle(SS.n300).frame(width: 24, height: 24).contentShape(Rectangle()) }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        }
        .padding(.horizontal, 12).frame(height: 48)
        .background(SS.n700, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

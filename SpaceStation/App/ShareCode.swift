// Space Station share codes: publish the profile being edited (plus its lighting) to Flydigi's share service and
// get the short code Space Station users exchange; or type a code in and get the profile into the local library
// and the editor. The payload is Space Station's own protobuf bean (FlydigiKit/SS4Profile.swift), so codes work
// in both directions with the Windows app.

import AppKit
import SwiftUI
import FlydigiKit
import FlydigiTransport

struct ShareCodeSheet: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(ControllerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var code: String?
    @State private var error: String?
    @State private var working = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Share as code").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            Text("Uploads this profile — buttons, sticks, triggers, gyro, vibration, macros and lighting — to Flydigi's share service and returns a code any Space Station user (Windows or Mac) can import. The profile is public to anyone who has the code.")
                .font(.system(size: 12)).foregroundStyle(SS.n300)
            if let code {
                HStack(spacing: 10) {
                    Text(code).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(SS.brand500).textSelection(.enabled)
                    GhostButton(title: copied ? "Copied" : "Copy", icon: copied ? "checkmark" : "doc.on.doc") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string); copied = true
                    }
                }
                .padding(14).frame(maxWidth: .infinity).background(SS.n700, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if working {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Uploading…").font(.system(size: 12)).foregroundStyle(SS.n300) }
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(SS.red) }
            HStack {
                if code == nil { PrimaryButton(title: "Get a share code", icon: "square.and.arrow.up", enabled: !working && profiles.draft != nil) { upload() } }
                Spacer()
                GhostButton(title: code == nil ? "Cancel" : "Done") { dismiss() }
            }
        }
        .padding(20).frame(width: 520).background(SS.n800)
    }

    private func upload() {
        guard let cfg = profiles.draft else { return }
        working = true; error = nil
        var bean = SS4Profile(blob: cfg.bytes)
        if let led = model.led { bean.led = SS4Profile.Led(led: led) }
        let name = cfg.title.isEmpty ? String(localized: "Profile") : cfg.title
        let s = bean.shareString
        Task {
            let r: Result<String, Error> = await Task.detached { Result { try FlydigiAPI.shareUpload(name: name, shareString: s) } }.value
            working = false
            switch r { case .success(let c): code = c; case .failure(let e): error = "\(e)" }
        }
    }
}

struct ImportCodeSheet: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(ProfileLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var working = false
    @State private var error: String?
    @State private var imported: (title: String, config: GamepadConfig)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import from code").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            Text("Paste a Space Station share code. The profile is saved to your library; you can also load it into the editor and apply it to a slot.")
                .font(.system(size: 12)).foregroundStyle(SS.n300)
            HStack(spacing: 8) {
                TextField("Share code", text: $code).textFieldStyle(.roundedBorder).font(.system(size: 14, design: .monospaced)).onSubmit { fetch() }
                PrimaryButton(title: working ? "Fetching…" : "Import", icon: "square.and.arrow.down", enabled: !working && !code.trimmingCharacters(in: .whitespaces).isEmpty) { fetch() }
            }
            if let imported {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Imported “\(imported.title)” into the library.").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Text("\(imported.config.keys.filter { $0.value != .identity }.count) remapped keys · \(imported.config.macros.count) macros · triggers \(imported.config.leftTrigger.adapterType == 0 ? "normal" : "ForceAdapt") / \(imported.config.rightTrigger.adapterType == 0 ? "normal" : "ForceAdapt")")
                        .font(.system(size: 12)).foregroundStyle(SS.n300)
                    HStack(spacing: 8) {
                        PrimaryButton(title: "Load into editor", icon: "arrow.down.doc") { var c = imported.config; c.title = String(imported.title.prefix(10)); profiles.draft = c; dismiss() }
                        GhostButton(title: "Keep in library only") { dismiss() }
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(SS.n700, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(SS.red) }
            HStack { Spacer(); GhostButton(title: imported == nil ? "Cancel" : "Done") { dismiss() } }
        }
        .padding(20).frame(width: 520).background(SS.n800)
    }

    private func fetch() {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return }
        working = true; error = nil
        Task {
            let r: Result<(String, SS4Profile), Error> = await Task.detached {
                Result {
                    if let bean = SS4Profile(shareString: c) { return (bean.title, bean) }      // a raw "0A-1B-…" string pasted directly
                    let d = try FlydigiAPI.shareDownload(code: c)
                    guard let bean = SS4Profile(shareString: d.shareString) else { throw FlydigiAPI.ShareError(message: String(localized: "The reply is not a controller profile.")) }
                    return (d.name.isEmpty ? bean.title : d.name, bean)
                }
            }.value
            working = false
            switch r {
            case .success(let (name, bean)):
                guard var cfg = GamepadConfig(bytes: bean.blob()) else { error = String(localized: "The profile could not be converted."); return }
                let title = (bean.title.isEmpty ? name : bean.title)
                if cfg.title.isEmpty { cfg.title = String(title.prefix(10)) }
                library.save(cfg, title: String(title.prefix(10)))
                imported = (title, cfg)
            case .failure(let e): error = "\(e)"
            }
        }
    }
}

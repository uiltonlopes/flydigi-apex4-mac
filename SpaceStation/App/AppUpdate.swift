// App self-update: asks GitHub for the latest release of this repository and offers its DMG. No framework, no
// background installer — the download opens in the browser (or the DMG directly) and the user drags the app
// over the old one, exactly as on first install. Checked once a day on launch and on demand from Settings.

import AppKit
import Foundation
import Observation
import FlydigiKit

@MainActor @Observable
final class AppUpdateChecker {
    struct Release: Equatable { var version: String; var page: URL; var dmg: URL?; var notes: String; var date: Date? }

    private(set) var latest: Release?          // newer than the running app, else nil
    private(set) var checked = false
    private(set) var checking = false
    private(set) var lastError: String?

    nonisolated static let repo = "uiltonlopes/flydigi-space-station-mac"
    static var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    /// Once a day is plenty; `force` for the Settings button.
    func checkIfDue(force: Bool = false) async {
        let last = UserDefaults.standard.object(forKey: "appUpdateCheckedAt") as? Date ?? .distantPast
        guard force || Date().timeIntervalSince(last) > 24 * 3600 else { return }
        await check()
    }

    func check() async {
        guard !checking else { return }
        checking = true; lastError = nil
        defer { checking = false; checked = true }
        let r: Result<Release?, Error> = await Task.detached {
            do {
                var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(AppUpdateChecker.repo)/releases/latest")!)
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                req.timeoutInterval = 15
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse else { return .success(nil) }
                if http.statusCode == 404 { return .success(nil) }              // no release published yet
                guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
                struct Asset: Decodable { let name: String; let browser_download_url: URL }
                struct GH: Decodable { let tag_name: String; let html_url: URL; let body: String?; let published_at: String?; let assets: [Asset]; let draft: Bool; let prerelease: Bool }
                let gh = try JSONDecoder().decode(GH.self, from: data)
                guard !gh.draft else { return .success(nil) }
                let version = gh.tag_name.hasPrefix("v") ? String(gh.tag_name.dropFirst()) : gh.tag_name
                let date = gh.published_at.flatMap { ISO8601DateFormatter().date(from: $0) }
                return .success(Release(version: version, page: gh.html_url, dmg: gh.assets.first { $0.name.hasSuffix(".dmg") }?.browser_download_url, notes: gh.body ?? "", date: date))
            } catch { return .failure(error) }
        }.value
        UserDefaults.standard.set(Date(), forKey: "appUpdateCheckedAt")
        switch r {
        case .success(let rel):
            if let rel, FirmwareVersion.isNewer(rel.version, than: Self.currentVersion) { latest = rel } else { latest = nil }
        case .failure(let e): lastError = "\(e)"
        }
    }

    /// Opens the DMG download (Safari saves it to Downloads) or the release page.
    func download() { if let r = latest { NSWorkspace.shared.open(r.dmg ?? r.page) } }
}

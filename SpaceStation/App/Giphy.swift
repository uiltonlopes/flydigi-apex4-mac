// GIPHY search for the Screen page, and the local record of what was last sent to the controller's LCD.
// The pad has no command to read its screen back (docs/protocol.md §6), so "on the controller" is what this
// Mac sent last — or the factory animation Space Station ships for the model when nothing was sent yet.

import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import FlydigiKit
import FlydigiTransport

// MARK: - GIPHY

enum Giphy {
    /// Beta key registered for this app. Beta keys are rate-limited (~100 searches/hour, shared by everyone
    /// on this build); Settings lets the user paste their own.
    static let sharedKey = "BBKXk3D61s16peHOlBsdIs5o5kvhxCym"
    static let keyDefaultsKey = "giphyApiKey"
    static var apiKey: String {
        let k = UserDefaults.standard.string(forKey: keyDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return k.isEmpty ? sharedKey : k
    }

    struct Gif: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let still: URL?        // small static thumbnail for the grid
        let download: URL      // 200 px-high GIF — plenty for a 160 × 80 screen
    }

    enum Failure: LocalizedError {
        case http(Int), badResponse
        var errorDescription: String? {
            switch self {
            case .http(429): return "GIPHY rate limit reached — paste your own API key in Settings."
            case .http(let c): return "GIPHY answered HTTP \(c)."
            case .badResponse: return "GIPHY returned an unexpected response."
            }
        }
    }

    /// Search, or trending when the query is empty.
    static func search(_ query: String, limit: Int = 30) async throws -> [Gif] {
        let q = query.trimmingCharacters(in: .whitespaces)
        var c = URLComponents(string: q.isEmpty ? "https://api.giphy.com/v1/gifs/trending" : "https://api.giphy.com/v1/gifs/search")!
        var items = [URLQueryItem(name: "api_key", value: apiKey), URLQueryItem(name: "limit", value: "\(limit)"),
                     URLQueryItem(name: "rating", value: "pg-13")]     // default bundle: it is the one that carries the *_still renditions
        if !q.isEmpty {
            items.append(URLQueryItem(name: "q", value: q))
            items.append(URLQueryItem(name: "lang", value: Locale.current.language.languageCode?.identifier ?? "en"))
        }
        c.queryItems = items
        let (data, resp) = try await URLSession.shared.data(from: c.url!)
        guard let http = resp as? HTTPURLResponse else { throw Failure.badResponse }
        guard http.statusCode == 200 else { throw Failure.http(http.statusCode) }
        let r = try JSONDecoder().decode(Response.self, from: data)
        return r.data.compactMap { item in
            let img = item.images
            guard let dl = img["fixed_height"]?.url ?? img["downsized"]?.url ?? img["original"]?.url, let du = URL(string: dl) else { return nil }
            let still = (img["fixed_height_small_still"]?.url ?? img["fixed_width_still"]?.url ?? img["480w_still"]?.url ?? img["fixed_height_small"]?.url).flatMap { URL(string: $0) }
            return Gif(id: item.id, title: item.title.isEmpty ? "GIPHY \(item.id)" : item.title, still: still, download: du)
        }
    }

    /// Downloads the GIF to a temporary file the screen editor can open.
    static func download(_ gif: Gif) async throws -> URL {
        let (data, resp) = try await URLSession.shared.data(from: gif.download)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { throw Failure.badResponse }
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent("giphy-\(gif.id).gif")
        try data.write(to: dst)
        return dst
    }

    private struct Response: Decodable { let data: [Item] }
    private struct Item: Decodable { let id: String; let title: String; let images: [String: Rendition] }
    private struct Rendition: Decodable { let url: String? }
}

// MARK: - What is on the controller

/// Where the animation in the editor came from (kept so the record can say what was sent).
struct ScreenOrigin: Hashable {
    enum Kind: String { case file, flydigi, giphy }
    var name: String
    var kind: Kind
    var url: String?
}

struct ScreenRecord: Codable, Hashable {
    var name: String
    var source: String          // ScreenOrigin.Kind raw value
    var url: String?
    var date: Date
    var frames: Int
    var intervalMs: Int
    var sourceLabel: String {
        switch source {
        case "giphy": return "GIPHY"
        case "flydigi": return String(localized: "Flydigi library")
        default: return String(localized: "local file")
        }
    }
}

enum ScreenStore {
    struct Current: Hashable {
        let gif: URL
        let record: ScreenRecord?      // nil = factory animation
        /// Changes whenever the file content may have changed, so the preview reloads.
        var token: String { record.map { "\($0.date.timeIntervalSince1970)" } ?? gif.lastPathComponent }
    }

    private static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Space Station", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private static var gifURL: URL { dir.appendingPathComponent("screen-current.gif") }
    private static var metaURL: URL { dir.appendingPathComponent("screen-current.json") }

    /// Last upload from this Mac, else the factory animation for the connected variant (84 as fallback).
    static func current(deviceId: UInt8?) -> Current? {
        if let d = try? Data(contentsOf: metaURL), let r = try? JSONDecoder().decode(ScreenRecord.self, from: d),
           FileManager.default.fileExists(atPath: gifURL.path) {
            return Current(gif: gifURL, record: r)
        }
        let id = deviceId.map { Int($0) } ?? 84
        if let u = Bundle.main.url(forResource: "factory-k2-\(id)", withExtension: "gif") ?? Bundle.main.url(forResource: "factory-k2-84", withExtension: "gif") {
            return Current(gif: u, record: nil)
        }
        return nil
    }

    /// Renders the frames exactly as sent (160 × 80, RGB565-quantised) into a GIF next to the record.
    static func save(images: [CGImage], crop: ScreenCrop?, intervalMs: Int, record: ScreenRecord) throws {
        let frames = images.compactMap { ImageLoader.preview($0, crop: crop) }
        guard !frames.isEmpty, let dest = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let delay = Double(max(20, intervalMs)) / 1000
        for f in frames {
            CGImageDestinationAddImage(dest, f, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        try JSONEncoder().encode(record).write(to: metaURL)
    }
}

/// Animated GIF from a file (NSImageView animates GIFs by itself; SwiftUI's Image shows the first frame).
struct AnimatedGIF: NSViewRepresentable {
    let url: URL
    let token: String
    final class GIFView: NSImageView { var token: String? }
    func makeNSView(context: Context) -> GIFView {
        let v = GIFView()
        v.imageScaling = .scaleProportionallyUpOrDown
        v.animates = true
        v.imageFrameStyle = .none
        return v
    }
    func updateNSView(_ v: GIFView, context: Context) {
        guard v.token != token else { return }
        v.token = token
        v.image = NSImage(contentsOf: url)
        v.animates = true
    }
}

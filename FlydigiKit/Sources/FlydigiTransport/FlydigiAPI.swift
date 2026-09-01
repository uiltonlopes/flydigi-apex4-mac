// Flydigi's public web API (the same endpoints Space Station 4 calls; no authentication).
// See docs/spacestation4-analysis.md §7. Used for the online GIF library, per-game trigger presets and
// firmware-availability notices. Nothing here writes to the controller.

import Foundation

public enum FlydigiAPI {
    public static let base = URL(string: "https://api.flydigi.com/pc")!
    public static let deviceCode = "k2"            // Apex 4 family
    /// Sent as `appversion`; Space Station 4.2.2.3 is what the servers currently see.
    public static let appVersion = "4.2.2.3"

    public struct ScreenPic: Decodable, Sendable, Hashable, Identifiable {
        public let id: Int
        public let type: String            // "gif" | "jpg"
        public let imagePath: URL
        public let title: String
        public let freq: Int               // official frame interval (units: see analysis §7)
        public let cate: String            // "0" | "1" | "2"
        public let isRecomment: Int
        public var isGIF: Bool { type == "gif" }
    }

    public struct GamePreset: Decodable, Sendable, Hashable, Identifiable {
        public let id: Int
        public let gameName: String
        public let enGameName: String
        public let platforms: [String]
        public let processGameNames: [String]
        public let isMod: Int
        public let isVibration: Int
        public let vibType: Int
        public let vibParams: String
        public let vibParamsRight: String?
        public let vibFilter: Int
        public let pwmScal: Int
        public let minFirmwareVersion: String
        public let isPS5: Int
        public let imagePath: URL?
    }

    public struct FirmwareChip: Decodable, Sendable, Hashable {
        public let version: String
        public let url: URL
        public let info: String
        public let min_app_version: String
        public let is_push: Int
    }

    private struct Envelope<T: Decodable>: Decodable { let data: T? }
    private struct FirmwareData: Decodable {
        let device_code: String
        let chip_list: ChipList
        /// `chip_list` is an object when there is something to offer and `[]` when there is not.
        enum ChipList: Decodable {
            case chips([String: FirmwareChip]), none
            init(from decoder: Decoder) throws {
                if let d = try? decoder.singleValueContainer().decode([String: FirmwareChip].self) { self = .chips(d) } else { self = .none }
            }
        }
    }

    // MARK: Calls (synchronous; callers run them off the main thread)

    public static func screenPictures(deviceCode: String = deviceCode) throws -> [ScreenPic] {
        try get("screen_pic/list", query: ["device_code": deviceCode], as: Envelope<[ScreenPic]>.self).data ?? []
    }

    public static func gamePresets(deviceCode: String = deviceCode) throws -> [GamePreset] {
        try get("adapter_trigger/list", query: ["device_code": deviceCode], as: Envelope<[GamePreset]>.self).data ?? []
    }

    /// Returns the chips with a newer firmware than the given versions (`main_chip` for the pad's MCU).
    public static func firmwareUpdates(deviceId: Int = 84, mainChip: String, deviceCode: String = deviceCode) throws -> [String: FirmwareChip] {
        let body: [String: Any] = ["device_code": deviceCode, "device_id": deviceId, "app_version": appVersion, "main_chip": mainChip]
        let env = try post("Update/firmware", json: body, as: Envelope<FirmwareData>.self)
        if case let .chips(c)? = env.data?.chip_list { return c }
        return [:]
    }

    /// Downloads a picture from the library (CDN); the caller feeds it to `ImageLoader`.
    public static func download(_ url: URL) throws -> Data {
        var req = URLRequest(url: url); req.timeoutInterval = 60
        return try perform(req).data
    }

    // MARK: Plumbing

    private static func get<T: Decodable>(_ path: String, query: [String: String], as type: T.Type) throws -> T {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: comps.url!); req.setValue(appVersion, forHTTPHeaderField: "appversion")
        return try JSONDecoder().decode(type, from: try perform(req).data)
    }

    private static func post<T: Decodable>(_ path: String, json: [String: Any], as type: T.Type) throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"; req.httpBody = try JSONSerialization.data(withJSONObject: json)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.setValue(appVersion, forHTTPHeaderField: "appversion")
        return try JSONDecoder().decode(type, from: try perform(req).data)
    }

    private static func perform(_ request: URLRequest) throws -> (data: Data, response: HTTPURLResponse) {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<(Data, HTTPURLResponse), Error> = .failure(URLError(.unknown))
        URLSession.shared.dataTask(with: request) { data, resp, err in
            if let err { result = .failure(err) }
            else if let data, let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) { result = .success((data, http)) }
            else { result = .failure(URLError(.badServerResponse)) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 60)
        return try result.get()
    }
}

import Foundation
import Observation
import CryptoKit
import AFFoundation

// MARK: Audio URLs

public extension SourceClient {
    /// Resolves (and caches for 10 minutes) the streaming URL of a track.
    func streamURL(trackId: String) async throws -> URL {
        if let cached = SourceCatalog.shared.cachedURL(trackId, download: false) { return cached }
        guard let song = SourceCatalog.shared.song(trackId) else { throw ClientError.invalidResponse }

        let url = try await ModuleHost.shared.resolve(song, download: false)
        SourceCatalog.shared.cache(url, for: trackId, download: false)
        return url
    }

    /// Call before `DownloadManager` starts a task: downloads need their URL synchronously.
    func prepareDownload(trackId: String) async {
        guard SourceCatalog.shared.cachedURL(trackId, download: true) == nil,
              let song = SourceCatalog.shared.song(trackId),
              let url = try? await ModuleHost.shared.resolve(song, download: true) else { return }
        SourceCatalog.shared.cache(url, for: trackId, download: true)
    }

    func knownDownloadURL(trackId: String) -> URL? {
        if let cached = SourceCatalog.shared.cachedURL(trackId, download: true) { return cached }
        guard let song = SourceCatalog.shared.song(trackId), !song.needsDownloadResolve, let s = song.url else { return nil }
        return URL(string: s)
    }

    func knownStreamURL(trackId: String) -> URL? {
        if let cached = SourceCatalog.shared.cachedURL(trackId, download: false) { return cached }
        guard let song = SourceCatalog.shared.song(trackId), !song.needsResolve, let s = song.url else { return nil }
        return URL(string: s)
    }
}

// MARK: Lyrics

public extension SourceClient {
    /// Module `lyrics(song)` may return an LRC string or [{ time, text }].
    func lyrics(trackId identifier: String) async throws -> Track.Lyrics {
        guard let song = SourceCatalog.shared.song(identifier) else { throw ClientError.invalidResponse }
        let rawObject = song.raw.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }
        let result = try await ModuleHost.shared.call(moduleID: song.moduleID, "lyrics", rawObject)

        var lyrics: Track.Lyrics = [0: nil]

        if let text = result as? String {
            for line in text.split(whereSeparator: \.isNewline) {
                guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { continue }
                let stamp = line[line.index(after: line.startIndex)..<close].split(separator: ":")
                guard stamp.count == 2, let minutes = Double(stamp[0]), let seconds = Double(stamp[1]) else { continue }

                let content = line[line.index(after: close)...].trimmingCharacters(in: .whitespacesAndNewlines)
                let text: String? = content.isEmpty ? nil : content
                lyrics[minutes * 60 + seconds] = text
            }
        } else if let lines = result as? [[String: Any]] {
            for line in lines {
                guard let time = (line["time"] as? NSNumber ?? line["start"] as? NSNumber)?.doubleValue else { continue }
                let content = (line["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let text: String? = (content?.isEmpty ?? true) ? nil : content
                lyrics[time] = text
            }
        }

        if lyrics.count <= 1 {
            throw ClientError.invalidResponse
        }

        return lyrics
    }

    func mediaInfo(trackId identifier: String) async throws -> Track.MediaInfo {
        throw ClientError.invalidResponse
    }
}

// MARK: Playback reporting (kept on this device only)

public extension SourceClient {
    func playbackStarted(identifier: String, queueIds: [String]) async throws {
        SourceCatalog.shared.played(identifier)
    }

    func progress(identifier: String, position: Double, paused: Bool, repeatMode: RepeatMode, shuffled: Bool, volume: Float) async throws {}

    func playbackStopped(identifier: String, positionSeconds: Double, playSessionId: String?) async throws {}

    static func sessionID(itemId: String, bitrate: Int?) -> String {
        let digest = Insecure.MD5.hash(data: Data("\(itemId)::\(bitrate ?? -1)".utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}

// MARK: Remote control (not part of this app, kept so existing player code compiles)

public extension SourceClient {
    func update(allowRemoteControl: Bool) async throws {}
    func controllableSessions() async -> [Session] { [] }
    func update(sessionId: String, command: PlayStateCommand) async throws {}
    func update(sessionId: String, positionSeconds: Double) async throws {}
    func update(sessionId: String, shuffled: Bool) async throws {}
    func update(sessionId: String, repeatMode: RepeatMode) async throws {}
    func update(sessionId: String, volume: Float) async throws {}
    func play(sessionId: String, tracks: [Track], index: Int) async throws {}
    func queue(sessionId: String, tracks: [Track], queuePosition: PlayCommand) async throws {}
}

@Observable
public final class SourceSocket {
    public internal(set) var connected = false

    private init() {}

    public static let shared = SourceSocket()

    public func connect() {}
    public func beginObservingSessionUpdated(clientId: String) {}
    public func stopObservingSessionUpdated() {}

    public static let disconnectedNotification = NSNotification.Name("io.rfk.ampfin.socket.disconnect")
    public static let playCommandIssuedNotification = NSNotification.Name("io.rfk.ampfin.socket.command.play")
    public static let playStateCommandIssuedNotification = NSNotification.Name("io.rfk.ampfin.socket.command.playState")
    public static let sessionUpdateNotification = NSNotification.Name("io.rfk.ampfin.socket.session.update")
}

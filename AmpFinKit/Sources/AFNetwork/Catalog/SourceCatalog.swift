import Foundation

struct SourceStat: Codable {
    var added: Date
    var lastPlayed: Date?
    var plays: Int
}

struct StoredPlaylist: Codable {
    var id: String
    var name: String
    var trackIDs: [String]
    var created: Date
}

/// Everything modules have shown us, plus the local "library": played/favorited songs, favorites and playlists.
final class SourceCatalog: @unchecked Sendable {
    static let shared = SourceCatalog()

    private let lock = NSLock()
    private var songs: [String: SourceSong] = [:]
    private var seen: [String] = []
    private var stats: [String: SourceStat] = [:]
    private var favorites: Set<String> = []
    private var playlists: [StoredPlaylist] = []
    private var streams: [String: (URL, Date)] = [:]
    private var downloads: [String: (URL, Date)] = [:]
    private let file: URL

    private struct Stored: Codable {
        var songs: [SourceSong]
        var stats: [String: SourceStat]
        var favorites: [String]
        var playlists: [StoredPlaylist]
    }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        file = base.appendingPathComponent("library.json")
        if let data = try? Data(contentsOf: file), let s = try? JSONDecoder().decode(Stored.self, from: data) {
            for song in s.songs { songs[song.id] = song }
            seen = s.songs.map(\.id)
            stats = s.stats
            favorites = Set(s.favorites)
            playlists = s.playlists
        }
    }

    // MARK: Songs

    func ingest(_ list: [SourceSong]) {
        lock.withLock {
            for song in list {
                if songs[song.id] == nil { seen.append(song.id) }
                songs[song.id] = song
            }
            if songs.count > 4000 {
                let keep = keptIDs()
                for id in seen where !keep.contains(id) && songs.count > 3000 { songs[id] = nil }
                seen = seen.filter { songs[$0] != nil }
            }
        }
    }

    func song(_ id: String) -> SourceSong? { lock.withLock { songs[id] } }
    func allSongs() -> [SourceSong] { lock.withLock { seen.compactMap { songs[$0] } } }
    func stat(_ id: String) -> SourceStat? { lock.withLock { stats[id] } }
    func isFavorite(_ id: String) -> Bool { lock.withLock { favorites.contains(id) } }

    /// Songs saved in the library (played, favorited, or added to a playlist).
    func librarySongs() -> [SourceSong] {
        lock.withLock { stats.keys.compactMap { songs[$0] } }
    }

    func favoriteIDs() -> Set<String> { lock.withLock { favorites } }

    // MARK: Mutations

    func played(_ id: String) {
        lock.withLock {
            var s = stats[id] ?? SourceStat(added: .now, lastPlayed: nil, plays: 0)
            s.plays += 1
            s.lastPlayed = .now
            stats[id] = s
        }
        save()
    }

    func setFavorite(_ id: String, _ value: Bool) {
        lock.withLock {
            if value {
                favorites.insert(id)
                if songs[id] != nil, stats[id] == nil { stats[id] = SourceStat(added: .now, lastPlayed: nil, plays: 0) }
            } else {
                favorites.remove(id)
            }
        }
        save()
    }

    func addToLibrary(_ ids: [String]) {
        lock.withLock {
            for id in ids where songs[id] != nil && stats[id] == nil {
                stats[id] = SourceStat(added: .now, lastPlayed: nil, plays: 0)
            }
        }
    }

    // MARK: Playlists

    func allPlaylists() -> [StoredPlaylist] { lock.withLock { playlists } }
    func playlist(_ id: String) -> StoredPlaylist? { lock.withLock { playlists.first { $0.id == id } } }

    func createPlaylist(name: String, trackIDs: [String]) {
        addToLibrary(trackIDs)
        lock.withLock { playlists.append(StoredPlaylist(id: "playlist::" + UUID().uuidString, name: name, trackIDs: trackIDs, created: .now)) }
        save()
    }

    func updatePlaylist(_ id: String, _ change: (inout StoredPlaylist) -> Void) {
        lock.withLock {
            if let i = playlists.firstIndex(where: { $0.id == id }) { change(&playlists[i]) }
        }
        save()
    }

    func deletePlaylist(_ id: String) {
        lock.withLock { playlists.removeAll { $0.id == id } }
        save()
    }

    // MARK: Stream URL cache (10 minutes, links from modules can expire)

    func cachedURL(_ id: String, download: Bool) -> URL? {
        lock.withLock {
            guard let (url, date) = (download ? downloads : streams)[id], Date().timeIntervalSince(date) < 600 else { return nil }
            return url
        }
    }

    func cache(_ url: URL, for id: String, download: Bool) {
        lock.withLock {
            if download { downloads[id] = (url, .now) } else { streams[id] = (url, .now) }
        }
    }

    // MARK: Persistence

    /// Call with the lock held.
    private func keptIDs() -> Set<String> {
        var keep = Set(stats.keys)
        for p in playlists { keep.formUnion(p.trackIDs) }
        for s in songs.values where favorites.contains(s.albumID) || favorites.contains(s.artistID) { keep.insert(s.id) }
        return keep
    }

    private func save() {
        let stored: Stored = lock.withLock {
            let keep = keptIDs()
            return Stored(songs: keep.compactMap { songs[$0] }, stats: stats, favorites: Array(favorites), playlists: playlists)
        }
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: file, options: .atomic)
        }
    }
}

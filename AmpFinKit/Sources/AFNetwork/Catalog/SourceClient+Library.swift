import Foundation
import AFFoundation

public struct SourceShelf: Identifiable {
    public let id = UUID()
    public let title: String
    public let tracks: [Track]
}

// MARK: Module feeds + search

public extension SourceClient {
    /// Home / New / Radio shelves from every module.
    func shelves(_ feed: ModuleHost.Feed) async -> [SourceShelf] {
        let results = await ModuleHost.shared.callAll(feed.rawValue, nil)
        var shelves: [SourceShelf] = []
        var all: [SourceSong] = []

        for (module, raw) in results {
            guard let array = raw as? [[String: Any]] else { continue }
            if array.contains(where: { $0["items"] != nil || $0["songs"] != nil }) {
                for s in array {
                    let items = (s["items"] ?? s["songs"]) as? [[String: Any]] ?? []
                    let songs = items.compactMap { SourceSong(json: $0, module: module) }
                    guard !songs.isEmpty else { continue }
                    all += songs
                    shelves.append(SourceShelf(title: (s["title"] as? String) ?? module.name, tracks: songs.map { track($0) }))
                }
            } else {
                let songs = array.compactMap { SourceSong(json: $0, module: module) }
                guard !songs.isEmpty else { continue }
                all += songs
                shelves.append(SourceShelf(title: module.name, tracks: songs.map { track($0) }))
            }
        }

        SourceCatalog.shared.ingest(all)
        return shelves
    }
}

internal extension SourceClient {
    /// Identical queries within 30 seconds share one module call (search fires tracks, albums and artists at once).
    func searchSongs(_ query: String) async -> [SourceSong] {
        let key = query.lowercased()
        let task: Task<[SourceSong], Never> = cacheLock.withLock {
            if let (date, existing) = searchCache[key], Date().timeIntervalSince(date) < 30 { return existing }
            let created = Task<[SourceSong], Never> {
                let results = await ModuleHost.shared.callAll("search", query)
                var songs: [SourceSong] = []
                for (module, raw) in results {
                    var items = raw as? [[String: Any]] ?? []
                    if items.contains(where: { $0["items"] != nil || $0["songs"] != nil }) {
                        items = items.flatMap { ($0["items"] ?? $0["songs"]) as? [[String: Any]] ?? [] }
                    }
                    songs += items.compactMap { SourceSong(json: $0, module: module) }
                }
                SourceCatalog.shared.ingest(songs)
                return songs
            }
            searchCache[key] = (Date(), created)
            return created
        }
        return await task.value
    }

    func page<T>(_ items: [T], limit: Int, startIndex: Int) -> [T] {
        let start = min(max(startIndex, 0), items.count)
        let end = limit > 0 ? min(start + limit, items.count) : items.count
        return Array(items[start..<end])
    }

    func sorted(_ songs: [SourceSong], by order: ItemSortOrder, ascending: Bool) -> [SourceSong] {
        let catalog = SourceCatalog.shared
        var result: [SourceSong]
        switch order {
            case .name: result = songs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            case .album: result = songs.sorted { $0.albumName.localizedCaseInsensitiveCompare($1.albumName) == .orderedAscending }
            case .albumArtist: result = songs.sorted { $0.albumArtist.localizedCaseInsensitiveCompare($1.albumArtist) == .orderedAscending }
            case .artist: result = songs.sorted { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
            case .added: result = songs.sorted { (catalog.stat($0.id)?.added ?? .distantPast) < (catalog.stat($1.id)?.added ?? .distantPast) }
            case .plays: result = songs.sorted { (catalog.stat($0.id)?.plays ?? 0) < (catalog.stat($1.id)?.plays ?? 0) }
            case .lastPlayed: result = songs.sorted { (catalog.stat($0.id)?.lastPlayed ?? .distantPast) < (catalog.stat($1.id)?.lastPlayed ?? .distantPast) }
            case .released: result = songs.sorted { ($0.released ?? .distantPast) < ($1.released ?? .distantPast) }
            case .runtime: result = songs.sorted { $0.duration < $1.duration }
            case .random: return songs.shuffled()
        }
        return ascending ? result : result.reversed()
    }
}

// MARK: Tracks

public extension SourceClient {
    func tracks(limit: Int, startIndex: Int, sortOrder: ItemSortOrder, ascending: Bool, favoriteOnly: Bool = false, search: String? = nil, coverSize: Cover.CoverSize = .normal) async throws -> ([Track], Int) {
        var songs: [SourceSong]

        if let search, !search.trimmingCharacters(in: .whitespaces).isEmpty {
            songs = await searchSongs(search)
        } else {
            songs = sorted(SourceCatalog.shared.librarySongs(), by: sortOrder, ascending: ascending)
        }
        if favoriteOnly {
            let favorites = SourceCatalog.shared.favoriteIDs()
            songs = songs.filter { favorites.contains($0.id) }
        }

        return (page(songs, limit: limit, startIndex: startIndex).map { track($0) }, songs.count)
    }

    func tracks(instantMixBaseId identifier: String, limit: Int = 200) async throws -> [Track] {
        guard let base = SourceCatalog.shared.song(identifier) else { return [] }

        var candidates = base.artist.isEmpty ? [] : await searchSongs(base.artist)
        if candidates.count < 5 { candidates += SourceCatalog.shared.librarySongs() }

        var seen = Set([identifier])
        let mix = candidates.shuffled().filter { seen.insert($0.id).inserted }
        return Array(mix.prefix(limit)).map { track($0) }
    }

    func tracks(albumId identifier: String) async throws -> [Track] {
        let songs = SourceCatalog.shared.allSongs().enumerated()
            .filter { $0.element.albumID == identifier }
            .sorted { ($0.element.disc, $0.element.index, $0.offset) < ($1.element.disc, $1.element.index, $1.offset) }
            .map(\.element)

        guard !songs.isEmpty else { throw ClientError.invalidResponse }
        return songs.map { track($0) }
    }

    func tracks(playlistId identifier: String) async throws -> [Track] {
        guard let playlist = SourceCatalog.shared.playlist(identifier) else { throw ClientError.invalidResponse }
        return playlist.trackIDs.compactMap { SourceCatalog.shared.song($0) }.map { track($0) }
    }

    func tracks(artistId identifier: String, sortOrder: ItemSortOrder, ascending: Bool, limit: Int = 30) async throws -> [Track] {
        func known() -> [SourceSong] {
            SourceCatalog.shared.allSongs().filter { $0.artistID == identifier || $0.albumArtistID == identifier }
        }

        var songs = known()
        if songs.count < 10, let name = songs.first?.artist, !name.isEmpty {
            _ = await searchSongs(name)
            songs = known()
        }

        let sortedSongs = sorted(songs, by: sortOrder, ascending: ascending)
        return Array(sortedSongs.prefix(limit)).map { track($0) }
    }

    func track(identifier: String) async throws -> Track {
        guard let song = SourceCatalog.shared.song(identifier) else { throw ClientError.invalidResponse }
        return track(song)
    }
}

// MARK: Albums & artists

public extension SourceClient {
    func albums(limit: Int, startIndex: Int, sortOrder: ItemSortOrder, ascending: Bool, favoriteOnly: Bool = false, artistId: String? = nil, search: String? = nil) async throws -> ([Album], Int) {
        var songs: [SourceSong]

        if let artistId {
            songs = SourceCatalog.shared.allSongs().filter { $0.albumArtistID == artistId || $0.artistID == artistId }
        } else if let search, !search.trimmingCharacters(in: .whitespaces).isEmpty {
            songs = await searchSongs(search)
        } else {
            songs = sorted(SourceCatalog.shared.librarySongs(), by: sortOrder == .name ? .album : sortOrder, ascending: ascending)
            // Favorited albums count as library albums even before anything was played.
            let favorites = SourceCatalog.shared.favoriteIDs()
            let ids = Set(songs.map(\.albumID))
            songs += SourceCatalog.shared.allSongs().filter { favorites.contains($0.albumID) && !ids.contains($0.albumID) }
        }

        var list = albums(from: songs)
        if favoriteOnly { list = list.filter { $0._favorite } }
        return (page(list, limit: limit, startIndex: startIndex), list.count)
    }

    func albums(similarToAlbumId albumId: String) async throws -> [Album] {
        let all = SourceCatalog.shared.allSongs()
        guard let artistID = all.first(where: { $0.albumID == albumId })?.albumArtistID else { return [] }
        let others = albums(from: all.filter { $0.albumArtistID == artistID && $0.albumID != albumId })
        return Array(others.prefix(10))
    }

    func album(identifier: String) async throws -> Album {
        guard let album = albums(from: SourceCatalog.shared.allSongs().filter { $0.albumID == identifier }).first else {
            throw ClientError.invalidResponse
        }
        return album
    }

    func artists(limit: Int, startIndex: Int, albumOnly: Bool, search: String?) async throws -> ([Artist], Int) {
        let songs: [SourceSong]

        if let search, !search.trimmingCharacters(in: .whitespaces).isEmpty {
            songs = await searchSongs(search)
        } else {
            songs = SourceCatalog.shared.librarySongs()
        }

        let list = artists(from: songs)
        return (page(list, limit: limit, startIndex: startIndex), list.count)
    }

    func artists(search: String) async throws -> [Artist] {
        Array(artists(from: await searchSongs(search)).prefix(20))
    }

    func artist(identifier: String) async throws -> Artist {
        guard let artist = artists(from: SourceCatalog.shared.allSongs().filter { $0.artistID == identifier }).first else {
            throw ClientError.invalidResponse
        }
        return artist
    }

    /// Cover of an album we have seen, used when downloading.
    func albumCover(albumId: String) -> Cover? {
        SourceCatalog.shared.allSongs().first { $0.albumID == albumId && $0.cover != nil }?.cover
    }
}

// MARK: Playlists & favorites (stored on this device)

public extension SourceClient {
    func create(playlistName: String, trackIds: [String], isPublic: Bool) async throws {
        SourceCatalog.shared.createPlaylist(name: playlistName, trackIDs: trackIds)
    }

    func playlists(limit: Int, sortOrder: ItemSortOrder, ascending: Bool, favoriteOnly: Bool = false, search: String? = nil) async throws -> [Playlist] {
        var list = SourceCatalog.shared.allPlaylists()

        if let search, !search.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(search) }
        }
        if favoriteOnly {
            let favorites = SourceCatalog.shared.favoriteIDs()
            list = list.filter { favorites.contains($0.id) }
        }

        switch sortOrder {
            case .name: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            default: list.sort { $0.created < $1.created }
        }
        if !ascending { list.reverse() }

        let result = list.map(playlist)
        return limit > 0 ? Array(result.prefix(limit)) : result
    }

    func playlist(identifier: String) async throws -> Playlist {
        guard let stored = SourceCatalog.shared.playlist(identifier) else { throw ClientError.invalidResponse }
        return playlist(stored)
    }

    func add(trackIds: [String], playlistId: String) async throws {
        SourceCatalog.shared.addToLibrary(trackIds)
        SourceCatalog.shared.updatePlaylist(playlistId) { $0.trackIDs += trackIds }
    }

    func remove(trackId: String, playlistId: String) async throws {
        SourceCatalog.shared.updatePlaylist(playlistId) { playlist in
            if let i = playlist.trackIDs.firstIndex(of: trackId) { playlist.trackIDs.remove(at: i) }
        }
    }

    func move(trackId: String, index: Int, playlistId: String) async throws {
        SourceCatalog.shared.updatePlaylist(playlistId) { playlist in
            guard let from = playlist.trackIDs.firstIndex(of: trackId) else { return }
            playlist.trackIDs.remove(at: from)
            playlist.trackIDs.insert(trackId, at: min(max(index, 0), playlist.trackIDs.count))
        }
    }

    func delete(identifier: String) async throws {
        SourceCatalog.shared.deletePlaylist(identifier)
    }

    func favorite(_ favorite: Bool, identifier: String) async throws {
        SourceCatalog.shared.setFavorite(identifier, favorite)
    }
}

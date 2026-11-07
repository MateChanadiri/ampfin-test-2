import Foundation
import AFFoundation

internal extension SourceClient {
    func track(_ s: SourceSong) -> Track {
        let catalog = SourceCatalog.shared
        return Track(
            id: s.id,
            name: s.title,
            cover: s.cover,
            favorite: catalog.isFavorite(s.id),
            album: .init(id: s.albumID, name: s.albumName, artists: s.albumArtistRefs),
            artists: s.artistRefs,
            lufs: nil,
            index: .init(index: s.index, disk: s.disc),
            runtime: s.duration,
            playCount: catalog.stat(s.id)?.plays ?? 0,
            releaseDate: s.released)
    }

    /// Songs sharing an album id become one album.
    func albums(from songs: [SourceSong]) -> [Album] {
        var order: [String] = []
        var groups: [String: [SourceSong]] = [:]
        for s in songs {
            if groups[s.albumID] == nil { order.append(s.albumID) }
            groups[s.albumID, default: []].append(s)
        }
        let catalog = SourceCatalog.shared
        return order.compactMap { id in
            guard let group = groups[id], let first = group.first else { return nil }
            return Album(
                id: id,
                name: first.albumName,
                cover: group.compactMap(\.cover).first,
                favorite: catalog.isFavorite(id),
                overview: nil,
                genres: [],
                releaseDate: group.compactMap(\.released).min(),
                artists: first.albumArtistRefs,
                playCount: group.reduce(0) { $0 + (catalog.stat($1.id)?.plays ?? 0) },
                lastPlayed: group.compactMap { catalog.stat($0.id)?.lastPlayed }.max())
        }
    }

    func artists(from songs: [SourceSong]) -> [Artist] {
        var seen = Set<String>()
        var result: [Artist] = []
        for s in songs where !s.artist.isEmpty && seen.insert(s.artistID).inserted {
            result.append(Artist(id: s.artistID, name: s.artist, cover: s.cover, favorite: SourceCatalog.shared.isFavorite(s.artistID), overview: nil))
        }
        return result
    }

    func playlist(_ p: StoredPlaylist) -> Playlist {
        let songs = p.trackIDs.compactMap { SourceCatalog.shared.song($0) }
        return Playlist(
            id: p.id,
            name: p.name,
            cover: songs.compactMap(\.cover).first,
            favorite: SourceCatalog.shared.isFavorite(p.id),
            duration: songs.reduce(0) { $0 + $1.duration },
            trackCount: p.trackIDs.count)
    }
}

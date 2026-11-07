import Foundation
import AFFoundation

/// A track as a module described it, plus derived album/artist ids.
struct SourceSong: Codable, Hashable {
    var id: String
    var moduleID: String
    var title: String
    var artist: String
    var album: String          // empty for singles
    var albumArtist: String
    var albumID: String
    var artistID: String
    var albumArtistID: String
    var artwork: String?
    var url: String?
    var duration: Double
    var index: Int
    var disc: Int
    var released: Date?
    var needsResolve: Bool
    var needsDownloadResolve: Bool
    var raw: String

    var albumName: String { album.isEmpty ? title : album }

    init?(json: [String: Any], module: JSModule) {
        guard let title = Self.string(json["title"]) ?? Self.string(json["name"]) else { return nil }
        let moduleID = module.id
        let rawID = Self.string(json["id"]) ?? Self.string(json["url"]) ?? title
        let artist = Self.string(json["artist"]) ?? (json["artists"] as? [String])?.joined(separator: ", ") ?? ""
        let albumArtist = Self.string(json["albumArtist"]) ?? artist
        let album = Self.string(json["album"]) ?? ""

        self.id = moduleID + "::" + rawID
        self.moduleID = moduleID
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.albumID = moduleID + "::album::" + (Self.string(json["albumId"]) ?? Self.slug(albumArtist + "|" + (album.isEmpty ? title : album)))
        self.artistID = moduleID + "::artist::" + (Self.string(json["artistId"]) ?? Self.slug(artist))
        self.albumArtistID = moduleID + "::artist::" + Self.slug(albumArtist)
        self.artwork = Self.string(json["artwork"]) ?? Self.string(json["cover"])
        self.url = Self.string(json["url"])
        self.duration = (json["duration"] as? NSNumber)?.doubleValue ?? 0
        self.index = (json["trackNumber"] as? NSNumber)?.intValue ?? (json["index"] as? NSNumber)?.intValue ?? 0
        self.disc = (json["disc"] as? NSNumber)?.intValue ?? 1
        if let year = (json["year"] as? NSNumber)?.intValue {
            self.released = Date("\(year)-01-01")
        } else {
            self.released = Date(Self.string(json["releaseDate"]))
        }
        self.needsResolve = module.has("resolve")
        self.needsDownloadResolve = module.has("download") || module.has("resolve")
        self.raw = (try? JSONSerialization.data(withJSONObject: json)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    static func string(_ value: Any?) -> String? {
        if let s = value as? String, !s.isEmpty { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    static func slug(_ s: String) -> String {
        s.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: "-")
    }

    var cover: Cover? {
        guard let artwork, let url = URL(string: artwork) else { return nil }
        return Cover(type: .remote, size: .normal, url: url)
    }
    var artistRefs: [Item.ReducedArtist] {
        artist.isEmpty ? [] : [Item.ReducedArtist(id: artistID, name: artist)]
    }
    var albumArtistRefs: [Item.ReducedArtist] {
        albumArtist.isEmpty ? [] : [Item.ReducedArtist(id: albumArtistID, name: albumArtist)]
    }
}

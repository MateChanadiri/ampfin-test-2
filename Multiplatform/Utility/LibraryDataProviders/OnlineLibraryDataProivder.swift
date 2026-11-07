//
//  OnlineLibraryDataProvider.swift
//  Music
//
//  Created by Rasmus Krämer on 06.09.23.
//

import Foundation
import AmpFinKit

public struct OnlineLibraryDataProvider: LibraryDataProvider {
    public var supportsArtistLookup: Bool = true
    public var supportsAdvancedFilters: Bool = true
    public var albumNotFoundFallbackToLibrary: Bool = false
    
    // MARK: Track
    
    public func tracks(limit: Int, startIndex: Int, sortOrder: ItemSortOrder, ascending: Bool, favoriteOnly: Bool, search: String?) async throws -> ([Track], Int) {
        try await SourceClient.shared.tracks(limit: limit, startIndex: startIndex, sortOrder: sortOrder, ascending: ascending, favoriteOnly: favoriteOnly, search: search)
    }
    
    // MARK: Album
    
    public func recentAlbums() async throws -> [Album] {
        return try await SourceClient.shared.albums(limit: 20, startIndex: 0, sortOrder: .added, ascending: false).0
    }
    public func randomAlbums() async throws -> [Album] {
        return try await SourceClient.shared.albums(limit: 20, startIndex: 0, sortOrder: .random, ascending: true).0
    }
    
    public func album(identifier: String) async throws -> Album {
        do {
            return try await SourceClient.shared.album(identifier: identifier)
        } catch {
            return try await OfflineLibraryDataProvider().album(identifier: identifier)
        }
    }
    public func albums(limit: Int, startIndex: Int, sortOrder: ItemSortOrder, ascending: Bool, search: String?) async throws -> ([Album], Int) {
        try await SourceClient.shared.albums(limit: limit, startIndex: startIndex, sortOrder: sortOrder, ascending: ascending, search: search)
    }
    
    public func tracks(albumId: String) async throws -> [Track] {
        do {
            return try await SourceClient.shared.tracks(albumId: albumId)
        } catch {
            return try await OfflineLibraryDataProvider().tracks(albumId: albumId)
        }
    }
    
    // MARK: Artist
    
    public func artist(identifier: String) async throws -> Artist {
        do {
            return try await SourceClient.shared.artist(identifier: identifier)
        } catch {
            return try await OfflineLibraryDataProvider().artist(identifier: identifier)
        }
    }
    public func artists(limit: Int, startIndex: Int, albumOnly: Bool, search: String?) async throws -> ([Artist], Int) {
        try await SourceClient.shared.artists(limit: limit, startIndex: startIndex, albumOnly: albumOnly, search: search)
    }
    
    public func tracks(artistId: String, sortOrder: ItemSortOrder, ascending: Bool) async throws -> [Track] {
        try await SourceClient.shared.tracks(artistId: artistId, sortOrder: sortOrder, ascending: ascending)
    }
    public func albums(artistId: String, limit: Int, startIndex: Int, sortOrder: ItemSortOrder, ascending: Bool) async throws -> ([Album], Int) {
        try await SourceClient.shared.albums(limit: limit, startIndex: startIndex, sortOrder: sortOrder, ascending: ascending, artistId: artistId)
    }
    
    // MARK: Playlists
    
    public func playlist(identifier: String) async throws -> Playlist {
        do {
            return try await SourceClient.shared.playlist(identifier: identifier)
        } catch {
            return try await OfflineLibraryDataProvider().playlist(identifier: identifier)
        }
    }
    public func playlists(search: String?) async throws -> [Playlist] {
        try await SourceClient.shared.playlists(limit: 0, sortOrder: .lastPlayed, ascending: false, search: search)
    }
    public func tracks(playlistId: String) async throws -> [Track] {
        do {
            return try await SourceClient.shared.tracks(playlistId: playlistId)
        } catch {
            return try await OfflineLibraryDataProvider().tracks(playlistId: playlistId)
        }
    }
}

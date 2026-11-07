//
//  File.swift
//  
//
//  Created by Rasmus Krämer on 04.01.24.
//

import Foundation
import AFFoundation
import AFNetwork
#if canImport(AFOffline)
import AFOffline
#endif

public extension Playlist {
    func add(trackIds: [String]) async throws {
        try await SourceClient.shared.add(trackIds: trackIds, playlistId: id)
        
        #if canImport(AFOffline)
        if OfflineManager.shared.offlineStatus(playlistId: id) != .none {
            try await OfflineManager.shared.download(playlist: self)
        }
        #endif
        
        trackCount = try await SourceClient.shared.tracks(playlistId: id).count
    }
}

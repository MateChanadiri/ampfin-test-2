//
//  DownloadManager+Item.swift
//  Music
//
//  Created by Rasmus Krämer on 08.09.23.
//

import Foundation
import SwiftData
import AFFoundation
import AFNetwork

extension DownloadManager {
    func download(trackId: String) -> URLSessionDownloadTask {
        // Modules that resolve their audio URL lazily are resolved by `SourceClient.prepareDownload` beforehand.
        // Without a URL the task fails and the regular failure handling cleans up.
        let url = SourceClient.shared.knownDownloadURL(trackId: trackId) ?? URL(string: "about:blank")!
        
        var request = URLRequest(url: url)
        
        for header in SourceClient.shared.customHTTPHeaders {
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }
        
        return urlSession.downloadTask(with: request)
    }
    
    func getTrackContainer(trackId: String) -> OfflineTrack.Container {
        let context = ModelContext(PersistenceManager.shared.modelContainer)
        var descriptor = FetchDescriptor<OfflineTrack>(predicate: #Predicate { $0.id == trackId })
        descriptor.fetchLimit = 1
        
        guard let container = try? context.fetch(descriptor).first?.container else {
            return .flac
        }
        
        return container
    }
    
    func setTrackFileType(track: OfflineTrack, mimeType: String?) {
        switch mimeType {
            case "audio/aac":
                track.container = .aac
            case "audio/mp4", "audio/x-m4a":
                // Both alac and aac can be in this container
                track.container = .m4a
            case "audio/mpeg", "audio/mp3":
                track.container = .mp3
            case "audio/wav", "audio/x-wav":
                track.container = .wav
            case "audio/x-aiff":
                track.container = .aiff
            case "audio/webm":
                track.container = .webma
            default:
                // Use flac if unsure
                track.container = .flac
        }
    }
    
    func failed(taskIdentifier: Int) {
        let context = ModelContext(PersistenceManager.shared.modelContainer)
        
        guard let track = try? OfflineManager.shared.offlineTrack(taskId: taskIdentifier, context: context) else {
            logger.fault("Could not resolve track from task identifier \(taskIdentifier)")
            return
        }
        
        logger.fault("Error while downloading track \(track.id) (\(track.name))")
        
        if let parents = try? OfflineManager.shared.parentIds(childId: track.id, context: context).filter({ $0 != track.album.albumIdentifier }) {
            for parent in parents {
                try? OfflineManager.shared.delete(playlistId: parent)
            }
        }
        
        try? OfflineManager.shared.delete(albumId: track.album.albumIdentifier)
    }
    func delete(trackId: String) {
        try? FileManager.default.removeItem(at: url(trackId: trackId))
    }
    
    func url(track: OfflineTrack) -> URL {
        let trackId = track.id
        let container = track.container ?? .flac
        return tracks.appending(path: "\(trackId).\(container)")
    }
    
    public func url(trackId: String) -> URL {
        let container = getTrackContainer(trackId: trackId)
        return tracks.appending(path: "\(trackId).\(container)")
    }
}

public extension DownloadManager {
    func downloaded(trackId: String) -> Bool {
        FileManager.default.fileExists(atPath: url(trackId: trackId).relativePath)
    }
}

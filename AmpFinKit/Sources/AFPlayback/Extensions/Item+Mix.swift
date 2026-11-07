//
//  File.swift
//  
//
//  Created by Rasmus Krämer on 24.12.23.
//

import Foundation
import AFFoundation
import AFNetwork

public extension Item {
    func startInstantMix() async throws {
        let tracks = try await SourceClient.shared.tracks(instantMixBaseId: id)
        AudioPlayer.current.startPlayback(tracks: tracks, startIndex: 0, shuffle: false, playbackInfo: .init(container: self))
    }
}

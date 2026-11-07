public extension SourceClient {
    func supports(_ featureFlag: FeatureFlag) -> Bool {
        switch featureFlag {
            case .lyrics:
                true
            case .sharedPlaylists, .quickConnect, .audioRemuxing:
                false
        }
    }

    enum FeatureFlag: Identifiable, Hashable, Codable {
        case lyrics
        case sharedPlaylists
        case quickConnect
        case audioRemuxing

        public var id: Self {
            self
        }
    }
}

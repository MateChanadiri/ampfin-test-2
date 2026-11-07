import Foundation

public enum PlayStateCommand: String {
    case play = "Unpause"
    case pause = "Pause"
    case next = "NextTrack"
    case previous = "PreviousTrack"
    case stop = "Stop"
}

public enum PlayCommand: String {
    case next = "PlayNext"
    case last = "PlayLast"
}

public struct SourceError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

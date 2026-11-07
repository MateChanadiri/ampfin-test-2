import Foundation
import Observation
import AFFoundation

/// Entry point for everything the UI used to ask a server for. Data now comes from .js modules and the local library.
@Observable
public final class SourceClient {
    public private(set) var clientId: String

    public let clientBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    public let clientVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

    static let defaults = UserDefaults.standard

    @ObservationIgnored var searchCache: [String: (Date, Task<[SourceSong], Never>)] = [:]
    @ObservationIgnored let cacheLock = NSLock()
    @ObservationIgnored var _customHTTPHeaders: [CustomHTTPHeader]?

    private init() {
        if let clientId = Self.defaults.string(forKey: "clientId") {
            self.clientId = clientId
        } else {
            clientId = String(length: 32)
            Self.defaults.set(clientId, forKey: "clientId")
        }
    }

    /// Always true: modules provide the data, there is nothing to sign in to.
    public var online: Bool = true
}

public extension SourceClient {
    static let shared = SourceClient()

    var authorized: Bool { true }

    enum ClientError: Error {
        case parseFailed
        case unknownMessage

        case invalidServerUrl
        case invalidHttpBody
        case invalidResponse
    }
}

import Foundation
import AVFoundation

/// Gives AVPlayer an asset for a track. When the module still has to resolve the audio URL (async),
/// the asset uses a placeholder URL and this loader redirects it once the real one is known.
public enum StreamLoader {
    private static let scheme = "ampfin-track"
    private static let delegate = Delegate()

    public static func asset(trackId: String, headers: [String: String] = [:]) -> AVURLAsset {
        if let url = SourceClient.shared.knownStreamURL(trackId: trackId) {
            return AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = "track"
        components.queryItems = [URLQueryItem(name: "id", value: trackId)]

        let asset = AVURLAsset(url: components.url ?? URL(string: "\(scheme)://track")!)
        asset.resourceLoader.setDelegate(delegate, queue: delegate.queue)
        return asset
    }

    private final class Delegate: NSObject, AVAssetResourceLoaderDelegate {
        let queue = DispatchQueue(label: "stream.loader")

        func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
            guard let url = loadingRequest.request.url, url.scheme == StreamLoader.scheme,
                  let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value else {
                return false
            }

            Task {
                do {
                    let real = try await SourceClient.shared.streamURL(trackId: id)
                    loadingRequest.redirect = URLRequest(url: real)
                    loadingRequest.response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": real.absoluteString])
                    loadingRequest.finishLoading()
                } catch {
                    loadingRequest.finishLoading(with: error)
                }
            }

            return true
        }
    }
}

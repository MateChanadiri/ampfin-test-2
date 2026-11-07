import Foundation
import Observation

/// Owns the installed .js modules (stored in Application Support/Modules).
@MainActor @Observable
public final class ModuleHost {
    public static let shared = ModuleHost()

    public enum Feed: String { case home, new, radio }

    public private(set) var modules: [JSModule] = []
    public private(set) var loadErrors: [String] = []
    public private(set) var runErrors: [String: String] = [:]
    private let dir: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("Modules", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        reload()
    }

    private func reload() {
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "js" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var loaded: [JSModule] = []
        var errors: [String] = []
        for file in files {
            do {
                let source = try String(contentsOf: file, encoding: .utf8)
                loaded.append(try JSModule(id: file.lastPathComponent, source: source))
            } catch {
                errors.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        modules = loaded
        loadErrors = errors
    }

    /// Copies a user-picked .js file into the app and starts it.
    public func add(from url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let source = try String(contentsOf: url, encoding: .utf8)
        let fileName = url.deletingPathExtension().lastPathComponent + ".js"
        _ = try JSModule(id: fileName, source: source) // validates before saving
        try source.write(to: dir.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        reload()
    }

    public func remove(_ module: JSModule) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(module.id))
        reload()
    }

    private func setError(_ message: String?, for id: String) {
        runErrors[id] = message
    }

    /// Calls `fn` on every module at once. Failures are recorded and skipped.
    func callAll(_ fn: String, _ arg: Any?) async -> [(JSModule, Any?)] {
        let mods = modules.filter { $0.has(fn) }
        let results = await withTaskGroup(of: (Int, Any?).self) { group -> [(Int, Any?)] in
            for (i, m) in mods.enumerated() {
                group.addTask {
                    do {
                        let r = try await m.call(fn, arg)
                        await self.setError(nil, for: m.id)
                        return (i, r)
                    } catch {
                        await self.setError(error.localizedDescription, for: m.id)
                        return (i, nil)
                    }
                }
            }
            var out: [(Int, Any?)] = []
            for await r in group { out.append(r) }
            return out
        }
        return results.sorted { $0.0 < $1.0 }.map { (mods[$0.0], $0.1) }
    }

    func call(moduleID: String, _ fn: String, _ arg: Any?) async throws -> Any? {
        guard let m = modules.first(where: { $0.id == moduleID }), m.has(fn) else { return nil }
        return try await m.call(fn, arg)
    }

    func module(_ id: String) -> JSModule? {
        modules.first { $0.id == id }
    }
}

extension ModuleHost {
    /// Finds an audio URL for a song. Uses the module's resolve()/download() when it has them, else the song's own url.
    func resolve(_ song: SourceSong, download: Bool) async throws -> URL {
        if let m = module(song.moduleID) {
            let rawObject = song.raw.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }
            for fn in download ? ["download", "resolve"] : ["resolve"] where m.has(fn) {
                guard let r = try await m.call(fn, rawObject) else { continue }
                if let s = r as? String, let u = URL(string: s) { return u }
                if let d = r as? [String: Any], let s = d["url"] as? String, let u = URL(string: s) { return u }
            }
        }
        if let s = song.url, let u = URL(string: s) { return u }
        throw SourceError("No audio URL from module \"\(song.moduleID)\"")
    }
}

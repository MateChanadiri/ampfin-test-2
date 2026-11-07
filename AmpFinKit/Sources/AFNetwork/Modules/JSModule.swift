import Foundation
import JavaScriptCore

/// One user-supplied .js module running in its own JavaScriptCore context.
/// Contract (CommonJS): module.exports = { name, home(), new(), radio(), search(q), resolve(song), download(song), lyrics(song) }
/// Every function may be async. fetch() and setTimeout() are provided.
public final class JSModule: Identifiable, @unchecked Sendable {
    public let id: String
    public private(set) var name: String
    /// Names of the functions the module exports.
    public private(set) var functions: Set<String> = []
    private let context: JSContext
    private let queue = DispatchQueue(label: "module.js")

    private static let prelude = """
    var module = { exports: {} }; var exports = module.exports;
    var console = { log: function () { __log(Array.prototype.slice.call(arguments).join(' ')); } };
    console.warn = console.error = console.info = console.log;
    function setTimeout(fn, ms) { __timeout(fn, ms || 0); return 0; }
    function fetch(url, opts) {
      opts = opts || {};
      return new Promise(function (resolve, reject) {
        var payload = JSON.stringify({ method: opts.method || 'GET', headers: opts.headers || {}, body: opts.body == null ? null : String(opts.body) });
        __fetch(String(url), payload, function (err, status, body) {
          if (err) { reject(new Error(err)); return; }
          resolve({ ok: status >= 200 && status < 300, status: status,
            text: function () { return Promise.resolve(body); },
            json: function () { return Promise.resolve(JSON.parse(body)); } });
        });
      });
    }
    function __call(name, argJSON, cb) {
      try {
        var e = module.exports || {};
        var fn = typeof e[name] === 'function' ? e[name].bind(e) : null;
        if (!fn) { cb(null, null); return; }
        Promise.resolve(fn(JSON.parse(argJSON))).then(
          function (r) { cb(null, r === undefined ? null : JSON.stringify(r)); },
          function (x) { cb(String((x && x.message) || x), null); });
      } catch (x) { cb(String((x && x.message) || x), null); }
    }
    """

    public init(id: String, source: String) throws {
        guard let ctx = JSContext() else { throw SourceError("Cannot start JavaScript engine") }
        self.id = id
        self.name = (id as NSString).deletingPathExtension
        self.context = ctx

        var failure: String?
        ctx.exceptionHandler = { _, e in failure = failure ?? e?.toString() }
        install(ctx)
        ctx.evaluateScript(JSModule.prelude)
        ctx.evaluateScript(source)
        if let failure { throw SourceError(failure) }

        if let n = ctx.evaluateScript("(module.exports && module.exports.name) || ''")?.toString(),
           !n.isEmpty, n != "undefined" {
            name = n
        }
        if let keys = ctx.evaluateScript("Object.keys(module.exports || {}).filter(function (k) { return typeof module.exports[k] === 'function'; })")?.toArray() as? [String] {
            functions = Set(keys)
        }
        let moduleID = id
        ctx.exceptionHandler = { _, e in print("[module \(moduleID)] \(e?.toString() ?? "error")") }
    }

    public func has(_ function: String) -> Bool { functions.contains(function) }

    private func install(_ ctx: JSContext) {
        let moduleID = id
        let log: @convention(block) (String) -> Void = { print("[module \(moduleID)] \($0)") }
        let timeout: @convention(block) (JSValue, Double) -> Void = { [weak self] fn, ms in
            self?.queue.asyncAfter(deadline: .now() + ms / 1000) { _ = fn.call(withArguments: []) }
        }
        let fetch: @convention(block) (String, String, JSValue) -> Void = { [weak self] urlString, payload, cb in
            guard let self else { return }
            guard let url = URL(string: urlString) else {
                self.queue.async { _ = cb.call(withArguments: ["Bad URL: \(urlString)"]) }
                return
            }
            var req = URLRequest(url: url, timeoutInterval: 25)
            if let d = payload.data(using: .utf8),
               let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                req.httpMethod = (o["method"] as? String) ?? "GET"
                (o["headers"] as? [String: Any])?.forEach { req.setValue("\($0.value)", forHTTPHeaderField: $0.key) }
                if let b = o["body"] as? String { req.httpBody = Data(b.utf8) }
            }
            URLSession.shared.dataTask(with: req) { data, resp, error in
                self.queue.async {
                    if let error {
                        _ = cb.call(withArguments: [error.localizedDescription])
                    } else {
                        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                        let body = String(decoding: data ?? Data(), as: UTF8.self)
                        _ = cb.call(withArguments: [NSNull(), status, body])
                    }
                }
            }.resume()
        }
        ctx.setObject(unsafeBitCast(log, to: AnyObject.self), forKeyedSubscript: "__log" as NSString)
        ctx.setObject(unsafeBitCast(timeout, to: AnyObject.self), forKeyedSubscript: "__timeout" as NSString)
        ctx.setObject(unsafeBitCast(fetch, to: AnyObject.self), forKeyedSubscript: "__fetch" as NSString)
    }

    /// Calls module.exports[fn](arg). Returns nil when the module has no such function.
    func call(_ fn: String, _ arg: Any? = nil) async throws -> Any? {
        let argJSON = arg
            .flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed]) }
            .flatMap { String(data: $0, encoding: .utf8) } ?? "null"

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Any?, Error>) in
            queue.async {
                var done = false
                let finish: (Result<Any?, Error>) -> Void = { result in
                    guard !done else { return }
                    done = true
                    cont.resume(with: result)
                }
                let cb: @convention(block) (JSValue, JSValue) -> Void = { err, res in
                    if err.isString {
                        finish(.failure(SourceError(err.toString())))
                    } else if res.isString, let data = res.toString().data(using: .utf8) {
                        finish(.success(try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])))
                    } else {
                        finish(.success(nil))
                    }
                }
                self.queue.asyncAfter(deadline: .now() + 45) {
                    finish(.failure(SourceError("Module timed out")))
                }
                let args: [Any] = [fn, argJSON, unsafeBitCast(cb, to: AnyObject.self)]
                _ = self.context.objectForKeyedSubscript("__call").call(withArguments: args)
            }
        }
    }
}

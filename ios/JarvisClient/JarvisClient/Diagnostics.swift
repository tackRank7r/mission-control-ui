// =====================================
// File: JarvisClient/Diagnostics.swift
// Drop-in logging + signposts + timing helpers
// Mirrors logs to `print` so they always appear in Xcode console.
// =====================================

import Foundation
import os
import os.signpost

// MARK: - Unified logger (also prints)
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.jarvis.app"
    static let auth = Logger(subsystem: subsystem, category: "Auth")
    static let ui   = Logger(subsystem: subsystem, category: "UI")
    static let net  = Logger(subsystem: subsystem, category: "Network")

    // mirroring helpers
    static func authInfo(_ s: String) { auth.info("\(s, privacy: .public)"); print(s) }
    static func uiInfo(_ s: String)   { ui.info("\(s, privacy: .public)");   print(s) }
    static func netInfo(_ s: String)  { net.info("\(s, privacy: .public)");  print(s) }
}

// MARK: - Signposting (iOS 15+)
enum Signpost {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.jarvis.app"
    static let auth = OSSignposter(subsystem: subsystem, category: "AuthFlow")
    static let ui   = OSSignposter(subsystem: subsystem, category: "UI")

    @discardableResult
    static func beginAuth(_ name: StaticString, _ message: String? = nil) -> OSSignpostIntervalState {
        if let message { return auth.beginInterval(name, "\(message)") }
        return auth.beginInterval(name)
    }
    static func endAuth(_ name: StaticString, _ state: OSSignpostIntervalState) {
        auth.endInterval(name, state)
    }
}

// MARK: - Simple stopwatch for async operations (also prints)
@discardableResult
func measureAsync<T>(
    _ label: String,
    log: Logger = Log.auth,
    operation: () async throws -> T
) async rethrows -> (result: T, elapsedMs: Int) {
    let start = DispatchTime.now().uptimeNanoseconds
    let value = try await operation()
    let end = DispatchTime.now().uptimeNanoseconds
    let ms = Int((end - start) / 1_000_000)
    let line = "[measure] \(label) took \(ms)ms"
    log.info("\(line, privacy: .public)")
    print(line) // <-- mirror
    return (value, ms)
}

// MARK: - UI tap helpers (also prints)
func logTap(_ name: String) {
    let line = "[tap] \(name)"
    Log.ui.info("\(line, privacy: .public)")
    print(line) // <-- mirror
}

// MARK: - Flow helper (formatted one-liners)
func logFlow(_ name: String, status: String, ms: Int) {
    let line = "[flow] \(name) -> \(status) in \(ms)ms"
    Log.authInfo(line)
}

// MARK: - URLSession metrics hook (SDK-safe) (also prints)
func logMetrics(_ metrics: URLSessionTaskMetrics?, label: String = "request") {
    guard let m = metrics else { return }
    for txn in m.transactionMetrics {
        // `remoteEndpoint` isn’t available on all SDKs; avoid it.
        let host: String
        if #available(iOS 13.0, *) {
            host = txn.remoteAddress ?? "unknown"
        } else {
            host = "unknown"
        }
        let ttfb = millis(between: txn.requestStartDate, txn.responseStartDate)
        let dns  = millis(between: txn.domainLookupStartDate, txn.domainLookupEndDate)
        let conn = millis(between: txn.connectStartDate, txn.connectEndDate)
        let tls  = millis(between: txn.secureConnectionStartDate, txn.secureConnectionEndDate)
        let line = "[metrics] \(label) host=\(host) dns=\(dns)ms conn=\(conn)ms tls=\(tls)ms ttfb=\(ttfb)ms"
        Log.netInfo(line)
    }
}

private func millis(between a: Date?, _ b: Date?) -> Int {
    guard let a = a, let b = b else { return -1 }
    return Int(b.timeIntervalSince(a) * 1000.0)
}

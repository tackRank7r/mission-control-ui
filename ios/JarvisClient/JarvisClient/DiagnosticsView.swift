// =====================================
// Path: JarvisClient/DiagnosticsView.swift
// (FULL REPLACEMENT)
// Combined flags view (from /diagnostics) + live endpoint pinger
// =====================================
import SwiftUI

// ---- Models for /diagnostics (preserved from your old version) ----
private struct DiagnosticsFlags: Codable {
    let has_backend_bearer: Bool?
    let has_openai: Bool?
    let has_aws_keys: Bool?
    let use_s3_cache: Bool?
    let aws_region: String?
    let polly_voice: String?
    let polly_format: String?
    let polly_engine: String?
    let tts_provider_env: String?
    let tts_provider_effective: String?
}

private struct DiagnosticsResponse: Codable {
    let ok: Bool
    let flags: DiagnosticsFlags
}

// ---- Pinger types ----
@MainActor
private final class EndpointPinger: ObservableObject {
    struct Row: Identifiable, Equatable {
        enum Kind: String { case ask = "/ask", chat = "/api/chat", speak = "/speak" }
        enum State: Equatable { case idle, running, ok(Int, Int), fail(Int?, String) }
        let id = UUID()
        let kind: Kind
        var state: State = .idle
        var url: URL {
            switch kind {
            case .ask:  return Secrets.askEndpoint
            case .chat: return Secrets.chatEndpoint
            case .speak:return Secrets.speakEndpoint
            }
        }
    }

    @Published var rows: [Row] = [
        .init(kind: .ask),
        .init(kind: .chat),
        .init(kind: .speak)
    ]

    private let session: URLSession = .shared

    func runAll() {
        for i in rows.indices { rows[i].state = .running }
        Task {
            await withTaskGroup(of: (Int, Row.State).self) { group in
                for i in rows.indices {
                    let row = rows[i]
                    group.addTask { [weak self] in
                        guard let self else { return (i, .fail(nil, "internal")) }
                        let newState = await self.ping(row)
                        return (i, newState)
                    }
                }
                for await (idx, state) in group {
                    if idx < rows.count { rows[idx].state = state }
                }
            }
        }
    }

    private func headers(json: Bool) -> [String:String] { Secrets.headers(json: json) }

    // One function per endpoint “shape”
    private func ping(_ row: Row) async -> Row.State {
        let t0 = CFAbsoluteTimeGetCurrent()
        func ms() -> Int { Int((CFAbsoluteTimeGetCurrent() - t0) * 1000) }

        do {
            switch row.kind {
            case .ask:
                var req = URLRequest(url: row.url)
                req.httpMethod = "POST"
                headers(json: true).forEach { req.setValue($1, forHTTPHeaderField: $0) }
                let payload: [[String:String]] = [
                    ["role":"system","content":"You are Jarvis."],
                    ["role":"user","content":"ping"]
                ]
                req.httpBody = try JSONSerialization.data(withJSONObject: ["messages": payload], options: [])
                let (data, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse else { return .fail(nil, "no http") }
                if (200..<300).contains(http.statusCode) {
                    if let obj = try? JSONSerialization.jsonObject(with: data) as? [String:Any],
                       let reply = obj["reply"] as? String, !reply.isEmpty {
                        return .ok(http.statusCode, ms())
                    }
                    return .fail(http.statusCode, "No reply key")
                } else if http.statusCode == 404 || http.statusCode == 405 {
                    return .fail(http.statusCode, "Route missing")
                } else {
                    return .fail(http.statusCode, String(data: data, encoding: .utf8) ?? "error")
                }

            case .chat:
                var req = URLRequest(url: row.url)
                req.httpMethod = "POST"
                headers(json: true).forEach { req.setValue($1, forHTTPHeaderField: $0) }
                let text = "ping"
                var body: [String:Any] = [
                    "user_text": text, // cover legacy servers that expect this exact key
                    "prompt": text,
                    "text": text
                ]
                body["system"] = "You are Jarvis."
                req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                let (data, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse else { return .fail(nil, "no http") }
                if (200..<300).contains(http.statusCode) {
                    if let obj = try? JSONSerialization.jsonObject(with: data) as? [String:Any] {
                        for k in ["reply","message","text","content","answer"] {
                            if let s = obj[k] as? String, !s.isEmpty { return .ok(http.statusCode, ms()) }
                        }
                    }
                    if let s = String(data: data, encoding: .utf8), !s.isEmpty { return .ok(http.statusCode, ms()) }
                    return .fail(http.statusCode, "Unparseable body")
                } else if http.statusCode == 404 {
                    return .fail(http.statusCode, "Route missing")
                } else {
                    return .fail(http.statusCode, String(data: data, encoding: .utf8) ?? "error")
                }

            case .speak:
                var req = URLRequest(url: row.url)
                req.httpMethod = "POST"
                headers(json: true).forEach { req.setValue($1, forHTTPHeaderField: $0) }
                req.httpBody = try JSONSerialization.data(withJSONObject: ["text": "ping"], options: [])
                let (data, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse else { return .fail(nil, "no http") }
                return (200..<300).contains(http.statusCode) && !data.isEmpty
                    ? .ok(http.statusCode, ms())
                    : .fail(http.statusCode, "No audio or non-2xx")
            }
        } catch {
            return .fail(nil, (error as NSError).localizedDescription)
        }
    }
}

// ---- Main Diagnostics View (flags + pinger) ----
struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss

    // Flags from /diagnostics
    @State private var diag: DiagnosticsResponse?
    @State private var isLoading = false
    @State private var error: String?

    // Endpoint pinger
    @StateObject private var pinger = EndpointPinger()

    var body: some View {
        NavigationStack {
            List {
                // Base URL + quick actions
                Section {
                    HStack {
                        Text("Base URL")
                        Spacer()
                        Text(Secrets.baseURL.absoluteString)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button {
                        pinger.runAll()
                    } label: {
                        Label("Run Endpoint Checks", systemImage: "waveform.path.ecg")
                            .foregroundColor(.blue)
                    }
                }

                // Endpoint results
                Section("Endpoints") {
                    ForEach(pinger.rows) { row in
                        EndpointRow(row: row)
                    }
                }

                // Diagnostics flags
                Section("Diagnostics Flags (/diagnostics)") {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Loading…")
                        }
                    } else if let diag {
                        flagRow("ok", diag.ok ? "true" : "false")
                        flagRow("has_backend_bearer", boolText(diag.flags.has_backend_bearer))
                        flagRow("has_openai", boolText(diag.flags.has_openai))
                        flagRow("has_aws_keys", boolText(diag.flags.has_aws_keys))
                        flagRow("use_s3_cache", boolText(diag.flags.use_s3_cache))
                        flagRow("aws_region", diag.flags.aws_region)
                        flagRow("polly_voice", diag.flags.polly_voice)
                        flagRow("polly_format", diag.flags.polly_format)
                        flagRow("polly_engine", diag.flags.polly_engine)
                        flagRow("tts_provider_env", diag.flags.tts_provider_env)
                        flagRow("tts_provider_effective", diag.flags.tts_provider_effective)
                    } else if let error {
                        VStack(spacing: 8) {
                            Text(error).foregroundColor(.red).multilineTextAlignment(.center)
                            Button("Retry") { Task { await fetchDiagnostics() } }
                        }
                    } else {
                        Text("No data").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await fetchDiagnostics() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                if diag == nil { await fetchDiagnostics() }
                pinger.runAll()
            }
        }
    }

    // ---- helpers for flags section ----
    private func flagRow(_ key: String, _ value: String?) -> some View {
        HStack {
            Text(key)
            Spacer()
            Text(value ?? "—").foregroundStyle(.secondary)
        }
    }

    private func boolText(_ v: Bool?) -> String? {
        v.map { $0 ? "true" : "false" }
    }

    // ---- networking for /diagnostics ----
    private func fetchDiagnostics() async {
        error = nil
        isLoading = true
        defer { isLoading = false }
        do {
            var req = URLRequest(url: Secrets.diagnosticsEndpoint)
            req.httpMethod = "GET"
            Secrets.headers(json: false).forEach { req.setValue($1, forHTTPHeaderField: $0) }
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
                let body = String(data: data, encoding: .utf8) ?? ""
                throw NSError(domain: "Diagnostics", code: status,
                              userInfo: [NSLocalizedDescriptionKey: "Bad status \(status). \(body)"])
            }
            diag = try JSONDecoder().decode(DiagnosticsResponse.self, from: data)
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }
}

// ---- Row view for pinger ----
private struct EndpointRow: View {
    let row: EndpointPinger.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            statusDot
            VStack(alignment: .leading, spacing: 2) {
                Text(titleFor(row.kind))
                    .font(.body.weight(.semibold))
                Text(row.url.absoluteString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            switch row.state {
            case .idle:
                Text("idle").foregroundStyle(.secondary)
            case .running:
                ProgressView().frame(width: 20, height: 20)
            case let .ok(code, ms):
                Text("\(code) · \(ms)ms").foregroundStyle(.green)
            case let .fail(code, msg):
                VStack(alignment: .trailing, spacing: 2) {
                    Text(code.map { "\($0)" } ?? "—")
                        .foregroundStyle(.red)
                    Text(msg).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var statusDot: some View {
        let color: Color
        switch row.state {
        case .idle:    color = .gray.opacity(0.5)
        case .running: color = .orange
        case .ok:      color = .green
        case .fail:    color = .red
        }
        return Circle().fill(color).frame(width: 10, height: 10)
    }

    private func titleFor(_ k: EndpointPinger.Row.Kind) -> String {
        switch k {
        case .ask:  return "Modern /ask"
        case .chat: return "Legacy /api/chat"
        case .speak:return "Text-to-Speech /speak"
        }
    }
}

// ---- Preview ----
#Preview {
    DiagnosticsView()
}

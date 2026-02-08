// File: ios/JarvisClient/JarvisClient/APIClient.swift
// Action: REPLACE entire file
//
// Purpose:
//   - Simple HTTP client for the SideKick360 backend
//   - Single JSON contract for chat + TTS
//   - No "all request shapes" fallback anymore.
//
// Endpoints (from Secrets.swift):
//   Secrets.chatEndpoint   -> POST { messages: [{role, content}, ...] }
//   Secrets.speakEndpoint  -> POST { text: "..." } -> audio bytes
//
// Secrets.headers(json:) should attach Authorization + Content-Type.
//

import Foundation

// MARK: - Models

/// Minimal message model used by both chat UI and VoiceChatManager.


/// Response shape from the backend chat endpoint.
struct AskResponse: Codable {
    let reply: String
    let call_scheduled: CallScheduledInfo?
}

/// Info returned when the backend auto-schedules a phone call.
struct CallScheduledInfo: Codable {
    let call_id: Int?
    let status: String?
    let routing_type: String?
    let target_name: String?
    let target_phone: String?
}

// MARK: - Errors

enum APIClientError: LocalizedError {
    case badStatus(code: Int, body: String)
    case decodingFailed
    case urlError(URLError)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, let body):
            return "Server error (\(code)): \(body)"
        case .decodingFailed:
            return "Failed to decode server response."
        case .urlError(let e):
            return e.localizedDescription
        case .unknown(let e):
            return e.localizedDescription
        }
    }
}

// MARK: - Client

final class APIClient {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Retries a request up to `maxRetries` times on timeout/network errors.
    private func dataWithRetry(for request: URLRequest, maxRetries: Int = 1) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                return try await session.data(for: request)
            } catch let urlError as URLError where
                urlError.code == .timedOut ||
                urlError.code == .networkConnectionLost ||
                urlError.code == .notConnectedToInternet {
                lastError = urlError
                if attempt < maxRetries {
                    // Wait briefly before retrying (500ms * attempt)
                    try? await Task.sleep(nanoseconds: UInt64((attempt + 1)) * 500_000_000)
                }
            } catch {
                throw error // Non-retryable error
            }
        }
        throw lastError ?? APIClientError.unknown(NSError(domain: "APIClient", code: -1))
    }

    // MARK: - Chat

    /// POSTs the messages to Secrets.chatEndpoint using a *single* JSON shape:
    ///
    ///   { "messages": [ { "role": "...", "content": "..." }, ... ] }
    ///
    func ask(messages: [Message]) async throws -> AskResponse {
        var request = URLRequest(url: Secrets.chatEndpoint)
        request.httpMethod = "POST"

        Secrets.headers(json: true).forEach { key, value in
            request.addValue(value, forHTTPHeaderField: key)
        }

        let payload: [String: Any] = [
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await dataWithRetry(for: request)
        } catch let urlError as URLError {
            throw APIClientError.urlError(urlError)
        } catch {
            throw APIClientError.unknown(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.decodingFailed
        }

        #if DEBUG
        print("APIClient.ask -> \(http.statusCode) from \(request.url?.absoluteString ?? "<nil>")")
        #endif

        guard (200...299).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw APIClientError.badStatus(code: http.statusCode, body: bodyString)
        }

        do {
            let decoded = try JSONDecoder().decode(AskResponse.self, from: data)
            return decoded
        } catch {
            throw APIClientError.decodingFailed
        }
    }

    // MARK: - Text-to-speech

    /// POSTs text to Secrets.speakEndpoint:
    ///
    ///   { "text": "<assistant reply>" }
    ///
    /// and returns the raw audio bytes for playback.
    func speak(_ text: String) async throws -> Data {
        var request = URLRequest(url: Secrets.speakEndpoint)
        request.httpMethod = "POST"

        Secrets.headers(json: true).forEach { key, value in
            request.addValue(value, forHTTPHeaderField: key)
        }

        let payload: [String: Any] = [ "text": text ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await dataWithRetry(for: request)
        } catch let urlError as URLError {
            throw APIClientError.urlError(urlError)
        } catch {
            throw APIClientError.unknown(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.decodingFailed
        }

        #if DEBUG
        print("APIClient.speak -> \(http.statusCode) from \(request.url?.absoluteString ?? "<nil>")")
        #endif

        guard (200...299).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw APIClientError.badStatus(code: http.statusCode, body: bodyString)
        }

        return data
    }
}

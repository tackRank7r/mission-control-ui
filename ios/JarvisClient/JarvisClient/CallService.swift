// File: ios/JarvisClient/JarvisClient/CallService.swift
// Action: REPLACE entire file
// Purpose: Start the Twilio-backed call via your backend, using Secrets.baseURL (URL)
//          and Secrets.headers(json:).

import Foundation

struct CallRequestPayload: Codable {
    let phoneNumber: String
    let instructions: String
    let userEmail: String?
}

enum CallServiceError: Error {
    case badStatusCode(Int)
    case noResponse
}

final class CallService {
    static let shared = CallService()
    private init() {}

    func startCall(
        phoneNumber: String,
        instructions: String,
        userEmail: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Your baseURL is already a URL, so just append the path.
        let url = Secrets.baseURL.appendingPathComponent("calls/start")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Use the same headers helper used elsewhere (e.g., MemoryStore.swift).
        let headers = Secrets.headers(json: true)
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let payload = CallRequestPayload(
            phoneNumber: phoneNumber,
            instructions: instructions,
            userEmail: userEmail
        )

        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(CallServiceError.noResponse)) }
                return
            }

            guard (200..<300).contains(http.statusCode) else {
                DispatchQueue.main.async {
                    completion(.failure(CallServiceError.badStatusCode(http.statusCode)))
                }
                return
            }

            DispatchQueue.main.async {
                completion(.success(()))
            }
        }.resume()
    }
}

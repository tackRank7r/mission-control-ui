// =====================================
// File: JarvisClient/MemoryStore.swift
// Purpose: Manages local and cloud memory notes for Jarvis app
// Dependencies: Foundation, Secrets.swift, AuthManager.swift
// =====================================
import Foundation

struct MemoryNote: Codable, Equatable, Identifiable {
    let id: String
    let createdAt: Date
    let text: String
}

protocol MemoryStore {
    func loadAll() async throws -> [MemoryNote]
    func save(note: MemoryNote) async throws
    func purgeAll() async throws
}

final class LocalMemoryStore: MemoryStore {
    private let url: URL
    init(filename: String = "memory.json") {
        self.url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
    }
    func loadAll() async throws -> [MemoryNote] {
        if !FileManager.default.fileExists(atPath: url.path) { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([MemoryNote].self, from: data)
    }
    func save(note: MemoryNote) async throws {
        var all = try await loadAll()
        all.append(note)
        let data = try JSONEncoder().encode(all)
        try data.write(to: url, options: .atomic)
    }
    func purgeAll() async throws {
        try? FileManager.default.removeItem(at: url)
    }
}

final class CloudMemoryStore: MemoryStore {
    private let session = URLSession.shared
    
    func loadAll() async throws -> [MemoryNote] {
        var req = URLRequest(url: Secrets.baseURL.appendingPathComponent("/memory"))
        req.httpMethod = "GET"
        var headers = Secrets.headers(json: false)
        do {
            if let (key, value) = try await AuthManager.shared.authHeader() { headers[key] = value }
        } catch {
            print("Failed to get auth header: \(error)") // Optional: Log error for debug
        }
        headers.forEach { req.addValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([MemoryNote].self, from: data)
    }
    
    func save(note: MemoryNote) async throws {
        var req = URLRequest(url: Secrets.baseURL.appendingPathComponent("/memory"))
        req.httpMethod = "POST"
        var headers = Secrets.headers(json: true)
        do {
            if let (key, value) = try await AuthManager.shared.authHeader() { headers[key] = value }
        } catch {
            print("Failed to get auth header: \(error)") // Optional: Log error for debug
        }
        headers.forEach { req.addValue($1, forHTTPHeaderField: $0) }
        let body = try JSONEncoder().encode(note)
        req.httpBody = body
        let (_, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }
    
    func purgeAll() async throws {
        var req = URLRequest(url: Secrets.baseURL.appendingPathComponent("/memory"))
        req.httpMethod = "DELETE"
        var headers = Secrets.headers(json: false)
        do {
            if let (key, value) = try await AuthManager.shared.authHeader() { headers[key] = value }
        } catch {
            print("Failed to get auth header: \(error)") // Optional: Log error for debug
        }
        headers.forEach { req.addValue($1, forHTTPHeaderField: $0) }
        let (_, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }
}

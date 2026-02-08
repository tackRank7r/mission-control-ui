// File: ios/JarvisClient/JarvisClient/ContactsManager.swift
// Action: CREATE file
// Purpose: Request iOS Contacts permission and look up a phone number by name/org.

import Foundation
import Contacts
import Combine

final class ContactsManager: ObservableObject {
    static let shared = ContactsManager()

    @Published private(set) var hasPermission: Bool = false

    private let store = CNContactStore()

    private init() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        hasPermission = (status == .authorized)
    }

    // Call this when you first need contacts (e.g. on “Call …” request).
    func requestAccessIfNeeded(completion: @escaping (Bool) -> Void) {
        let status = CNContactStore.authorizationStatus(for: .contacts)

        switch status {
        case .authorized:
            hasPermission = true
            completion(true)

        case .denied, .restricted:
            hasPermission = false
            completion(false)

        case .notDetermined:
            store.requestAccess(for: .contacts) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.hasPermission = granted
                    completion(granted)
                }
            }

        @unknown default:
            hasPermission = false
            completion(false)
        }
    }

    /// Very simple fuzzy search over full name + organization.
    /// Example: query "Dr. Smith" or "Dentist".
    func findPhoneNumber(matching query: String, completion: @escaping (String?) -> Void) {
        requestAccessIfNeeded { [weak self] granted in
            guard granted, let self = self else {
                completion(nil)
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.lookupSync(query: query)
                DispatchQueue.main.async {
                    completion(result?.phone)
                }
            }
        }
    }

    /// Async wrapper for use in Swift concurrency contexts.
    func findContact(matching query: String) async -> ContactMatch? {
        guard hasPermission else { return nil }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: self.lookupSync(query: query))
            }
        }
    }

    /// Searches user text for any word sequence that matches a contact name.
    /// Returns the best match found, or nil.
    func findContactInText(_ text: String) async -> ContactMatch? {
        guard hasPermission else { return nil }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.searchTextForContact(text)
                cont.resume(returning: result)
            }
        }
    }

    struct ContactMatch {
        let name: String
        let phone: String
    }

    // MARK: - Private helpers

    private func lookupSync(query: String) -> ContactMatch? {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as NSString,
            CNContactFamilyNameKey as NSString,
            CNContactOrganizationNameKey as NSString,
            CNContactPhoneNumbersKey as NSString
        ]

        let request = CNContactFetchRequest(keysToFetch: keys)
        var bestMatch: ContactMatch?

        do {
            try store.enumerateContacts(with: request) { contact, stop in
                let fullName = "\(contact.givenName) \(contact.familyName)"
                    .trimmingCharacters(in: .whitespaces)
                let org = contact.organizationName

                let haystack = (fullName + " " + org).lowercased()
                let needle = query.lowercased()

                guard haystack.contains(needle) else { return }

                if let phone = contact.phoneNumbers.first?.value.stringValue {
                    let displayName = fullName.isEmpty ? org : fullName
                    bestMatch = ContactMatch(name: displayName, phone: phone)
                    stop.pointee = true
                }
            }
        } catch {
            // Best effort
        }
        return bestMatch
    }

    /// Scans text for 2+ word sequences that match a contact.
    private func searchTextForContact(_ text: String) -> ContactMatch? {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard words.count >= 1 else { return nil }

        // Try progressively shorter sequences (longest match wins)
        for length in stride(from: min(words.count, 4), through: 1, by: -1) {
            for start in 0...(words.count - length) {
                let candidate = words[start..<(start + length)].joined(separator: " ")
                // Skip very short candidates (likely not names)
                if candidate.count < 3 { continue }
                if let match = lookupSync(query: candidate) {
                    return match
                }
            }
        }
        return nil
    }
}


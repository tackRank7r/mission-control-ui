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
    /// Example: query “Dr. Smith” or “Dentist”.
    func findPhoneNumber(matching query: String, completion: @escaping (String?) -> Void) {
        requestAccessIfNeeded { [weak self] granted in
            guard granted, let self = self else {
                completion(nil)
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let keys: [CNKeyDescriptor] = [
                    CNContactGivenNameKey as NSString,
                    CNContactFamilyNameKey as NSString,
                    CNContactOrganizationNameKey as NSString,
                    CNContactPhoneNumbersKey as NSString
                ]

                let request = CNContactFetchRequest(keysToFetch: keys)
                var bestMatchNumber: String?

                do {
                    try self.store.enumerateContacts(with: request) { contact, stop in
                        let fullName = "\(contact.givenName) \(contact.familyName)"
                            .trimmingCharacters(in: .whitespaces)
                        let org = contact.organizationName

                        let haystack = (fullName + " " + org).lowercased()
                        let needle = query.lowercased()

                        guard haystack.contains(needle) else { return }

                        if let phone = contact.phoneNumbers.first?.value.stringValue {
                            bestMatchNumber = phone
                            stop.pointee = true
                        }
                    }
                } catch {
                    // Best effort; just fall through with nil.
                }

                DispatchQueue.main.async {
                    completion(bestMatchNumber)
                }
            }
        }
    }
}


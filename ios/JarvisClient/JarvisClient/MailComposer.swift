// =====================================
// File: JarvisClient/MailComposer.swift
// FINAL - Runbook Compliant Version
// =====================================

import SwiftUI
import MessageUI

struct MailComposer: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    var recipient: String
    var subject: String
    var messageBody: String   // renamed from 'body' to avoid redeclaration conflict

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        var parent: MailComposer

        init(_ parent: MailComposer) {
            self.parent = parent
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
            parent.presentationMode.wrappedValue.dismiss()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mailVC = MFMailComposeViewController()
        mailVC.mailComposeDelegate = context.coordinator
        mailVC.setToRecipients([recipient])
        mailVC.setSubject(subject)
        mailVC.setMessageBody(messageBody, isHTML: false)
        return mailVC
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {
        // No live updates needed
    }

    static func canSendMail() -> Bool {
        MFMailComposeViewController.canSendMail()
    }
}

// MARK: - SwiftUI Wrapper for Easy Use
struct MailButton: View {
    @State private var showingMail = false
    var recipient: String
    var subject: String
    var messageBody: String   // renamed consistently

    var body: some View {
        Button {
            if MailComposer.canSendMail() {
                showingMail = true
            } else {
                print("Mail services are not available.")
            }
        } label: {
            Label("Send Feedback", systemImage: "envelope.fill")
        }
        .sheet(isPresented: $showingMail) {
            MailComposer(recipient: recipient, subject: subject, messageBody: messageBody)
        }
    }
}

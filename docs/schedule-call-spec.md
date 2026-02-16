# SideKick360 "Schedule a Call" Flow – Implementation Spec

_Last updated: 2026-02-11 16:46 CST_

## 1. Goals & Scope

Deliver a guided "schedule a call" experience that works from chat, voice, and the main UI while capturing enough context for the backend to trigger the correct routing, OTP-gated confirmation, and summary email.

Out of scope: contact syncing to cloud, calendar integration with third-party APIs, or redesigning the existing chat/call history stack.

## 2. User Stories

1. **Schedule from chat:** As a user chatting with SideKick360, I can say "set up a call with Dana tomorrow morning" and the assistant launches the scheduling flow to fill in missing info.
2. **Schedule from voice button:** From the voice UI I can verbally request a call; the UI switches into the multi-step flow with voice prompts.
3. **Schedule from button:** Tapping the existing "Schedule a Call" button opens the guided UI.
4. **Settings confirmation:** I can review/change my name, preferred agent tone, and confirmation email inside Settings; these values auto-fill the scheduler.
5. **Contacts integration:** I can pick an iOS contact (name + phone + optional email) or type freeform contact details.
6. **OTP email verification:** If my confirmation email is unverified, the app prompts me to enter a one-time code sent by the backend.
7. **Summary email:** After the call completes, I receive an email summary (outcome + action items + next steps) using the tone selected during scheduling.

## 3. Experience Flow

1. **Entry point determination**
   - Chat intent detection looks for phrases like "schedule a call", "book a call", etc.
   - Voice intent uses existing `VoiceChatManager` to emit `VoiceIntent.scheduleCall`.
   - Manual button triggers `ScheduleCallCoordinator`.

2. **Multi-step wizard (SwiftUI sheet / navigation stack):**
   1. _Contact step_: Search device contacts (CNContactPicker) or manual entry; capture name, phone, optional email/company.
   2. _Purpose & agenda_: Freeform text field + quick templates (status update, follow-up, escalation).
   3. _Timing_: Date picker with quick chips (Later today, Tomorrow morning, Custom). Store timezone-aware ISO timestamp.
   4. _Tone & agent persona_: Segmented control with options (Friendly, Professional, Executive). Display agent name preview.
   5. _Confirmation_: Shows summary card, selected email, and OTP status.

3. **OTP branch:**
   - If `SettingsStore.isEmailVerified == false`, call `/auth/request-code` and prompt user for 6-digit OTP.
   - Submit `/auth/verify-code` with email + code → on success, mark `isEmailVerified = true` locally.

4. **Submit call:**
   - POST `/call/schedule` with payload described below.
   - Show pending state (spinner + copy "Your call is queued").

5. **Completion notification:**
   - When `/call/<id>/events` emits `completed`, backend also sends SendGrid summary email; client optionally surfaces push/local notification linking to history.

## 4. Data Model & Local Storage

### Local Settings (`SettingsStore`)
- `agentName: String` (default "SideKick360")
- `preferredTone: Tone` (`friendly`, `professional`, `executive`)
- `userEmail: String`
- `isEmailVerified: Bool`
- Stored via `@AppStorage`/UserDefaults JSON blob so it is available offline.

### Scheduling Flow Model
```swift
struct CallScheduleRequest: Codable {
    struct Contact: Codable {
        var name: String
        var phoneNumber: String
        var email: String?
        var company: String?
    }

    var contact: Contact
    var objective: String
    var tone: Tone
    var agentName: String
    var scheduledTimeISO8601: String // e.g. 2026-02-11T21:30:00Z
    var requesterEmail: String
    var metadata: [String: String] // free-form, e.g. entry point, notes
}
```

### Tone enum
```
Friendly (warm, casual)
Professional (neutral, businesslike)
Executive (concise, high-authority)
```
Mapped to backend `tone` string.

## 5. Backend Payload & APIs

### `/call/schedule` additions
- Accepts new fields: `contact.email`, `tone`, `agent_name`, `requester_email`, optional `metadata.entry_point`.
- Store in `CallTask` table:
  - `contact_email` (nullable)
  - `agent_tone`
  - `agent_display_name`
  - `requester_email`
  - `entry_point`
- Response adds `requires_email_verification` boolean so client knows to prompt if backend sees unverified email.

### OTP Endpoints
1. `POST /auth/request-code`
   - Body: `{ "email": "user@example.com" }`
   - Rate-limit per email (e.g., 5/hour).
   - Stores hashed OTP with 10-min expiry.
   - Sends SendGrid transactional email (template: OTP code, short copy).

2. `POST /auth/verify-code`
   - Body: `{ "email": "user@example.com", "code": "123456" }`
   - Returns `{ "verified": true }` and issues a short-lived token or session entry so `/call/schedule` trusts subsequent requests.

### Summary Email Trigger
- After a call transitions to `completed`, backend composes summary using stored metadata:
  - Subject: `SideKick360 Summary – <Contact Name> — <Date>`
  - Body sections: Outcome, Action Items (bulleted), Promises/Follow-ups, Next Steps.
  - Tone-specific intro/outro (use `agent_tone`).
- SendGrid dynamic template with placeholders for each section.

## 6. iOS Implementation Checklist

- **Settings surface:** Add row under Main Menu → Settings. Includes:
  - Agent Name text field (validates length).
  - Tone segmented control.
  - Email field + "Verify" button → OTP flow.
- **Contacts permission:**
  - Add `NSContactsUsageDescription` to Info.plist with copy: _"SideKick360 uses your contacts to let you pick who should receive scheduled calls."_
  - Use `CNContactPickerViewController` / `ContactsUI` bridging in SwiftUI.
- **Schedule UI:** new `ScheduleCallView` with the steps listed above; accessible via button, chat intent, and voice intent.
- **Chat/Voice integration:**
  - Update `ChatViewModel` intent detection to push `ScheduleCallIntent` when patterns match.
  - `VoiceChatManager` to emit similar events; `ContentView` listens and presents the sheet.
- **Networking:** implement `CallSchedulerService` for OTP + scheduling requests.
- **State handling:** show success/error toasts; log analytics events (`entry_point`, `tone`).

## 7. Backend Enhancements Checklist

- Extend database migration for new columns (nullable defaults for existing rows).
- Implement OTP tables (email, hashed_code, expires_at, attempts, verified_at).
- Wire SendGrid client (API key from env `SENDGRID_API_KEY`).
- Update `/call/schedule` to enforce verified email unless `is_admin`.
- Hook summary email send on `call_completed` event (existing Twilio/n8n + ElevenLabs flows).

## 8. Testing Requirements

- **Unit tests:**
  - `SettingsStoreTests` (tone persistence, email verification flag).
  - `CallScheduleRequestTests` (payload encoding, ISO timestamp formatting).
  - Backend OTP tests (request, verify, expiry, rate limits).
- **Integration tests:**
  - Flask tests for `/call/schedule` ensuring new fields stored.
  - SendGrid summary trigger using stub transport.
- **UI tests (XCUITest):**
  - Schedule flow via button and via chat intent.
  - OTP prompt path (enter code, success/failure).

## 9. Documentation & Release Notes

- Update `RUNBOOK.md` + root `README.md` describing:
  - Tone settings & OTP flow.
  - Schedule-call wizard steps.
  - New backend endpoints `/auth/request-code`, `/auth/verify-code`.
  - Summary email template requirements/settings.
- Add release notes entry: "Schedule-A-Call 2.0" with highlights (contacts picker, tone control, OTP verification, summary email).

---

This spec is the baseline for the immediate implementation work; any adjustments can be tracked here and timestamped as they arise.

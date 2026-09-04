import EventKit
import Foundation
import UIKit

/// Tools that change something outside the app — a calendar entry, a reminder,
/// a phone call (FR-41). They are opt-in (Settings → Device actions, off by
/// default) and the router re-checks that switch at call time, exactly like the
/// egress tools do. Calls and texts go through the system's own confirmation
/// UI, so the model can only ever *offer* them.
nonisolated enum DeviceActionDates {
    /// Lenient date parsing: a small model writes "2026-09-05T14:00:00",
    /// "2026-09-05 14:00", or just "2026-09-05" and means all three.
    static func parse(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

nonisolated struct CalendarEventTool: LocalTool {
    private struct Arguments: Decodable {
        var title: String
        var start: String
        var end: String?
        var durationMinutes: Int?
        var location: String?
        var notes: String?
    }

    let store: EKEventStore

    var spec: ToolSpec {
        ToolSpec(
            name: "create_calendar_event",
            summary: "Adds an event to the user's default calendar. Dates are local time in \"YYYY-MM-DDTHH:MM\" form. Call current_datetime first if you need to resolve \"tomorrow\" or \"next Friday\".",
            parametersJSONSchema: #"{"type":"object","properties":{"title":{"type":"string"},"start":{"type":"string","description":"Start, e.g. \"2026-09-05T14:00\""},"end":{"type":"string","description":"End; omit to use durationMinutes"},"durationMinutes":{"type":"integer","description":"Length in minutes when no end is given (default 60)"},"location":{"type":"string"},"notes":{"type":"string"}},"required":["title","start"]}"#,
            causesEgress: false,
            causesDeviceAction: true
        )
    }

    func execute(argumentsJSON: String) async -> ToolOutput {
        guard let arguments = decodeArguments(Arguments.self, from: argumentsJSON), !arguments.title.isEmpty else {
            return ToolOutput(content: "Expected at least \"title\" and \"start\".", isError: true)
        }
        guard let start = DeviceActionDates.parse(arguments.start) else {
            return ToolOutput(content: "Could not read the start date \"\(arguments.start)\". Use YYYY-MM-DDTHH:MM.", isError: true)
        }
        let end = arguments.end.flatMap(DeviceActionDates.parse)
            ?? start.addingTimeInterval(Double(arguments.durationMinutes ?? 60) * 60)
        guard end > start else {
            return ToolOutput(content: "The event ends before it starts.", isError: true)
        }
        guard (try? await store.requestWriteOnlyAccessToEvents()) == true else {
            return ToolOutput(content: "The user hasn't granted calendar access. Ask them to allow it in Settings → Privacy → Calendars.", isError: true)
        }
        guard let calendar = store.defaultCalendarForNewEvents else {
            return ToolOutput(content: "No writable calendar is set up on this device.", isError: true)
        }
        let event = EKEvent(eventStore: store)
        event.title = arguments.title
        event.startDate = start
        event.endDate = end
        event.location = arguments.location
        event.notes = arguments.notes
        event.calendar = calendar
        do {
            try store.save(event, span: .thisEvent)
        } catch {
            return ToolOutput(content: "Couldn't save the event: \(error.localizedDescription)", isError: true)
        }
        let when = start.formatted(date: .abbreviated, time: .shortened)
        return ToolOutput(content: "Added \"\(arguments.title)\" to the calendar on \(when).")
    }
}

nonisolated struct ReminderTool: LocalTool {
    private struct Arguments: Decodable {
        var title: String
        var due: String?
        var notes: String?
    }

    let store: EKEventStore

    var spec: ToolSpec {
        ToolSpec(
            name: "create_reminder",
            summary: "Adds a reminder to the user's Reminders app, optionally with a due date in \"YYYY-MM-DDTHH:MM\" local time.",
            parametersJSONSchema: #"{"type":"object","properties":{"title":{"type":"string"},"due":{"type":"string","description":"Optional due date, e.g. \"2026-09-05T09:00\""},"notes":{"type":"string"}},"required":["title"]}"#,
            causesEgress: false,
            causesDeviceAction: true
        )
    }

    func execute(argumentsJSON: String) async -> ToolOutput {
        guard let arguments = decodeArguments(Arguments.self, from: argumentsJSON), !arguments.title.isEmpty else {
            return ToolOutput(content: "Expected a \"title\".", isError: true)
        }
        guard (try? await store.requestFullAccessToReminders()) == true else {
            return ToolOutput(content: "The user hasn't granted access to Reminders. Ask them to allow it in Settings → Privacy → Reminders.", isError: true)
        }
        guard let list = store.defaultCalendarForNewReminders() else {
            return ToolOutput(content: "No reminders list is set up on this device.", isError: true)
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = arguments.title
        reminder.notes = arguments.notes
        reminder.calendar = list
        if let due = arguments.due.flatMap(DeviceActionDates.parse) {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: due
            )
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        do {
            try store.save(reminder, commit: true)
        } catch {
            return ToolOutput(content: "Couldn't save the reminder: \(error.localizedDescription)", isError: true)
        }
        return ToolOutput(content: "Added the reminder \"\(arguments.title)\".")
    }
}

/// Places a call or opens a prefilled text. Both hand off to iOS, which asks
/// the user to confirm — the model never dials or sends anything on its own.
nonisolated struct PhoneTool: LocalTool {
    private struct Arguments: Decodable {
        var number: String
        var message: String?
    }

    /// Injected so tests don't need a UIApplication.
    let open: @Sendable (URL) async -> Bool

    init(open: (@Sendable (URL) async -> Bool)? = nil) {
        self.open = open ?? { url in
            await MainActor.run { UIApplication.shared.canOpenURL(url) }
                ? await UIApplication.shared.open(url)
                : false
        }
    }

    var spec: ToolSpec {
        ToolSpec(
            name: "start_call_or_text",
            summary: "Starts a phone call to a number, or opens a text message to it when \"message\" is given. iOS asks the user to confirm before anything is dialled or sent.",
            parametersJSONSchema: #"{"type":"object","properties":{"number":{"type":"string","description":"Phone number, digits and + only"},"message":{"type":"string","description":"Include to open a prefilled text instead of calling"}},"required":["number"]}"#,
            causesEgress: false,
            causesDeviceAction: true
        )
    }

    func execute(argumentsJSON: String) async -> ToolOutput {
        guard let arguments = decodeArguments(Arguments.self, from: argumentsJSON) else {
            return ToolOutput(content: "Expected a \"number\".", isError: true)
        }
        let digits = arguments.number.filter { $0.isNumber || $0 == "+" }
        guard digits.count >= 3 else {
            return ToolOutput(content: "\"\(arguments.number)\" is not a usable phone number.", isError: true)
        }
        let url: URL?
        if let message = arguments.message, !message.isEmpty {
            let body = message.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            url = URL(string: "sms:\(digits)&body=\(body)")
        } else {
            url = URL(string: "tel://\(digits)")
        }
        guard let url, await open(url) else {
            return ToolOutput(content: "This device can't place calls or send texts.", isError: true)
        }
        return arguments.message == nil
            ? ToolOutput(content: "Asked iOS to call \(digits); the user confirms on screen.")
            : ToolOutput(content: "Opened a text to \(digits) with the message ready to send.")
    }
}

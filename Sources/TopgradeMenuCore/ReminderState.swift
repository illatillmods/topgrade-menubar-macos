import Foundation

public enum ReminderState {
    public static let dueAfter: TimeInterval = 24 * 60 * 60

    public static func isDue(lastUsed: Date?, now: Date = Date()) -> Bool {
        guard let lastUsed else {
            return true
        }

        // A clock correction that puts lastUsed in the future should not create a
        // false overdue warning. The next minute tick will reevaluate the state.
        return max(0, now.timeIntervalSince(lastUsed)) >= dueAfter
    }
}

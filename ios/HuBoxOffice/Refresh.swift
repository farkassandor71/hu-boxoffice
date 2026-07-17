import BackgroundTasks
import UserNotifications

/// Schedules an occasional background refresh and notifies when a new monthly
/// snapshot lands. The source updates once a month (between the 1st and 10th), so
/// this is intentionally infrequent — the on-launch refresh in HuBoxOfficeApp is the
/// primary path; this just surfaces new data when the app hasn't been opened.
enum Refresh {
    static let taskID = "hu.filmforgalmazok.HuBoxOffice.refresh"

    /// Register the launch handler. Must run before the app finishes launching.
    static func register(store: FilmStore) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            handle(task, store: store)
        }
    }

    /// Ask permission to post the "new data" notification. No-op if already decided.
    static func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge]) { _, _ in }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        // Not before ~a day from now; the system decides the actual time.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask, store: FilmStore) {
        schedule()  // always queue the next one
        let work = Task { @MainActor in
            let previous = store.latestSnapshot
            let changed = await store.refresh()
            if changed, store.latestSnapshot != previous {
                notifyNewData(snapshot: store.latestSnapshot)
            }
            task.setTaskCompleted(success: changed)
        }
        task.expirationHandler = { work.cancel() }
    }

    private static func notifyNewData(snapshot: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Frissült box office adatok"
        content.body = snapshot.map { "Új összesítés: \(Format.date($0))" }
            ?? "Új adatok érhetők el."
        let req = UNNotificationRequest(
            identifier: "new-data", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

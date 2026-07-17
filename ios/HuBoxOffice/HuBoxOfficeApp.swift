import SwiftUI

@main
struct HuBoxOfficeApp: App {
    @StateObject private var store: FilmStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = FilmStore()
        _store = StateObject(wrappedValue: store)
        Refresh.register(store: store)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    store.load()
                    Refresh.requestNotificationPermission()
                    await store.refresh()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Refresh.schedule() }
        }
    }
}

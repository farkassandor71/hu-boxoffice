import SwiftUI

@main
struct BoxOfficeHUMacApp: App {
    @StateObject private var store = FilmStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    store.load()
                    await store.refresh()
                }
                .frame(minWidth: 480, minHeight: 600)
        }
    }
}

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
                .frame(minWidth: 760, idealWidth: 900, minHeight: 600, idealHeight: 720)
        }
    }
}

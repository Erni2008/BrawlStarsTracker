import SwiftUI

@main
struct BrawlTrophyTrackerApp: App {
    @StateObject private var store = TrackerStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

import SwiftUI

@main
struct SetWatchApp: App {
    @State private var link = WatchSessionLink()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(link)
        }
    }
}

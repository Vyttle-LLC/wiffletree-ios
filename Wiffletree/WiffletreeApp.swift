import SwiftUI
import WiffletreeDesignSystem

@main
struct WiffletreeApp: App {
    @State private var app = AppModel(.live())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Tidal.accent)
        }
    }
}

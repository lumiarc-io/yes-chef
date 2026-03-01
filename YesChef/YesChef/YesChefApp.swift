import SwiftUI
import FirebaseCore

@main
struct ChefApp: App {
    init() {
        FirebaseApp.configure()
    }

    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

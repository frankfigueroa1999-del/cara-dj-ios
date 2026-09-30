import SwiftUI

@main
struct CaraDJApp: App {
    @StateObject private var engine = Engine()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .environmentObject(Config.shared)
                .preferredColorScheme(.dark)
        }
    }
}

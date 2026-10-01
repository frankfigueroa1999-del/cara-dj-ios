import SwiftUI

@main
struct CaraDJApp: App {
    @State private var engine = Engine()
    @State private var router = Router()

    init() {
        // keep downloaded covers on the phone so they appear instantly next time
        URLCache.shared = URLCache(memoryCapacity: 48 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engine)
                .environment(router)
                .environment(Library.shared)
                .environment(Toasts.shared)
                .environmentObject(Config.shared)
        }
    }
}

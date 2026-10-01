import Foundation
import Observation

enum AppTab: Hashable {
    case home, cara, library, search
}

/// Every page you can open on top of a tab.
enum Route: Hashable {
    case album(Album)
    case artist(Artist)
    case playlist(Playlist)
    case liked
    case playlists
    case albums
    case artists
    case genre(Genre)
}

/// Which tab you're on, what's open on each one, and the sheets that can pop up.
@MainActor
@Observable
final class Router {
    var tab: AppTab = .home
    var home: [Route] = []
    var cara: [Route] = []
    var library: [Route] = []
    var search: [Route] = []
    var showPlayer = false
    var showSettings = false
    var addToPlaylist: Track? = nil

    /// Open a page on the current tab. If the big player is up, it slides away first.
    func open(_ r: Route) {
        if showPlayer {
            showPlayer = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 380_000_000)
                self.push(r)
            }
        } else {
            push(r)
        }
    }

    private func push(_ r: Route) {
        switch tab {
        case .home: home.append(r)
        case .cara: cara.append(r)
        case .library: library.append(r)
        case .search: search.append(r)
        }
    }

    func select(_ t: AppTab) {
        if tab == t {
            switch t {             // tapping the tab you're already on goes back to its first page
            case .home: home = []
            case .cara: cara = []
            case .library: library = []
            case .search: search = []
            }
        } else {
            tab = t
        }
    }
}

struct ToastItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let symbol: String
}

/// Little "Added to Queue" style messages.
@MainActor
@Observable
final class Toasts {
    static let shared = Toasts()
    var current: ToastItem? = nil
    private var hideTask: Task<Void, Never>? = nil

    func show(_ text: String, _ symbol: String = "checkmark") {
        current = ToastItem(text: text, symbol: symbol)
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_900_000_000)
            if !Task.isCancelled { self.current = nil }
        }
    }
}

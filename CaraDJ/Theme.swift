import SwiftUI
import UIKit

enum Theme {
    /// The Apple Music pink-red, which also happens to be very Non Stop Pop.
    static let accent = Color(red: 0.98, green: 0.18, blue: 0.29)
    static let caraPurple = Color(red: 0.47, green: 0.16, blue: 0.62)
    static let caraNight = Color(red: 0.10, green: 0.05, blue: 0.20)
    static let hPad: CGFloat = 20
    /// Room left at the bottom of every page for the mini player and tab bar.
    static let tabBarHeight: CGFloat = 50
    static let miniHeight: CGFloat = 58
    static let caraGradient = LinearGradient(colors: [accent, caraPurple, caraNight], startPoint: .topLeading, endPoint: .bottomTrailing)
}

@MainActor
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func firm() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

/// Buttons that squish a little when you press them.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// The big round player buttons: a soft circle shows up behind them while pressed, like Apple Music.
struct TransportStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0))
                    .frame(width: 76, height: 76)
            )
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        if let act = action {
            Button(action: act) { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(title).font(.title2.weight(.bold)).foregroundStyle(Color.primary)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 0)
            }
            if let s = subtitle {
                Text(s).font(.subheadline).foregroundStyle(Color.secondary)
            }
        }
        .padding(.horizontal, Theme.hPad)
        .contentShape(Rectangle())
    }
}

/// "Play" and "Shuffle", side by side, the Apple Music way.
struct PlayShuffleButtons: View {
    var play: () -> Void
    var shuffle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            pill("Play", "play.fill", play)
            pill("Shuffle", "shuffle", shuffle)
        }
        .padding(.horizontal, Theme.hPad)
    }

    private func pill(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

struct ExplicitBadge: View {
    var body: some View {
        Text("E")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(Color(.systemBackground))
            .frame(width: 13, height: 13)
            .background(Color.secondary, in: RoundedRectangle(cornerRadius: 2.5, style: .continuous))
    }
}

/// The little bouncing bars next to the song that's playing.
struct EqualizerBars: View {
    var playing: Bool
    var color: Color = Theme.accent
    var height: CGFloat = 13

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let wave = abs(sin(t * (2.1 + Double(i) * 0.65) + Double(i) * 1.7))
                    let h: CGFloat = playing ? CGFloat(0.25 + 0.75 * wave) : 0.3
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: 3, height: height * h)
                }
            }
            .frame(width: 18, height: height, alignment: .bottom)
        }
    }
}

/// The Non Stop Pop waveform logo (the app icon), which dances while Cara is live.
struct StationLogo: View {
    var active: Bool
    var color: Color = .white
    static let base: [Double] = [0.35, 0.65, 1.0, 0.55, 0.85, 0.45, 0.7]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !active)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                let base = StationLogo.base
                let gap = g.size.width / CGFloat(base.count * 2 - 1)
                HStack(alignment: .center, spacing: gap) {
                    ForEach(0..<base.count, id: \.self) { i in
                        let wobble = active ? 0.72 + 0.28 * sin(t * (2.6 + Double(i) * 0.9) + Double(i) * 1.3) : 1.0
                        Capsule()
                            .fill(color)
                            .frame(width: gap, height: g.size.height * CGFloat(base[i] * wobble))
                    }
                }
                .frame(width: g.size.width, height: g.size.height)
            }
        }
    }
}

/// A capsule that reads "LIVE" with a pulsing dot.
struct LiveBadge: View {
    var text: String = "LIVE"
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
                .opacity(pulse ? 0.35 : 1)
            Text(text).font(.system(size: 11, weight: .heavy)).tracking(1)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Theme.accent, in: Capsule())
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// A friendly message for empty or not-yet-loaded pages.
struct EmptyNote: View {
    var symbol: String
    var title: String
    var message: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Color.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
            if let b = buttonTitle, let act = action {
                Button {
                    act()
                } label: {
                    Text(b)
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 36)
        .padding(.vertical, 40)
    }
}

extension View {
    /// Room at the bottom of a page so the mini player and tab bar never cover the last row.
    func chromeInset() -> some View {
        self.contentMargins(.bottom, Theme.tabBarHeight + Theme.miniHeight + 26, for: .scrollContent)
    }
}

/// A tiny progress spinner row for lists that load more as you scroll.
struct LoadingRow: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.vertical, 18)
    }
}

extension Color {
    /// A two-tone gradient pair from a hue, for the browse tiles.
    static func tile(_ hue: Double) -> LinearGradient {
        LinearGradient(colors: [Color(hue: hue, saturation: 0.75, brightness: 0.85),
                                Color(hue: hue + 0.06 > 1 ? hue + 0.06 - 1 : hue + 0.06, saturation: 0.85, brightness: 0.55)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

import SwiftUI
import UIKit
import Observation

enum Theme {
    /// The Apple Music pink-red, which also happens to be very Non Stop Pop. Used sparingly.
    static let accent = Color(red: 0.98, green: 0.18, blue: 0.29)
    static let caraPurple = Color(red: 0.47, green: 0.16, blue: 0.62)
    static let caraNight = Color(red: 0.10, green: 0.05, blue: 0.20)
    /// The deep near-black every page starts from.
    static let ink = Color(red: 0.035, green: 0.035, blue: 0.05)
    /// Secondary and tertiary text on glass.
    static let text2 = Color.white.opacity(0.62)
    static let text3 = Color.white.opacity(0.38)
    /// Hairlines between rows.
    static let line = Color.white.opacity(0.08)
    static let hPad: CGFloat = 20
    /// The floating tab bar and mini player.
    static let tabBarHeight: CGFloat = 62
    static let miniHeight: CGFloat = 60
    static let caraGradient = LinearGradient(colors: [accent, caraPurple, caraNight], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// The gentle spring used for everything that moves.
    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.86)
}

@MainActor
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func firm() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

// MARK: - Frosted glass
/// Glass, the light way: every page already sits on a soft, blurred colour, so a faint white wash with a
/// hairline edge reads as frosted glass without blurring anything a second time (scrolling stays smooth).
struct GlassCard: ViewModifier {
    var corner: CGFloat
    var tint: Double

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let wash = LinearGradient(colors: [Color.white.opacity(tint + 0.035), Color.white.opacity(tint)],
                                  startPoint: .top, endPoint: .bottom)
        let edge = LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.05)],
                                  startPoint: .top, endPoint: .bottom)
        return content
            .background(shape.fill(wash))
            .overlay(shape.strokeBorder(edge, lineWidth: 0.7))
    }
}

extension View {
    /// A frosted glass card.
    func glass(_ corner: CGFloat = 20, tint: Double = 0.06) -> some View {
        modifier(GlassCard(corner: corner, tint: tint))
    }

    /// Real frosted glass that blurs whatever moves behind it (the tab bar, the mini player, toasts).
    func frosted(_ corner: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7))
    }

    /// Every page sits on the same soft, blurred colour of what's playing (or of its own cover).
    func frostedPage(art: String? = nil) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background { AmbientBackdrop(art: art) }
    }

    /// Room at the bottom of a page so the mini player and tab bar never cover the last row.
    func chromeInset() -> some View {
        self.contentMargins(.bottom, Theme.tabBarHeight + Theme.miniHeight + 40, for: .scrollContent)
    }
}

// MARK: - The colour behind every page
/// A small, very soft copy of the cover that's playing, shared by every page.
@MainActor
@Observable
final class Ambience {
    static let shared = Ambience()
    private(set) var image: UIImage? = nil
    private(set) var brightness: Double = 0.3
    private(set) var key = ""
    private var wanted = ""
    private static var made: [String: (image: UIImage, brightness: Double)] = [:]

    /// Follow the cover of what's playing. Keeps the last colour when nothing is.
    func follow(_ art: String) async {
        wanted = art
        guard !art.isEmpty, art != key else { return }
        guard let a = await Ambience.make(art), wanted == art else { return }
        withAnimation(.easeInOut(duration: 1.2)) {
            image = a.image
            brightness = a.brightness
            key = art
        }
    }

    static func make(_ art: String) async -> (image: UIImage, brightness: Double)? {
        if let done = made[art] { return done }
        guard let src = await ImageCache.shared.load(art, px: 300) else { return nil }
        guard let out = await ArtColors.ambient(from: src) else { return nil }
        if made.count > 60 { made.removeAll() }
        made[art] = out
        return out
    }
}

/// The backdrop itself: the blurred cover, deepened towards the bottom so text always reads.
struct AmbientBackdrop: View {
    /// A page's own cover (album, playlist, artist); nil follows what's playing.
    var art: String? = nil
    @State private var own: UIImage? = nil
    @State private var ownBright: Double = 0.3
    @State private var ownKey = ""

    var body: some View {
        let shared = Ambience.shared
        let useOwn = !(art ?? "").isEmpty && own != nil
        let img: UIImage? = useOwn ? own : shared.image
        let key: String = useOwn ? ownKey : shared.key
        let bright: Double = useOwn ? ownBright : shared.brightness
        // bright covers get a little extra shade, so white text always reads
        let shade: Double = min(0.42, max(0, bright - 0.3) * 0.8)
        return ZStack {
            Theme.ink
            if let im = img {
                Color.clear
                    .overlay {
                        Image(uiImage: im)
                            .resizable()
                            .interpolation(.medium)
                            .scaledToFill()
                            .scaleEffect(1.25)
                    }
                    .clipped()
                    .id(key)
                    .transition(.opacity)
                Color.black.opacity(shade)
            } else {
                CaraGlow()
            }
            LinearGradient(stops: [
                .init(color: Color.black.opacity(0.28), location: 0),
                .init(color: Color.black.opacity(0.52), location: 0.42),
                .init(color: Color.black.opacity(0.80), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: art ?? "") {
            guard let a = art, !a.isEmpty, a != ownKey else { return }
            if let made = await Ambience.make(a), !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.6)) {
                    own = made.image
                    ownBright = made.brightness
                    ownKey = a
                }
            }
        }
    }
}

/// Cara's colours, softly glowing (before anything has played).
struct CaraGlow: View {
    var body: some View {
        ZStack {
            RadialGradient(colors: [Theme.accent.opacity(0.42), .clear], center: UnitPoint(x: 0.12, y: 0.08), startRadius: 0, endRadius: 430)
            RadialGradient(colors: [Theme.caraPurple.opacity(0.62), .clear], center: UnitPoint(x: 0.92, y: 0.38), startRadius: 0, endRadius: 470)
            RadialGradient(colors: [Color(red: 0.14, green: 0.2, blue: 0.56).opacity(0.5), .clear], center: UnitPoint(x: 0.25, y: 0.96), startRadius: 0, endRadius: 430)
        }
    }
}

// MARK: - Buttons
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

/// A white pill (the main action) or a glass pill (everything else).
struct PillLabel: View {
    var title: String
    var icon: String? = nil
    var primary = true
    var height: CGFloat = 48
    var fill = true

    var body: some View {
        HStack(spacing: 7) {
            if let i = icon { Image(systemName: i).font(.system(size: 15, weight: .semibold)) }
            Text(title).font(.system(size: 16, weight: .semibold))
        }
        .foregroundStyle(primary ? Color.black : Color.white)
        .padding(.horizontal, 20)
        .frame(maxWidth: fill ? .infinity : nil, minHeight: height)
        .background {
            if primary {
                Capsule().fill(Color.white)
            } else {
                Capsule().fill(Color.white.opacity(0.1))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7))
            }
        }
        .contentShape(Capsule())
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
                Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(Color.white)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.text3)
                }
                Spacer(minLength: 0)
            }
            if let s = subtitle {
                Text(s).font(.system(size: 14)).foregroundStyle(Theme.text2)
            }
        }
        .padding(.horizontal, Theme.hPad)
        .contentShape(Rectangle())
    }
}

/// "Play" and "Shuffle", side by side.
struct PlayShuffleButtons: View {
    var play: () -> Void
    var shuffle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.tap()
                play()
            } label: {
                PillLabel(title: "Play", icon: "play.fill", primary: true)
            }
            .buttonStyle(PressableStyle())
            Button {
                Haptics.tap()
                shuffle()
            } label: {
                PillLabel(title: "Shuffle", icon: "shuffle", primary: false)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, Theme.hPad)
    }
}

struct ExplicitBadge: View {
    var body: some View {
        Text("E")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(Color.black)
            .frame(width: 13, height: 13)
            .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 2.5, style: .continuous))
    }
}

/// The little bouncing bars next to the song that's playing.
struct EqualizerBars: View {
    var playing: Bool
    var color: Color = Theme.accent
    var height: CGFloat = 13

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !playing)) { ctx in
            bars(at: ctx.date)
        }
    }

    private func bars(at date: Date) -> some View {
        let t: Double = date.timeIntervalSinceReferenceDate
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 3, height: height * EqualizerBars.level(i, t, playing))
            }
        }
        .frame(width: 18, height: height, alignment: .bottom)
    }

    static func level(_ i: Int, _ t: Double, _ playing: Bool) -> CGFloat {
        if !playing { return 0.3 }
        let speed: Double = 2.1 + Double(i) * 0.65
        let phase: Double = Double(i) * 1.7
        let wave: Double = abs(sin(t * speed + phase))
        return CGFloat(0.25 + 0.75 * wave)
    }
}

/// The Non Stop Pop waveform logo (the app icon), which dances while Cara is live.
struct StationLogo: View {
    var active: Bool
    var color: Color = .white
    static let base: [Double] = [0.35, 0.65, 1.0, 0.55, 0.85, 0.45, 0.7]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !active)) { ctx in
            GeometryReader { g in
                logo(size: g.size, t: ctx.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func logo(size: CGSize, t: Double) -> some View {
        let count = StationLogo.base.count
        let gap: CGFloat = size.width / CGFloat(count * 2 - 1)
        return HStack(alignment: .center, spacing: gap) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: gap, height: size.height * StationLogo.level(i, t, active))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    static func level(_ i: Int, _ t: Double, _ active: Bool) -> CGFloat {
        let b: Double = base[i]
        if !active { return CGFloat(b) }
        let speed: Double = 2.6 + Double(i) * 0.9
        let phase: Double = Double(i) * 1.3
        let wobble: Double = 0.72 + 0.28 * sin(t * speed + phase)
        return CGFloat(b * wobble)
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
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.text2)
                .frame(width: 72, height: 72)
                .glass(36)
                .padding(.bottom, 4)
            Text(title).font(.system(size: 19, weight: .semibold)).foregroundStyle(Color.white)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
            if let b = buttonTitle, let act = action {
                Button {
                    act()
                } label: {
                    PillLabel(title: b, primary: true, height: 44, fill: false)
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

/// A tiny progress spinner row for lists that load more as you scroll.
struct LoadingRow: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView().tint(Color.white)
            Spacer()
        }
        .padding(.vertical, 18)
    }
}

extension Color {
    /// A two-tone gradient pair from a hue, for the browse tiles.
    static func tile(_ hue: Double) -> LinearGradient {
        LinearGradient(colors: [Color(hue: hue, saturation: 0.62, brightness: 0.78),
                                Color(hue: hue + 0.06 > 1 ? hue + 0.06 - 1 : hue + 0.06, saturation: 0.78, brightness: 0.42)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

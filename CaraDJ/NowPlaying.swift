import SwiftUI
import UIKit
import MediaPlayer

enum NPMode: Equatable {
    case art, lyrics, queue, cara, about
}

/// The big player that slides up from the mini player.
struct NowPlayingView: View {
    @Environment(Engine.self) private var engine
    @Environment(Router.self) private var router
    @Environment(Library.self) private var library
    @State private var mode: NPMode = .art
    @State private var cover: UIImage? = nil
    @State private var coverKey = ""
    @State private var backdrop: UIImage? = nil
    @State private var brightness: Double = 0.4
    @State private var lyrics = LyricsStore()
    @State private var about = AboutStore()
    @State private var showDevices = false
    @State private var playlistTrack: Track? = nil
    @Namespace private var ns

    private var item: Track? { engine.displayItem }
    private var spring: Animation { .spring(response: 0.5, dampingFraction: 0.86) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                NPBackground(image: backdrop, key: coverKey, brightness: brightness, playing: engine.now.isPlaying)
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 38, height: 5)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    if mode == .art {
                        artSection(width: geo.size.width, height: geo.size.height)
                    } else {
                        compactHeader
                            .padding(.horizontal, 24)
                        modeContent
                            .frame(maxHeight: .infinity)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    controls
                        .padding(.horizontal, 28)
                        .padding(.bottom, geo.safeAreaInsets.bottom > 0 ? 2 : 14)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .overlay { ToastOverlay() }
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showDevices) {
            DevicesSheet()
                .environment(engine)
                .environment(\.colorScheme, .dark)
        }
        .sheet(item: $playlistTrack) { t in
            AddToPlaylistSheet(track: t)
                .environment(engine)
                .environment(router)
                .environment(library)
                .environment(Toasts.shared)
                .presentationDetents([.medium, .large])
        }
        .task(id: item?.art ?? "") { await loadCover() }
        .task(id: engine.now.item?.uri ?? "") {
            await lyrics.load(engine.now.item, durationMs: engine.now.durationMs)
        }
        .task(id: aboutKey) {
            if mode == .about { await about.load(engine.now.item) }
        }
        .task { await engine.refreshQueue() }
    }

    private var aboutKey: String { (mode == .about ? "on|" : "off|") + (engine.now.item?.uri ?? "") }

    // MARK: big cover + title
    @ViewBuilder
    private func artSection(width: CGFloat, height: CGFloat) -> some View {
        let side = max(120, min(width - 52, height - 390, 430))
        let up = engine.now.isPlaying || engine.speaking
        Spacer(minLength: 6)
        coverView(corner: 12)
            .matchedGeometryEffect(id: "cover", in: ns)
            .frame(width: side, height: side)
            .overlay(alignment: .bottom) {
                if engine.speaking && !engine.line.isEmpty {
                    CaraCaption(text: engine.line)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .scaleEffect(up ? 1 : 0.8)
            .shadow(color: Color.black.opacity(up ? 0.45 : 0.25), radius: up ? 28 : 12, y: up ? 16 : 6)
            .animation(.spring(response: 0.55, dampingFraction: 0.7), value: up)
            .animation(.easeInOut(duration: 0.35), value: engine.speaking)
            .onTapGesture(count: 2) {
                Haptics.tap()
                Task { await engine.toggleLikeCurrent() }
            }
        Spacer(minLength: 6)
        titleRow
            .padding(.horizontal, 26)
            .padding(.bottom, 4)
    }

    private func coverView(corner: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .overlay {
                if let img = cover {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .id(coverKey)
                        .transition(.opacity)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 54, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item?.title ?? (engine.connected ? "Not Playing" : "Not Connected"))
                    .font(.system(size: 21, weight: .semibold))
                    .lineLimit(1)
                Button {
                    if let t = item, !t.artistID.isEmpty { router.open(.artist(t.artistRef)) }
                } label: {
                    Text(item?.artistLine ?? "Play something in Spotify")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            likeButton
            moreMenu
        }
        .foregroundStyle(Color.white)
    }

    private var compactHeader: some View {
        HStack(spacing: 12) {
            coverView(corner: 6)
                .matchedGeometryEffect(id: "cover", in: ns)
                .frame(width: 60, height: 60)
                .shadow(color: Color.black.opacity(0.3), radius: 8, y: 4)
                .onTapGesture { withAnimation(spring) { mode = .art } }
            VStack(alignment: .leading, spacing: 2) {
                Text(item?.title ?? "Not Playing")
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Text(item?.artistLine ?? "")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            likeButton
            moreMenu
        }
        .foregroundStyle(Color.white)
        .padding(.vertical, 8)
    }

    private var likeButton: some View {
        let on = engine.currentLiked ?? false
        return Button {
            Haptics.tap()
            Task { await engine.toggleLikeCurrent() }
        } label: {
            Image(systemName: on ? "heart.fill" : "heart")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(on ? Theme.accent : Color.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.16), in: Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.85))
        .disabled(item == nil)
    }

    private var moreMenu: some View {
        Menu {
            if let t = item {
                let liked = engine.currentLiked ?? false
                Button {
                    Task { await engine.toggleLikeCurrent() }
                } label: {
                    Label(liked ? "Remove from Liked Songs" : "Add to Liked Songs", systemImage: liked ? "heart.slash" : "heart")
                }
                Button {
                    playlistTrack = t
                } label: {
                    Label("Add to a Playlist…", systemImage: "text.badge.plus")
                }
                Divider()
                if !t.albumID.isEmpty {
                    Button {
                        router.open(.album(t.albumRef))
                    } label: {
                        Label("Go to Album", systemImage: "square.stack")
                    }
                }
                if !t.artistID.isEmpty {
                    Button {
                        router.open(.artist(t.artistRef))
                    } label: {
                        Label("Go to Artist", systemImage: "music.mic")
                    }
                }
                Button {
                    withAnimation(spring) { mode = .about }
                } label: {
                    Label("About This Song", systemImage: "info.circle")
                }
            }
            Menu {
                Button("Off") { engine.setSleep(minutes: nil) }
                Button("15 Minutes") { engine.setSleep(minutes: 15) }
                Button("30 Minutes") { engine.setSleep(minutes: 30) }
                Button("45 Minutes") { engine.setSleep(minutes: 45) }
                Button("1 Hour") { engine.setSleep(minutes: 60) }
                Button("End of Song") { engine.setSleepAtEndOfSong() }
            } label: {
                Label(sleepLabel, systemImage: "moon.zzz")
            }
            if let u = item?.shareURL {
                ShareLink(item: u) {
                    Label("Share Song", systemImage: "square.and.arrow.up")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.16), in: Circle())
        }
    }

    private var sleepLabel: String {
        if engine.sleepAtTrackEnd { return "Sleep Timer: End of Song" }
        if let s = engine.sleepAt {
            let mins = max(1, Int(s.timeIntervalSinceNow / 60.0 + 0.5))
            return "Sleep Timer: \(mins) min left"
        }
        return "Sleep Timer"
    }

    // MARK: lyrics / queue / Cara / about
    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .lyrics: LyricsPanel(lyrics: lyrics)
        case .queue: QueuePanel(onAddToPlaylist: { t in playlistTrack = t })
        case .cara: CaraPanel()
        case .about: AboutPanel(about: about)
        case .art: EmptyView()
        }
    }

    // MARK: scrubber, buttons, volume
    private var controls: some View {
        VStack(spacing: 0) {
            Scrubber()
                .padding(.top, 8)
            transport
                .padding(.vertical, mode == .art ? 16 : 8)
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.6))
                SystemVolumeSlider()
                    .frame(height: 30)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .padding(.bottom, 14)
            bottomRow
            if !engine.now.onThisPhone && !engine.now.deviceName.isEmpty {
                Label("Playing on \(engine.now.deviceName)", systemImage: "hifispeaker.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 6)
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 0) {
            Spacer()
            Button {
                Haptics.tap()
                Task { await engine.previous() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 32))
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(TransportStyle())
            Spacer()
            Button {
                Haptics.firm()
                Task { await engine.togglePlay() }
            } label: {
                Image(systemName: engine.now.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 46))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 72, height: 72)
            }
            .buttonStyle(TransportStyle())
            Spacer()
            Button {
                Haptics.tap()
                Task { await engine.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 32))
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(TransportStyle())
            Spacer()
        }
        .foregroundStyle(Color.white)
    }

    private var bottomRow: some View {
        HStack(spacing: 0) {
            modeButton(.lyrics, icon: "quote.bubble")
            Spacer()
            Button {
                Haptics.tap()
                showDevices = true
            } label: {
                Image(systemName: engine.now.onThisPhone ? "airplayaudio" : "hifispeaker.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(engine.now.onThisPhone ? Color.white.opacity(0.75) : Theme.accent)
                    .frame(width: 46, height: 36)
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            Spacer()
            modeButton(.cara, icon: "dot.radiowaves.left.and.right")
                .overlay(alignment: .topTrailing) {
                    if engine.running {
                        Circle().fill(Theme.accent).frame(width: 8, height: 8).offset(x: 2, y: -2)
                    }
                }
            Spacer()
            modeButton(.queue, icon: "list.bullet")
        }
        .padding(.horizontal, 18)
    }

    private func modeButton(_ m: NPMode, icon: String) -> some View {
        let active = mode == m
        return Button {
            Haptics.tap()
            withAnimation(spring) { mode = active ? .art : m }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(active ? Color.black.opacity(0.85) : Color.white.opacity(0.75))
                .frame(width: 46, height: 36)
                .background(active ? Color.white.opacity(0.88) : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.9))
    }

    private func loadCover() async {
        guard let it = item, !it.art.isEmpty else { return }
        let key = it.art
        if key == coverKey { return }
        guard let img = await ImageCache.shared.load(key, px: 1000) else { return }
        if Task.isCancelled { return }
        let bd = await ArtColors.backdrop(from: img)
        if Task.isCancelled { return }
        withAnimation(.easeInOut(duration: 0.6)) {
            cover = img
            coverKey = key
            backdrop = bd.image
            brightness = bd.brightness
        }
    }
}

// MARK: - The moving colours behind the player
struct NPBackground: View {
    let image: UIImage?
    let key: String
    let brightness: Double
    let playing: Bool

    var body: some View {
        ZStack {
            Color(white: 0.13)
            if let img = image {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !playing)) { ctx in
                    GeometryReader { g in
                        spinning(img, size: g.size, angle: NPBackground.angle(ctx.date))
                    }
                }
                .id(key)
                .transition(.opacity)
            }
            Color.black.opacity(0.16 + 0.38 * brightness)
        }
        .ignoresSafeArea()
    }

    private func spinning(_ img: UIImage, size: CGSize, angle: Angle) -> some View {
        let side: CGFloat = max(size.width, size.height) * 1.7
        return Image(uiImage: img)
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
            .rotationEffect(angle)
            .position(x: size.width / 2, y: size.height / 2)
    }

    static func angle(_ date: Date) -> Angle {
        let t: Double = date.timeIntervalSinceReferenceDate
        let turn: Double = t.truncatingRemainder(dividingBy: 160) * 2.25
        return .degrees(turn)
    }
}

/// Her line, shown on the cover while she's talking.
struct CaraCaption: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            LiveBadge(text: "CARA")
            Text(text.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(10)
    }
}

// MARK: - Scrubber
struct Scrubber: View {
    @Environment(Engine.self) private var engine
    @State private var dragFrac: Double? = nil
    @State private var startFrac: Double = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            content(liveFraction())
        }
    }

    private var durationMs: Int { max(engine.now.durationMs, 1) }

    private func liveFraction() -> Double {
        if engine.pendingItem != nil { return 0 }
        let cur: Int = min(engine.now.currentProgressMs, durationMs)
        return Double(cur) / Double(durationMs)
    }

    private func content(_ live: Double) -> some View {
        let frac: Double = dragFrac ?? live
        let dur: Int = durationMs
        let shown: Int = Int(frac * Double(dur))
        let active: Bool = dragFrac != nil
        return VStack(spacing: 6) {
            GeometryReader { g in
                bar(width: max(g.size.width, 1), frac: frac, live: live, active: active)
            }
            .frame(height: 22)
            HStack {
                Text(formatClock(shown))
                Spacer()
                Text("-" + formatClock(max(0, dur - shown)))
            }
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(Color.white.opacity(active ? 0.9 : 0.55))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: active)
    }

    private func bar(width w: CGFloat, frac: Double, live: Double, active: Bool) -> some View {
        let filled: CGFloat = max(0, min(w, w * CGFloat(frac)))
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.22))
            Capsule()
                .fill(Color.white.opacity(active ? 0.95 : 0.72))
                .frame(width: filled)
        }
        .frame(height: active ? 12 : 7)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if dragFrac == nil {
                        startFrac = live
                        Haptics.soft()
                    }
                    let f: Double = startFrac + Double(v.translation.width / w)
                    dragFrac = min(max(f, 0), 1)
                }
                .onEnded { v in
                    if let f = dragFrac, abs(v.translation.width) > 2 {
                        let ms: Int = Int(f * Double(durationMs))
                        Task { await engine.seek(ms) }
                    }
                    dragFrac = nil
                }
        )
    }
}

/// The phone's own volume slider (works on the iPhone even though Spotify can't set it there).
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: .zero)
        v.showsRouteButton = false
        style(v)
        return v
    }

    func updateUIView(_ v: MPVolumeView, context: Context) {
        style(v)
    }

    private func style(_ v: MPVolumeView) {
        for sub in v.subviews {
            if let s = sub as? UISlider {
                s.minimumTrackTintColor = .white
                s.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)
                s.setThumbImage(SystemVolumeSlider.thumb, for: .normal)
            }
        }
    }

    static let thumb: UIImage = {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 14, height: 14))
        return r.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 14, height: 14))
        }
    }()
}

extension View {
    /// Fades the top and bottom edges of a scrolling panel.
    func edgeFade(_ top: CGFloat = 0.05, _ bottom: CGFloat = 0.92) -> some View {
        self.mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: top),
                .init(color: .black, location: bottom),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        )
    }
}

// MARK: - Lyrics
struct LyricsPanel: View {
    let lyrics: LyricsStore
    @Environment(Engine.self) private var engine

    var body: some View {
        if lyrics.hasSynced {
            ScrollViewReader { proxy in
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    let cur = lyrics.index(at: engine.now.currentProgressMs)
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(lyrics.lines) { line in
                                lineView(line, cur: cur)
                            }
                        }
                        .padding(.horizontal, 26)
                        .padding(.vertical, 120)
                    }
                    .edgeFade(0.08, 0.88)
                    .onChange(of: cur) { _, c in
                        if c >= 0 {
                            withAnimation(.spring(response: 0.7, dampingFraction: 0.9)) {
                                proxy.scrollTo(c, anchor: UnitPoint(x: 0.5, y: 0.3))
                            }
                        }
                    }
                    .onAppear {
                        if cur >= 0 { proxy.scrollTo(cur, anchor: UnitPoint(x: 0.5, y: 0.3)) }
                    }
                }
            }
        } else if !lyrics.plain.isEmpty {
            ScrollView(showsIndicators: false) {
                Text(lyrics.plain)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 24)
            }
            .edgeFade()
        } else {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "quote.bubble").font(.system(size: 34)).foregroundStyle(Color.white.opacity(0.5))
                Text(lyrics.status.isEmpty ? "No lyrics for this one." : lyrics.status)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func lineView(_ line: LyricLine, cur: Int) -> some View {
        let isNow = line.id == cur
        let opacity: Double = isNow ? 1 : (line.id < cur ? 0.3 : 0.42)
        return Text(line.text.isEmpty ? "\u{266A}" : line.text)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(Color.white.opacity(opacity))
            .scaleEffect(isNow ? 1 : 0.97, anchor: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.3), value: isNow)
            .id(line.id)
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.tap()
                Task { await engine.seek(line.timeMs) }
            }
    }
}

// MARK: - Playing next (with where Cara will talk)
struct QueuePanel: View {
    var onAddToPlaylist: (Track) -> Void
    @Environment(Engine.self) private var engine

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                if engine.upNext.isEmpty {
                    Text("Nothing's lined up. Spotify carries on from " + (engine.contextName.isEmpty ? "your music." : engine.contextName + "."))
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .padding(.vertical, 18)
                    if engine.breakSlot != nil { CaraMarker() }
                }
                ForEach(Array(engine.upNext.enumerated()), id: \.offset) { i, t in
                    if engine.breakSlot == i { CaraMarker() }
                    QueueRow(track: t, onAddToPlaylist: onAddToPlaylist) {
                        Task { await engine.skip(to: i) }
                    }
                }
                Text("Spotify doesn't let apps reorder or remove songs from the queue. Press and hold a song for more.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .padding(.top, 16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .edgeFade(0.0, 0.94)
        .task { await engine.refreshQueue() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Playing Next").font(.system(size: 20, weight: .bold))
                if !engine.contextName.isEmpty {
                    Text("From " + engine.contextName)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer()
            toggle(engine.now.shuffle ? "shuffle" : "shuffle", on: engine.now.shuffle) {
                Task { await engine.toggleShuffle() }
            }
            toggle(engine.now.repeatMode == "track" ? "repeat.1" : "repeat", on: engine.now.repeatMode != "off") {
                Task { await engine.cycleRepeat() }
            }
        }
        .foregroundStyle(Color.white)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private func toggle(_ icon: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(on ? Color.black.opacity(0.85) : Color.white.opacity(0.9))
                .frame(width: 46, height: 30)
                .background(on ? Color.white.opacity(0.88) : Color.white.opacity(0.14), in: Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
    }
}

struct QueueRow: View {
    let track: Track
    var onAddToPlaylist: (Track) -> Void
    var onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Artwork(track.artMid, px: 150, corner: 5)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(track.artistLine)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap()
            onTap()
        }
        .contextMenu {
            TrackMenuItems(track: track, onAddToPlaylist: onAddToPlaylist)
        }
    }
}

struct CaraMarker: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 30)
                .background(Theme.accent, in: Capsule())
            VStack(alignment: .leading, spacing: 1) {
                Text("Cara talks here")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text(styleText)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private var styleText: String {
        let s = engine.queued ?? engine.prepared?.style ?? ""
        switch s {
        case "talkover": return "Talking over the end of the song"
        case "intro": return "Over the start of the next song"
        case "silent": return "The music pauses while she talks"
        default: return "She picks the style when she's ready"
        }
    }
}

// MARK: - Cara's controls, right in the player
struct CaraPanel: View {
    @Environment(Engine.self) private var engine
    @EnvironmentObject private var cfg: Config

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    StationLogo(active: engine.running)
                        .frame(width: 46, height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cara").font(.system(size: 22, weight: .bold))
                        Text(engine.statusLine).font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.7))
                    }
                    Spacer()
                    Button {
                        Haptics.firm()
                        if engine.running { engine.stop() } else { engine.start() }
                    } label: {
                        Text(engine.running ? "End Show" : "Go Live")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(engine.running ? Color.white : Color.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(engine.running ? Color.white.opacity(0.18) : Color.white, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
                if !engine.line.isEmpty {
                    Text("\u{201C}" + engine.line.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression) + "\u{201D}")
                        .font(.system(size: 15, weight: .medium))
                        .italic()
                        .foregroundStyle(Color.white.opacity(0.85))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                label("NEXT TRANSITION")
                HStack(spacing: 8) {
                    queuePill("Talk Over", "talkover")
                    queuePill("Over Intro", "intro")
                    queuePill("Silent", "silent")
                }
                label("RIGHT NOW")
                HStack(spacing: 8) {
                    actionPill("Talk Now", "mic.fill") { engine.testBreak() }
                    actionPill("Pop In", "sparkles") { engine.testPopin() }
                    actionPill("Stinger", "bolt.fill") { Task { await engine.testStinger() } }
                }
                label("MOOD")
                Picker("Mood", selection: $cfg.mood) {
                    Text("Chill").tag("chill")
                    Text("Normal").tag("normal")
                    Text("Unhinged").tag("unhinged")
                    Text("Mixed").tag("mixed")
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 10)
        }
        .foregroundStyle(Color.white)
        .edgeFade(0.0, 0.95)
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(Color.white.opacity(0.55))
    }

    private func queuePill(_ title: String, _ style: String) -> some View {
        let on = engine.queued == style
        return Button {
            Haptics.tap()
            engine.queue(style)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? Color.black : Color.white)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(on ? Color.white : Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private func actionPill(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - About this song
struct AboutPanel: View {
    let about: AboutStore
    @Environment(Engine.self) private var engine
    @State private var bioOpen = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if !about.ready {
                    ProgressView().tint(Color.white).padding(.top, 40)
                }
                if !about.song.isEmpty {
                    InfoCard(title: "About the Song") {
                        Text(about.song)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineSpacing(3)
                        Text("From Wikipedia")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
                if !about.bio.isEmpty {
                    InfoCard(title: "About " + (engine.now.item?.artist ?? "the Artist")) {
                        if !about.genres.isEmpty {
                            Text(about.genres.map { $0.capitalized }.joined(separator: " · "))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        Text(about.bio)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineSpacing(3)
                            .lineLimit(bioOpen ? nil : 6)
                        if about.bio.count > 280 {
                            Button(bioOpen ? "Show Less" : "More") {
                                withAnimation(.easeInOut(duration: 0.25)) { bioOpen.toggle() }
                            }
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.white)
                        }
                    }
                }
                if let t = engine.now.item {
                    InfoCard(title: "Credits") {
                        ForEach(Array(t.artists.enumerated()), id: \.offset) { i, n in
                            credit(n, i == 0 ? "Main Artist" : "Featured Artist")
                        }
                        if !t.album.isEmpty { credit(t.album, "Album" + (t.year.isEmpty ? "" : " \u{00B7} " + t.year)) }
                        if t.release.count > 4 { credit(prettyDate(t.release), "Released") }
                        if !about.copyright.isEmpty { credit(about.copyright, "Copyright") }
                    }
                }
                if about.ready && about.song.isEmpty && about.bio.isEmpty {
                    Text("Couldn't find the story behind this one.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
        }
        .foregroundStyle(Color.white)
        .edgeFade(0.0, 0.95)
    }

    private func credit(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.system(size: 16)).lineLimit(2)
            Text(sub).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Speakers and other devices
struct DevicesSheet: View {
    @Environment(Engine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if engine.devices.isEmpty {
                        Text("No Spotify devices found. Open Spotify on the phone, computer or speaker you want to use.")
                            .foregroundStyle(Color.secondary)
                    }
                    ForEach(engine.devices) { d in
                        Button {
                            Haptics.tap()
                            Task {
                                await engine.transfer(to: d)
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: d.symbol)
                                    .font(.system(size: 20))
                                    .frame(width: 30)
                                    .foregroundStyle(d.isActive ? Theme.accent : Color.primary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.name).foregroundStyle(Color.primary)
                                    if d.isActive {
                                        Text("Playing now").font(.caption).foregroundStyle(Theme.accent)
                                    }
                                }
                                Spacer()
                                if d.isActive {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .disabled(d.isRestricted)
                    }
                } footer: {
                    Text("Cara's voice always comes out of this iPhone, so she sounds best when the music plays here too.")
                }
            }
            .navigationTitle("Play On")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await engine.loadDevices() }
            .refreshable { await engine.loadDevices() }
        }
        .presentationDetents([.medium, .large])
    }
}

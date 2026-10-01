import SwiftUI
import UIKit

/// The icons that came with the app (ai_*.png), so the player looks exactly like it always has.
enum Icon {
    static func img(_ n: String) -> Image { Image(uiImage: UIImage(named: n) ?? UIImage()) }
}

/// The big player: the frosted, full-screen look, with lyrics, Playing Next and the song's story
/// on cards underneath. Pull down from the top (or tap the little handle) to close it.
struct NowPlayingView: View {
    @Environment(Engine.self) private var engine
    @Environment(Router.self) private var router
    @Environment(Library.self) private var library
    @EnvironmentObject private var cfg: Config
    @State private var lyrics = LyricsStore()
    @State private var about = AboutStore()
    // the cover on screen; it only changes once the next one has fully loaded, then cross-fades
    @State private var shown: UIImage? = nil
    @State private var shownKey = ""
    @State private var accent = Color(red: 0.25, green: 0.2, blue: 0.2)
    @State private var inLyr = false
    @State private var closing = false
    @State private var showFullLyrics = false
    @State private var showFullQueue = false
    @State private var showDevices = false
    @State private var showCara = false
    @State private var bioOpen = false
    @State private var heartPop = false
    @State private var dragFrac: Double? = nil
    @State private var popular: [Track] = []
    @State private var popularFor = ""

    static let green = Color(red: 0.37, green: 0.82, blue: 0.43)
    private var item: Track? { engine.displayItem }
    private var springy: Animation { .spring(response: 0.5, dampingFraction: 0.86) }

    var body: some View {
        ZStack {
            background
            GeometryReader { g in
                page(g)
            }
        }
        .environment(\.colorScheme, .dark)
        .overlay {
            if showFullLyrics {
                GeometryReader { g in
                    fullLyrics(top: g.safeAreaInsets.top, bottom: g.safeAreaInsets.bottom)
                        .ignoresSafeArea()
                }
                .transition(.scale(scale: 0.88, anchor: .center).combined(with: .opacity))
            }
        }
        .overlay {
            if showFullQueue {
                GeometryReader { g in
                    fullQueue(top: g.safeAreaInsets.top, bottom: g.safeAreaInsets.bottom)
                        .ignoresSafeArea()
                }
                .transition(.scale(scale: 0.88, anchor: .center).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showDevices) {
            DevicesSheet()
                .environment(engine)
                .environment(\.colorScheme, .dark)
        }
        .sheet(isPresented: $showCara) {
            CaraOptionsSheet(onSettings: {
                showCara = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { router.showSettings = true }
            })
            .environment(engine)
            .environment(router)
            .environmentObject(cfg)
        }
        .task(id: item?.art ?? "") { await loadCover() }
        .task(id: engine.now.item?.uri ?? "") {
            await lyrics.load(engine.now.item, durationMs: engine.now.durationMs)
        }
        .task(id: "about|" + (engine.now.item?.uri ?? "")) { await loadAbout() }
    }

    // MARK: the whole scrolling page
    private func page(_ g: GeometryProxy) -> some View {
        let top = g.safeAreaInsets.top
        let bottom = g.safeAreaInsets.bottom
        let fullH = g.size.height + top + bottom
        let peek: CGFloat = 84 + bottom
        let pageH = fullH - peek
        let side = min(g.size.width * 0.84, fullH * 0.46, 420)
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                playerPage(top: top, side: side)
                    .frame(height: pageH)
                    .background(
                        GeometryReader { p in
                            Color.clear
                                .onChange(of: p.frame(in: .named("np")).minY) { _, y in
                                    scrolled(y, pageH: pageH)
                                }
                        }
                    )
                lyricsCard
                queueCard
                    .padding(.top, 14)
                infoCards
                Color.clear.frame(height: 40 + bottom)
            }
        }
        .coordinateSpace(.named("np"))
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            miniBar(top: top)
                .allowsHitTesting(inLyr)
        }
    }

    private func scrolled(_ y: CGFloat, pageH: CGFloat) {
        let past = -y > pageH * 0.8
        if past != inLyr { inLyr = past }
        // pulled down past the top: close the player
        if y > 110 && !closing {
            closing = true
            Haptics.soft()
            router.closePlayer()
        }
    }

    // MARK: the player itself
    private func playerPage(top: CGFloat, side: CGFloat) -> some View {
        VStack(spacing: 0) {
            grabber
            if !engine.connected {
                Button {
                    Task { await engine.connect(forceLogin: !engine.loggedIn) }
                } label: {
                    Text(engine.loggedIn ? "RECONNECT SPOTIFY" : "CONNECT SPOTIFY")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.top, 8)
            }
            Spacer(minLength: 8)
            cover(side: side)
            Spacer(minLength: 8).frame(maxHeight: 28)
            bottomPanel
            Spacer(minLength: 4).frame(maxHeight: 12)
        }
        .padding(.horizontal, 22)
        .padding(.top, top)
    }

    private var grabber: some View {
        Button {
            router.closePlayer()
        } label: {
            Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(width: 36, height: 5)
                .frame(width: 120, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close player")
    }

    private func cover(side: CGFloat) -> some View {
        ZStack {
            Color.white.opacity(0.08)
            if let img = shown {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .id(shownKey)
                    .transition(.opacity)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .bottom) {
            if engine.speaking && !engine.line.isEmpty {
                CaraCaption(text: engine.line)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            Image(systemName: "heart.fill")
                .font(.system(size: 84))
                .foregroundStyle(Color.white)
                .shadow(color: Color.black.opacity(0.35), radius: 12)
                .scaleEffect(heartPop ? 1 : 0.4)
                .opacity(heartPop ? 0.95 : 0)
        }
        .shadow(color: Color.black.opacity(0.5), radius: 22, y: 10)
        .animation(.easeInOut(duration: 0.35), value: engine.speaking)
        .onTapGesture(count: 2) { likeFromCover() }
    }

    private func likeFromCover() {
        guard engine.pendingItem == nil, item != nil else { return }
        Haptics.tap()
        if !(engine.currentLiked ?? false) { Task { await engine.toggleLikeCurrent() } }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { heartPop = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeOut(duration: 0.3)) { heartPop = false }
        }
    }

    // song name and artist, with the DJ on/off button and the "..." menu
    private var bottomPanel: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item?.title ?? (engine.connected ? "Nothing playing" : "Not connected"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)
                    Button {
                        if let t = item, !t.artistID.isEmpty { router.open(.artist(t.artistRef)) }
                    } label: {
                        Text(item?.artistLine ?? "Start a playlist in the Spotify app.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
                .shadow(color: Color.black.opacity(0.5), radius: 6)
                Spacer(minLength: 8)
                djButton
                moreButton
            }
            Spacer().frame(height: 26)
            progress
            Spacer().frame(height: 26)
            controls
            Spacer().frame(height: 22)
            deviceRow
        }
    }

    /// Cara on / off: white and filled while she's live. Press and hold for her quick actions.
    private var djButton: some View {
        Button {
            Haptics.firm()
            if engine.running { engine.stop() } else { engine.start() }
        } label: {
            Icon.img("ai_dj").renderingMode(.template).resizable().scaledToFit()
                .frame(width: 15, height: 15)
                .foregroundStyle(engine.running ? Color.black : Color.white)
                .frame(width: 30, height: 30)
                .background(engine.running ? AnyShapeStyle(Color.white) : AnyShapeStyle(Material.ultraThinMaterial), in: Circle())
        }
        .contextMenu {
            Button { engine.testBreak() } label: { Label("Talk Now", systemImage: "mic.fill") }
            Button { engine.testPopin() } label: { Label("Pop In Now", systemImage: "sparkles") }
            Button { Task { await engine.testStinger() } } label: { Label("Play a Stinger", systemImage: "bolt.fill") }
            Menu {
                Button("Talk Over") { engine.queue("talkover") }
                Button("Over the Intro") { engine.queue("intro") }
                Button("Silent") { engine.queue("silent") }
            } label: {
                Label("Next Transition", systemImage: "forward.end")
            }
            Divider()
            Button { showCara = true } label: { Label("Cara Options…", systemImage: "slider.horizontal.3") }
        }
    }

    private var moreButton: some View {
        Menu {
            if let t = item {
                let liked = engine.currentLiked ?? false
                Button {
                    Task { await engine.toggleLikeCurrent() }
                } label: {
                    Label(liked ? "Remove from Liked Songs" : "Add to Liked Songs", systemImage: liked ? "heart.slash" : "heart")
                }
                .disabled(engine.pendingItem != nil)
                Button {
                    router.addToPlaylist = t
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
            }
            Button {
                showCara = true
            } label: {
                Label("Cara Options…", systemImage: "dot.radiowaves.left.and.right")
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
            Icon.img("ai_more").renderingMode(.template).resizable().scaledToFit()
                .frame(width: 17, height: 6)
                .foregroundStyle(Color.white)
                .frame(width: 30, height: 30)
                .background(.ultraThinMaterial, in: Circle())
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

    // MARK: progress bar with a round handle; drag it to seek
    private var durMs: Int { max(engine.now.durationMs, 1) }

    private func liveFraction() -> Double {
        if engine.pendingItem != nil { return 0 }
        let cur: Int = min(engine.now.currentProgressMs, durMs)
        return Double(cur) / Double(durMs)
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            progressBody(liveFraction())
        }
    }

    private func progressBody(_ live: Double) -> some View {
        let dur: Int = durMs
        let frac: Double = dragFrac ?? live
        let shownMs: Int = Int(frac * Double(dur))
        return VStack(spacing: 2) {
            GeometryReader { g in
                progressTrack(width: max(g.size.width, 1), frac: frac, dur: dur)
            }
            .frame(height: 24)
            HStack {
                Text(formatClock(shownMs))
                Spacer()
                Text("-" + formatClock(max(0, dur - shownMs)))
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.65))
        }
    }

    private func progressTrack(width w: CGFloat, frac: Double, dur: Int) -> some View {
        let filled: CGFloat = w * CGFloat(frac)
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.3)).frame(height: 3)
            Capsule().fill(Color.white).frame(width: max(0, filled), height: 3)
            Circle().fill(Color.white).frame(width: 12, height: 12).offset(x: filled - 6)
        }
        .frame(height: 24)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let f: Double = Double(v.location.x / w)
                    dragFrac = min(max(f, 0), 1)
                }
                .onEnded { v in
                    let f: Double = min(max(Double(v.location.x / w), 0), 1)
                    dragFrac = nil
                    let ms: Int = Int(f * Double(dur))
                    Task { await engine.seek(ms) }
                }
        )
    }

    // MARK: shuffle, previous, the big round play/pause, next, repeat
    private var controls: some View {
        let repeatOn = engine.now.repeatMode != "off"
        return HStack(spacing: 0) {
            modeButton("ai_shuffle", on: engine.now.shuffle) { Task { await engine.toggleShuffle() } }
                .frame(maxWidth: .infinity)
            transport("ai_prev") { Task { await engine.previous() } }
                .frame(maxWidth: .infinity)
            playButton(size: 60, icon: 22)
                .frame(maxWidth: .infinity)
            transport("ai_next") { Task { await engine.next() } }
                .frame(maxWidth: .infinity)
            modeButton(engine.now.repeatMode == "track" ? "ai_repeat1" : "ai_repeat", on: repeatOn) { Task { await engine.cycleRepeat() } }
                .frame(maxWidth: .infinity)
        }
    }

    private func playButton(size: CGFloat, icon: CGFloat) -> some View {
        Button {
            Haptics.firm()
            Task { await engine.togglePlay() }
        } label: {
            ZStack {
                Circle().fill(Color.white)
                Icon.img(engine.now.isPlaying ? "ai_pause" : "ai_play").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: icon, height: icon)
                    .foregroundStyle(Color.black)
                    .offset(x: engine.now.isPlaying ? 0 : 2)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
    }

    private func modeButton(_ icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            ZStack {
                Icon.img(icon).renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(on ? NowPlayingView.green : Color.white.opacity(0.85))
                Circle().fill(on ? NowPlayingView.green : Color.clear).frame(width: 4, height: 4).offset(y: 19)
            }
            .frame(width: 52, height: 52)
        }
    }

    private func transport(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Icon.img(icon).renderingMode(.template).resizable().scaledToFit()
                .foregroundStyle(Color.white)
                .frame(width: 24, height: 24)
                .frame(minWidth: 46, minHeight: 46)
        }
        .buttonStyle(PressableStyle(scale: 0.85))
        .shadow(color: Color.black.opacity(0.4), radius: 6)
    }

    // which device is playing (tap to change), and share
    private var deviceRow: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                showDevices = true
            } label: {
                HStack(spacing: 10) {
                    Icon.img("ai_speaker").renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 17, height: 17)
                        .foregroundStyle(NowPlayingView.green)
                    Text(engine.now.deviceName.isEmpty ? "This device" : engine.now.deviceName)
                        .font(.system(size: 13))
                        .foregroundStyle(NowPlayingView.green)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            if let u = item?.shareURL {
                ShareLink(item: u) {
                    Icon.img("ai_share").renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Color.white)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.14), in: Circle())
                }
            }
        }
        .opacity(engine.connected ? 1 : 0)
    }

    // MARK: the frosted album-art background
    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.12, green: 0.12, blue: 0.18), Color.black], startPoint: .top, endPoint: .bottom)
            if let img = shown {
                Color.clear
                    .overlay {
                        Image(uiImage: img).resizable().scaledToFill()
                            .scaleEffect(1.3)
                            .blur(radius: 55)
                    }
                    .clipped()
                    .id(shownKey)
                    .transition(.opacity)
                Color.black.opacity(0.35)
            }
            // darkens the top and bottom so the text and buttons stay readable
            LinearGradient(colors: [Color.black.opacity(0.3), .clear, .clear, Color.black.opacity(0.6)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    // MARK: lyrics card (a short preview that follows the song; tap it to open it full screen)
    private var lyricsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Lyrics").font(.system(size: 16, weight: .bold))
                Spacer()
                if let u = item?.shareURL {
                    ShareLink(item: u) {
                        Icon.img("ai_share").renderingMode(.template).resizable().scaledToFit()
                            .frame(width: 15, height: 15)
                            .frame(width: 30, height: 30)
                            .background(Color.black.opacity(0.22), in: Circle())
                    }
                }
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Color.black.opacity(0.22), in: Circle())
            }
            .padding(.top, 16)
            LyricsScroller(lyrics: lyrics, size: 22, spacing: 14, tappable: false, anchor: .top, bottomPad: 100)
                .frame(height: 190)
                .allowsHitTesting(false)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.72), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(accent))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture { withAnimation(springy) { showFullLyrics = true } }
        .padding(.horizontal, 12)
    }

    private func fullLyrics(top: CGFloat, bottom: CGFloat) -> some View {
        ZStack {
            accent
            VStack(spacing: 0) {
                panelHeader(top: top) { withAnimation(springy) { showFullLyrics = false } }
                LyricsScroller(lyrics: lyrics, size: 29, spacing: 22, tappable: true, anchor: UnitPoint(x: 0.5, y: 0.3), bottomPad: 260)
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                panelFooter(bottom: bottom)
            }
            .foregroundStyle(Color.white)
        }
    }

    // MARK: Playing Next (with where Cara will talk)
    private var queueCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Playing Next").font(.system(size: 16, weight: .bold))
                    if !engine.contextName.isEmpty {
                        Text("From " + engine.contextName)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Color.black.opacity(0.22), in: Circle())
            }
            .padding(.bottom, 4)
            if engine.upNext.isEmpty {
                Text("Nothing's lined up. Spotify carries on from " + (engine.contextName.isEmpty ? "your music." : engine.contextName + "."))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.6))
                if engine.breakSlot != nil { CaraMarker() }
            }
            ForEach(Array(engine.upNext.prefix(5).enumerated()), id: \.offset) { i, t in
                if engine.breakSlot == i { CaraMarker() }
                QueueRow(track: t, onAddToPlaylist: { router.addToPlaylist = $0 }) {
                    Task { await engine.skip(to: i) }
                }
            }
        }
        .foregroundStyle(Color.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture { withAnimation(springy) { showFullQueue = true } }
        .padding(.horizontal, 12)
    }

    private func fullQueue(top: CGFloat, bottom: CGFloat) -> some View {
        ZStack {
            accent
            VStack(spacing: 0) {
                panelHeader(top: top) { withAnimation(springy) { showFullQueue = false } }
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Playing Next").font(.system(size: 22, weight: .bold))
                                if !engine.contextName.isEmpty {
                                    Text("From " + engine.contextName)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.white.opacity(0.65))
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            queueToggle("ai_shuffle", on: engine.now.shuffle) { Task { await engine.toggleShuffle() } }
                            queueToggle(engine.now.repeatMode == "track" ? "ai_repeat1" : "ai_repeat", on: engine.now.repeatMode != "off") {
                                Task { await engine.cycleRepeat() }
                            }
                        }
                        .padding(.vertical, 10)
                        if engine.upNext.isEmpty {
                            Text("Nothing's lined up next.")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.white.opacity(0.65))
                                .padding(.vertical, 12)
                            if engine.breakSlot != nil { CaraMarker() }
                        }
                        ForEach(Array(engine.upNext.enumerated()), id: \.offset) { i, t in
                            if engine.breakSlot == i { CaraMarker() }
                            QueueRow(track: t, onAddToPlaylist: { router.addToPlaylist = $0 }) {
                                Task { await engine.skip(to: i) }
                            }
                        }
                        Text("Spotify doesn't let apps reorder or remove songs in the queue. Press and hold a song for more.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .padding(.top, 16)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 20)
                }
                .refreshable { await engine.refreshQueue() }
                panelFooter(bottom: bottom)
            }
            .foregroundStyle(Color.white)
        }
        .task { await engine.refreshQueue() }
    }

    private func queueToggle(_ icon: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Icon.img(icon).renderingMode(.template).resizable().scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(on ? Color.black : Color.white)
                .frame(width: 44, height: 32)
                .background(on ? Color.white : Color.white.opacity(0.16), in: Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
    }

    // the chevron + song name at the top of the full-screen lyrics / queue
    private func panelHeader(top: CGFloat, close: @escaping () -> Void) -> some View {
        HStack {
            Button(action: close) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 40, height: 40)
            }
            Spacer()
            VStack(spacing: 1) {
                Text(item?.title ?? "").font(.system(size: 15, weight: .bold)).lineLimit(1)
                Text(item?.artistLine ?? "").font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.75)).lineLimit(1)
            }
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 18)
        .padding(.top, top + 14)
        .padding(.bottom, 10)
    }

    // share + "..." + progress + the big play button at the bottom of the full-screen panels
    private func panelFooter(bottom: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack {
                if let u = item?.shareURL {
                    ShareLink(item: u) {
                        Icon.img("ai_share").renderingMode(.template).resizable().scaledToFit()
                            .frame(width: 24, height: 24)
                            .frame(width: 44, height: 44)
                    }
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
                Spacer()
                moreButton
            }
            .padding(.horizontal, 26)
            .padding(.top, 6)
            progress
                .padding(.horizontal, 24)
                .padding(.top, 6)
            playButton(size: 72, icon: 26)
                .padding(.top, 14)
                .padding(.bottom, bottom + 22)
        }
    }

    // MARK: the cards under Playing Next
    private var infoCards: some View {
        VStack(spacing: 14) {
            if !about.song.isEmpty {
                InfoCard(title: "About the song") {
                    Text(about.song).font(.system(size: 15)).foregroundStyle(Color.white.opacity(0.8)).lineSpacing(3)
                    Text("Wikipedia")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                }
                .padding(.horizontal, 12)
            }
            if !about.artistImage.isEmpty || !about.bio.isEmpty {
                artistCard
            }
            if !popular.isEmpty {
                InfoCard(title: "Popular tracks") {
                    ForEach(Array(popular.prefix(5).enumerated()), id: \.offset) { i, t in
                        Button {
                            Haptics.tap()
                            Task { await engine.playTracks(popular, startAt: i) }
                        } label: {
                            HStack(spacing: 12) {
                                Artwork(t.artMid, px: 150, corner: 6)
                                    .frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                                    Text(t.artistLine).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.6)).lineLimit(1)
                                }
                                Spacer()
                                Text("\(i + 1)").font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.5))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { TrackMenuItems(track: t) }
                    }
                }
                .padding(.horizontal, 12)
            }
            if let t = engine.now.item {
                InfoCard(title: "Credits") {
                    ForEach(Array(t.artists.enumerated()), id: \.offset) { i, n in
                        creditRow(n, i == 0 ? "Main Artist" : "Featured Artist")
                    }
                    if !t.album.isEmpty { creditRow(t.album, "Album" + (t.year.isEmpty ? "" : " \u{00B7} " + t.year)) }
                    if t.release.count > 4 { creditRow(prettyDate(t.release), "Released") }
                    if !about.copyright.isEmpty { creditRow(about.copyright, "Copyright") }
                }
                .padding(.horizontal, 12)
                InfoCard(title: "Explore") {
                    HStack(spacing: 10) {
                        if !t.artistID.isEmpty {
                            tile("Songs by " + t.artist) {
                                Task { await engine.playContext("spotify:artist:" + t.artistID) }
                            }
                        }
                        if !t.albumID.isEmpty {
                            tile("Play " + (t.album.isEmpty ? "album" : t.album)) {
                                Task { await engine.playContext("spotify:album:" + t.albumID) }
                            }
                        }
                        tile("Watch on YouTube") {
                            let q = (t.title + " " + t.artist).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let u = URL(string: "https://www.youtube.com/results?search_query=" + q) { UIApplication.shared.open(u) }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .foregroundStyle(Color.white)
        .padding(.top, 14)
    }

    private var artistCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if !about.artistImage.isEmpty {
                    Artwork(about.artistImage, px: 900, corner: 0)
                        .frame(height: 260)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    LinearGradient(colors: [Color.black.opacity(0.45), .clear], startPoint: .top, endPoint: .center)
                } else {
                    Color.white.opacity(0.06).frame(height: 70)
                }
                Text("About the artist").font(.system(size: 18, weight: .bold)).padding(18)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(engine.now.item?.artist ?? "").font(.system(size: 26, weight: .heavy))
                if !about.genres.isEmpty {
                    HStack {
                        ForEach(about.genres, id: \.self) { g in
                            Text(g.capitalized)
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.12), in: Capsule())
                        }
                    }
                }
                if !about.bio.isEmpty {
                    Text(about.bio)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .lineSpacing(3)
                        .lineLimit(bioOpen ? nil : 4)
                    if about.bio.count > 220 {
                        Button(bioOpen ? "show less" : "see more") {
                            withAnimation(.easeInOut(duration: 0.25)) { bioOpen.toggle() }
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white)
                    }
                }
                if let t = engine.now.item, !t.artistID.isEmpty {
                    Button {
                        router.open(.artist(t.artistRef))
                    } label: {
                        Text("See artist page")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
    }

    private func creditRow(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.system(size: 16)).lineLimit(2)
            Text(sub).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tile(_ label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .bottomLeading)
                .padding(10)
                .background(LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.16)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: small player that slides in once you scroll past the player page
    private func miniBar(top: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    (Text(item?.title ?? "").font(.system(size: 14, weight: .bold))
                     + Text("  \u{00B7} " + (item?.artist ?? "")).font(.system(size: 14)).foregroundColor(Color.white.opacity(0.65)))
                        .lineLimit(1)
                    Text(engine.now.deviceName)
                        .font(.system(size: 11))
                        .foregroundStyle(NowPlayingView.green)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    Haptics.tap()
                    Task { await engine.togglePlay() }
                } label: {
                    Icon.img(engine.now.isPlaying ? "ai_pause" : "ai_play").renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(Color.white)
                        .frame(width: 40, height: 40)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, top + 10)
            .padding(.bottom, 12)
            GeometryReader { g in
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: g.size.width * CGFloat(liveFraction()), height: 2)
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 18)
        }
        .foregroundStyle(Color.white)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.35))
        .offset(y: inLyr ? 0 : -200)
        .opacity(inLyr ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: inLyr)
    }

    // MARK: loading
    private func loadCover() async {
        guard let it = item, !it.art.isEmpty else { return }
        let key = it.art
        if key == shownKey { return }
        guard let img = await ImageCache.shared.load(key, px: 900) else { return }
        if Task.isCancelled { return }
        let avg = ArtColors.average(img)
        withAnimation(.easeInOut(duration: 0.9)) {
            shown = img
            shownKey = key
            accent = avg
        }
    }

    private func loadAbout() async {
        guard let t = engine.now.item else { return }
        await about.load(t)
        if t.isMusic && !t.artistID.isEmpty && popularFor != t.artistID {
            let found = await Spotify.shared.artistTopTracks(t.artistRef)
            if Task.isCancelled { return }
            popular = found
            popularFor = t.artistID
        }
    }
}

// MARK: - Lyrics that follow the song
struct LyricsScroller: View {
    let lyrics: LyricsStore
    var size: CGFloat
    var spacing: CGFloat
    var tappable: Bool
    var anchor: UnitPoint
    var bottomPad: CGFloat
    @Environment(Engine.self) private var engine

    var body: some View {
        if lyrics.hasSynced {
            ScrollViewReader { proxy in
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    lines(cur: lyrics.index(at: engine.now.currentProgressMs), proxy: proxy)
                }
            }
        } else if !lyrics.plain.isEmpty {
            ScrollView(showsIndicators: false) {
                Text(lyrics.plain)
                    .font(.system(size: tappable ? 22 : 18, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            .scrollDisabled(!tappable)
        } else {
            Text(lyrics.status.isEmpty ? "No lyrics for this one." : lyrics.status)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        }
    }

    private func lines(cur: Int, proxy: ScrollViewProxy) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(lyrics.lines) { line in
                    lineView(line, isNow: line.id == cur)
                }
                Color.clear.frame(height: bottomPad)
            }
            .padding(.top, 4)
        }
        .scrollDisabled(!tappable)
        .onChange(of: cur) { _, c in
            if c >= 0 {
                withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo(c, anchor: anchor) }
            }
        }
        .onAppear {
            if cur >= 0 { proxy.scrollTo(cur, anchor: anchor) }
        }
    }

    private func lineView(_ line: LyricLine, isNow: Bool) -> some View {
        Text(line.text.isEmpty ? "\u{266A}" : line.text)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(isNow ? Color.white : Color.white.opacity(0.38))
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(line.id)
            .contentShape(Rectangle())
            .onTapGesture {
                if tappable {
                    Haptics.tap()
                    Task { await engine.seek(line.timeMs) }
                }
            }
    }
}

// MARK: - Everything Cara can do (the "Cara Options…" sheet)
struct CaraOptionsSheet: View {
    @Environment(Engine.self) private var engine
    @EnvironmentObject private var cfg: Config
    var onSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("DJ OPTIONS").font(.system(size: 13, weight: .heavy)).tracking(2).foregroundStyle(Color.white)
                    Spacer()
                    Button("SETTINGS", action: onSettings)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white)
                }

                Button {
                    Haptics.firm()
                    if engine.running { engine.stop() } else { engine.start() }
                } label: {
                    Text(engine.running ? "STOP DJ" : "START DJ")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(engine.running ? Color.white : Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(engine.running ? Color.red : Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                label(statusText)
                if !engine.line.isEmpty {
                    Text("\u{201C}" + engine.line.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression) + "\u{201D}")
                        .font(.system(size: 13))
                        .italic()
                        .foregroundStyle(Color.white)
                }

                Stepper("DJ talks at least every \(cfg.breakMin) song\(cfg.breakMin == 1 ? "" : "s")", value: $cfg.breakMin, in: 1...10)
                    .onChange(of: cfg.breakMin) { _, v in if v > cfg.breakMax { cfg.breakMax = v } }
                Stepper("...and at most every \(cfg.breakMax) (random in between)", value: $cfg.breakMax, in: 1...10)
                    .onChange(of: cfg.breakMax) { _, v in if v < cfg.breakMin { cfg.breakMin = v } }
                Stepper("Stinger chance: \(cfg.stingerChance)% of silent breaks", value: $cfg.stingerChance, in: 0...100, step: 5)

                Toggle("Cara pops back in a few seconds into the song", isOn: $cfg.popinEnabled)
                Stepper("Pop-in chance: \(cfg.popinChance)% of talk-over / intro breaks", value: $cfg.popinChance, in: 0...100, step: 5)
                Stepper("Pop-in about \(cfg.popinSeconds) seconds into the song", value: $cfg.popinSeconds, in: 5...120, step: 5)
                Toggle("Pop-in test mode (after every non-silent break)", isOn: $cfg.popinTest)

                sliderRow("DJ VOLUME", value: $cfg.djVolume)
                sliderRow("STINGER VOLUME", value: $cfg.stingerVolume)

                VStack(alignment: .leading, spacing: 6) {
                    label("DJ MOOD")
                    Picker("Mood", selection: $cfg.mood) {
                        Text("Chill").tag("chill")
                        Text("Normal").tag("normal")
                        Text("Unhinged").tag("unhinged")
                        Text("Mixed").tag("mixed")
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    label("QUEUE NEXT (AT THE END OF THIS SONG)")
                    HStack(spacing: 10) {
                        queueButton("TALK OVER", "talkover")
                        queueButton("OVER INTRO", "intro")
                        queueButton("SILENT", "silent")
                    }
                }

                HStack(spacing: 10) {
                    pill("TEST DJ NOW") { engine.testBreak() }
                    pill("TEST STINGER") { Task { await engine.testStinger() } }
                    pill("TEST POP-IN") { engine.testPopin() }
                }

                VStack(alignment: .leading, spacing: 6) {
                    label("ACTIVITY")
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(engine.log.reversed().enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color(red: 0.6, green: 0.82, blue: 0.66))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: 180)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Color.white)
            .padding(20)
        }
        .tint(Theme.accent)
        .environment(\.colorScheme, .dark)
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }

    private var statusText: String {
        if engine.speaking { return "DJ IS TALKING..." }
        if engine.running { return "DJ IS LIVE · " + engine.statusLine.uppercased() }
        return "DJ IS OFF"
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(Color.white.opacity(0.6))
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func queueButton(_ title: String, _ style: String) -> some View {
        Button {
            Haptics.tap()
            engine.queue(style)
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(engine.queued == style ? Color.white : Color.clear, lineWidth: 2))
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label(title)
            Slider(value: value, in: 0...100).tint(Color.white)
        }
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

// MARK: - A song in "Playing Next"
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

/// Where Cara will come in, shown between the songs in "Playing Next".
struct CaraMarker: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        HStack(spacing: 12) {
            Icon.img("ai_dj").renderingMode(.template).resizable().scaledToFit()
                .frame(width: 15, height: 15)
                .foregroundStyle(Color.black)
                .frame(width: 44, height: 30)
                .background(Color.white, in: Capsule())
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
                                    .foregroundStyle(d.isActive ? NowPlayingView.green : Color.primary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.name).foregroundStyle(Color.primary)
                                    if d.isActive {
                                        Text("Playing now").font(.caption).foregroundStyle(NowPlayingView.green)
                                    }
                                }
                                Spacer()
                                if d.isActive {
                                    Image(systemName: "checkmark").foregroundStyle(NowPlayingView.green)
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

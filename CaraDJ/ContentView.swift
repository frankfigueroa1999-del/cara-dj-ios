import SwiftUI
import UIKit

/// Icons live as plain PNG files next to the Swift files (ai_*.png), so they can be uploaded in one go.
enum Icon { static func img(_ n: String) -> Image { Image(uiImage: UIImage(named: n) ?? UIImage()) } }

struct ContentView: View {
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var cfg: Config
    @State private var showSettings = false
    @State private var showOptions = false
    @StateObject private var lyrics = LyricsStore()
    @StateObject private var about = AboutStore()
    @State private var bioOpen = false
    @State private var showFull = false
    // the cover that is currently on screen; it only changes once the next one has fully loaded, then cross-fades
    @State private var shown: UIImage? = nil
    @State private var shownKey = ""
    @State private var accent = Color(red: 0.25, green: 0.2, blue: 0.2)
    @State private var dragFrac: Double? = nil

    private var artURL: URL? {
        if let s = engine.now.track?.art, !s.isEmpty { return URL(string: s) }
        return nil
    }

    @State private var inLyr = false
    @State private var scrollY: CGFloat = 0
    @State private var pageHeightHint: CGFloat = 600
    private struct OffsetKey: PreferenceKey { static var defaultValue: CGFloat = 0; static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() } }

    var body: some View {
        ZStack {
            background
            GeometryReader { g in
                let top = g.safeAreaInsets.top
                let bottom = g.safeAreaInsets.bottom
                let H = g.size.height + top + bottom
                let peek: CGFloat = 84 + bottom
                let pageH = H - peek
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            // the player page
                            VStack(spacing: 0) {
                                topBar
                                Spacer(minLength: 8)
                                cover
                                Spacer(minLength: 8).frame(maxHeight: 28)
                                bottomPanel
                                Spacer(minLength: 4).frame(maxHeight: 12)
                            }
                            .padding(.horizontal, 22)
                            .padding(.top, top)
                            .frame(height: pageH)
                            .id("player")
                            .background(GeometryReader { p in
                                Color.clear.preference(key: OffsetKey.self, value: p.frame(in: .named("sc")).minY)
                            })
                            lyricsCard
                            infoCards
                            Color.clear.frame(height: 40 + bottom)
                        }
                    }
                    .coordinateSpace(name: "sc")
                    .onPreferenceChange(OffsetKey.self) { y in
                        scrollY = -y; pageHeightHint = pageH
                        let now = -y > pageH * 0.8
                        if now != inLyr { inLyr = now }
                    }
                }
                .ignoresSafeArea()
                .overlay(alignment: .top) { miniBar(top: top).allowsHitTesting(inLyr) }
            }
        }
        .preferredColorScheme(.dark)
        .overlay {
            GeometryReader { g in
                if showFull {
                    fullLyrics(top: g.safeAreaInsets.top, bottom: g.safeAreaInsets.bottom)
                        .ignoresSafeArea()
                        .transition(.scale(scale: 0.88, anchor: .center).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showOptions) {
            OptionsView(onSettings: {
                showOptions = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showSettings = true }
            })
            .environmentObject(engine).environmentObject(cfg)
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(engine).environmentObject(cfg) }
        .task(id: artURL) {
            guard let u = artURL,
                  let (data, _) = try? await URLSession.shared.data(from: u),
                  let img = UIImage(data: data) else { return }
            withAnimation(.easeInOut(duration: 0.9)) { shown = img; shownKey = u.absoluteString; accent = ContentView.average(img) }
        }
        .task(id: engine.now.track?.uri ?? "") { await about.load(engine.now.track) }
        .task(id: lyricsKey) { await lyrics.load(engine.now.track, durationMs: engine.now.durationMs) }
        .task {
            engine.startBackgroundPolling()
            if Spotify.shared.isLoggedIn { await engine.connect() }
            else if cfg.clientID.isEmpty { showSettings = true }
        }
    }

    // MARK: the album cover fills the whole screen
    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.12, green: 0.12, blue: 0.18), Color.black], startPoint: .top, endPoint: .bottom)
            if let img = shown {
                Color.clear.overlay(
                    Image(uiImage: img).resizable().scaledToFill()
                        .scaleEffect(1.3)
                        .blur(radius: 55)
                ).clipped()
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

    /// The real album cover, sharp, in the middle of the frosted background.
    private var cover: some View {
        ZStack {
            Color.white.opacity(0.08)
            if let img = shown {
                Image(uiImage: img).resizable().scaledToFill()
                    .id(shownKey)
                    .transition(.opacity)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: min(UIScreen.main.bounds.width * 0.84, UIScreen.main.bounds.height * 0.46, 420))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 22, y: 10)
    }

    // MARK: lyrics
    private var lyricsKey: String { (engine.now.track?.title ?? "") + "|" + (engine.now.track?.artist ?? "") }

    private var curLine: Int {
        let pos = engine.now.currentProgressMs + 250
        return lyrics.lines.lastIndex(where: { $0.timeMs <= pos }) ?? -1
    }

    private var shareURL: URL? {
        let p = engine.now.uri.split(separator: ":")
        if p.count == 3 { return URL(string: "https://open.spotify.com/\(p[1])/\(p[2])") }
        return nil
    }

    // the compact lyrics card: a short preview that follows the song; tap it to open it full screen
    private var lyricsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Lyrics").font(.system(size: 16, weight: .bold))
                Spacer()
                if let u = shareURL {
                    ShareLink(item: u) {
                        Icon.img("ai_share").renderingMode(.template).resizable().scaledToFit().frame(width: 15, height: 15)
                            .frame(width: 30, height: 30).background(Color.black.opacity(0.22), in: Circle())
                    }
                }
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30).background(Color.black.opacity(0.22), in: Circle())
            }
            .padding(.top, 16)
            ScrollViewReader { p in
                ScrollView(showsIndicators: false) {
                    lyricsList(prefix: "pv", size: 22, spacing: 14, tappable: false)
                        .padding(.top, 4)
                }
                .scrollDisabled(true)
                .allowsHitTesting(false)
                .frame(height: 190)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.72), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                .onChange(of: curLine) { c in
                    if c >= 0 { withAnimation(.easeInOut(duration: 0.5)) { p.scrollTo("pv\(c)", anchor: .top) } }
                }
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(accent))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture { withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { showFull = true } }
        .padding(.horizontal, 12)
    }

    // full-screen lyrics: the card grown into a page of its own
    private func fullLyrics(top: CGFloat, bottom: CGFloat) -> some View {
        ZStack {
            accent
            VStack(spacing: 0) {
                HStack {
                    Button { withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { showFull = false } } label: {
                        Image(systemName: "chevron.down").font(.system(size: 18, weight: .bold)).frame(width: 40, height: 40)
                    }
                    Spacer()
                    VStack(spacing: 1) {
                        Text(engine.now.track?.title ?? "").font(.system(size: 15, weight: .bold)).lineLimit(1)
                        Text(engine.now.track?.artist ?? "").font(.system(size: 14)).foregroundColor(Color.white.opacity(0.75)).lineLimit(1)
                    }
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 18).padding(.top, top + 14).padding(.bottom, 10)
                ScrollViewReader { p in
                    ScrollView(showsIndicators: false) {
                        lyricsList(prefix: "fl", size: 29, spacing: 22, tappable: true)
                            .padding(.horizontal, 22).padding(.top, 18)
                    }
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                    .onChange(of: curLine) { c in
                        if c >= 0 { withAnimation(.easeInOut(duration: 0.5)) { p.scrollTo("fl\(c)", anchor: UnitPoint(x: 0.5, y: 0.3)) } }
                    }
                    .onAppear { if curLine >= 0 { p.scrollTo("fl\(curLine)", anchor: UnitPoint(x: 0.5, y: 0.3)) } }
                }
                HStack {
                    if let u = shareURL {
                        ShareLink(item: u) {
                            Icon.img("ai_share").renderingMode(.template).resizable().scaledToFit().frame(width: 24, height: 24).frame(width: 44, height: 44)
                        }
                    } else { Color.clear.frame(width: 44, height: 44) }
                    Spacer()
                    Button { showFull = false; showOptions = true } label: {
                        Icon.img("ai_more").renderingMode(.template).resizable().scaledToFit().frame(width: 22, height: 8).frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 26).padding(.top, 6)
                progress.padding(.horizontal, 24).padding(.top, 6)
                Button { Task { await engine.togglePlay() } } label: {
                    ZStack {
                        Circle().fill(Color.white)
                        Icon.img(engine.now.isPlaying ? "ai_pause" : "ai_play").renderingMode(.template).resizable().scaledToFit()
                            .frame(width: 26, height: 26).foregroundColor(.black).offset(x: engine.now.isPlaying ? 0 : 2)
                    }
                    .frame(width: 72, height: 72)
                }
                .padding(.top, 14).padding(.bottom, bottom + 22)
            }
            .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private func lyricsList(prefix: String, size: CGFloat, spacing: CGFloat, tappable: Bool) -> some View {
        if !lyrics.lines.isEmpty {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let cur = curLine
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(lyrics.lines) { line in
                        Text(line.text.isEmpty ? "\u{266A}" : line.text)
                            .font(.system(size: size, weight: .bold))
                            .foregroundColor(line.id == cur ? .white : Color.white.opacity(0.38))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(prefix + "\(line.id)")
                            .contentShape(Rectangle())
                            .onTapGesture { if tappable { Task { await engine.seek(line.timeMs) } } }
                    }
                    Spacer().frame(height: tappable ? 260 : 100)
                }
            }
        } else if !lyrics.plain.isEmpty {
            Text(lyrics.plain).font(.system(size: tappable ? 22 : 18, weight: .semibold)).foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
        } else {
            Text(lyrics.status).font(.system(size: 14)).foregroundColor(Color.white.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
        }
    }

    // MARK: info cards under the lyrics
    @ViewBuilder
    private var infoCards: some View {
        VStack(spacing: 14) {
            if !about.song.isEmpty {
                InfoCard(title: "About the song") {
                    Text(about.song).font(.system(size: 15)).foregroundColor(Color.white.opacity(0.8)).lineSpacing(3)
                    Text("Wikipedia").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                }
            }
            if about.artistImage != "" || !about.bio.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        if let u = URL(string: about.artistImage), about.artistImage != "" {
                            AsyncImage(url: u) { ph in
                                if let i = ph.image { i.resizable().scaledToFill() } else { Color.white.opacity(0.06) }
                            }
                            .frame(height: 260).clipped()
                            LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .center)
                        } else { Color.white.opacity(0.06).frame(height: 70) }
                        Text("About the artist").font(.system(size: 18, weight: .bold)).padding(18)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(engine.now.track?.artist ?? "").font(.system(size: 26, weight: .heavy))
                        if about.followers > 0 {
                            Text(ContentView.compact(about.followers) + " followers").font(.system(size: 14)).foregroundColor(Color.white.opacity(0.65))
                        }
                        if !about.genres.isEmpty {
                            HStack { ForEach(about.genres, id: \.self) { g in
                                Text(g.capitalized).font(.system(size: 12, weight: .bold)).padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color.white.opacity(0.12), in: Capsule()) } }
                        }
                        if !about.bio.isEmpty {
                            Text(about.bio).font(.system(size: 15)).foregroundColor(Color.white.opacity(0.8)).lineSpacing(3)
                                .lineLimit(bioOpen ? nil : 4)
                            if about.bio.count > 220 {
                                Button(bioOpen ? "show less" : "see more") { withAnimation(.easeInOut(duration: 0.25)) { bioOpen.toggle() } }
                                    .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                            }
                        }
                        if let u = URL(string: about.artistURL), about.artistURL != "" {
                            Link("Open in Spotify", destination: u).font(.system(size: 14, weight: .bold))
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1)).foregroundColor(.white).padding(.top, 4)
                        }
                    }.padding(18)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 12)
            }
            if !about.pop.isEmpty {
                InfoCard(title: "Popular tracks") {
                    ForEach(Array(about.pop.enumerated()), id: \.element.id) { i, t in
                        Button { Task { await Spotify.shared.playContext(contextURI: nil, trackURI: t.uri, device: engine.now.deviceID); engine.lastPollReset() } } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: URL(string: t.art)) { ph in if let im = ph.image { im.resizable().scaledToFill() } else { Color.white.opacity(0.1) } }
                                    .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                                    Text(t.artists).font(.system(size: 13)).foregroundColor(Color.white.opacity(0.6)).lineLimit(1)
                                }
                                Spacer()
                                Text("\(i + 1)").font(.system(size: 13)).foregroundColor(Color.white.opacity(0.5))
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
            if let t = engine.now.track {
                InfoCard(title: "Credits") {
                    ForEach(Array(t.artists.enumerated()), id: \.offset) { i, n in creditRow(n, i == 0 ? "Main Artist" : "Featured Artist") }
                    if !t.album.isEmpty { creditRow(t.album, "Album" + (t.year.isEmpty ? "" : " \u{00B7} " + t.year)) }
                    if !about.label.isEmpty { creditRow(about.label, "Label") }
                    if t.release.count > 4 { creditRow(ContentView.prettyDate(t.release), "Released") }
                    if !about.copyright.isEmpty { creditRow(about.copyright, "Copyright") }
                }
                InfoCard(title: "Explore") {
                    HStack(spacing: 10) {
                        if !t.artistID.isEmpty { tile("Songs by " + t.artist) { await Spotify.shared.playContext(contextURI: "spotify:artist:" + t.artistID, trackURI: nil, device: engine.now.deviceID) } }
                        if !t.albumID.isEmpty { tile("Play " + (t.album.isEmpty ? "album" : t.album)) { await Spotify.shared.playContext(contextURI: "spotify:album:" + t.albumID, trackURI: nil, device: engine.now.deviceID) } }
                        tile("Watch on YouTube") {
                            let q = (t.title + " " + t.artist).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let u = URL(string: "https://www.youtube.com/results?search_query=" + q) { await MainActor.run { UIApplication.shared.open(u) } }
                        }
                    }
                }
            }
        }
        .padding(.top, 14)
    }

    private func creditRow(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.system(size: 16)).lineLimit(2)
            Text(sub).font(.system(size: 13)).foregroundColor(Color.white.opacity(0.6))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tile(_ label: String, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Text(label).font(.system(size: 13, weight: .bold)).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .bottomLeading).padding(10)
                .background(LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.16)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }

    // small player that slides in once you scroll past the player page
    private func miniBar(top: CGFloat) -> some View {
        let dur = Double(max(engine.now.durationMs, 1))
        return ZStack(alignment: .bottom) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    (Text(engine.now.track?.title ?? "").font(.system(size: 14, weight: .bold)) + Text("  \u{00B7} " + (engine.now.track?.artist ?? "")).font(.system(size: 14)).foregroundColor(Color.white.opacity(0.65))).lineLimit(1)
                    Text(engine.now.deviceName).font(.system(size: 11)).foregroundColor(green).lineLimit(1)
                }
                Spacer()
                Button { Task { await engine.togglePlay() } } label: {
                    Icon.img(engine.now.isPlaying ? "ai_pause" : "ai_play").renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 20, height: 20).foregroundColor(.white).frame(width: 40, height: 40)
                }
            }
            .padding(.horizontal, 18).padding(.top, top + 10).padding(.bottom, 12)
            GeometryReader { g in
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    Rectangle().fill(Color.white).frame(width: g.size.width * CGFloat(min(Double(engine.now.currentProgressMs) / dur, 1)), height: 2)
                }
            }.frame(height: 2).padding(.horizontal, 18)
        }
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.35))
        .offset(y: inLyr ? 0 : -200)
        .opacity(inLyr ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: inLyr)
    }

    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
    static func prettyDate(_ s: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: s) else { return s }
        let o = DateFormatter(); o.dateStyle = .long; return o.string(from: d)
    }

    // MARK: pieces
    private var topBar: some View {
        VStack(spacing: 12) {
            if !engine.connected {
                Button { Task { await engine.connect() } } label: {
                    Text("CONNECT SPOTIFY").font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous)).foregroundColor(.black)
                }
            }
        }
        .padding(.top, 8)
        .shadow(color: .black.opacity(0.5), radius: 6)
    }

    private let green = Color(red: 0.37, green: 0.82, blue: 0.43)

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            // song name and artist, with the DJ on/off button and the "..." button that opens every DJ option
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.now.track?.title ?? (engine.connected ? "Nothing playing" : "Not connected"))
                        .font(.system(size: 18, weight: .bold)).foregroundColor(.white).lineLimit(2)
                    Text(engine.now.track?.artist ?? "Start a playlist in the Spotify app.")
                        .font(.system(size: 14)).foregroundColor(Color.white.opacity(0.7)).lineLimit(1)
                }
                .shadow(color: .black.opacity(0.5), radius: 6)
                Spacer(minLength: 8)
                // DJ on / off: white and filled while she is live
                Button {
                    if engine.running { engine.stop() } else { engine.start() }
                } label: {
                    Icon.img("ai_dj").renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 15, height: 15)
                        .foregroundColor(engine.running ? .black : .white)
                        .frame(width: 30, height: 30)
                        .background(engine.running ? AnyShapeStyle(Color.white) : AnyShapeStyle(Material.ultraThinMaterial), in: Circle())
                }
                Button { showOptions = true } label: {
                    Icon.img("ai_more").renderingMode(.template).resizable().scaledToFit().frame(width: 17, height: 6).foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }

            Spacer().frame(height: 26)
            progress
            Spacer().frame(height: 26)
            controls
            Spacer().frame(height: 22)
            deviceRow
        }
    }

    // shuffle, previous, the big round play/pause, next, repeat
    private var controls: some View {
        let repeatOn = engine.now.repeatMode != "off"
        return HStack(spacing: 0) {
            Group {
            modeButton("ai_shuffle", on: engine.now.shuffle) { Task { await engine.toggleShuffle() } }
            }.frame(maxWidth: .infinity)
            Group {
            transport("ai_prev", size: 24) { Task { await engine.previous() } }
            }.frame(maxWidth: .infinity)
            Group {
            Button { Task { await engine.togglePlay() } } label: {
                ZStack {
                    Circle().fill(Color.white)
                    Icon.img(engine.now.isPlaying ? "ai_pause" : "ai_play").renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 22, height: 22).foregroundColor(.black)
                        .offset(x: engine.now.isPlaying ? 0 : 2)
                }
                .frame(width: 60, height: 60)
            }
            }.frame(maxWidth: .infinity)
            Group {
            transport("ai_next", size: 24) { Task { await engine.next() } }
            }.frame(maxWidth: .infinity)
            Group {
            modeButton(engine.now.repeatMode == "track" ? "ai_repeat1" : "ai_repeat", on: repeatOn) { Task { await engine.cycleRepeat() } }
            }.frame(maxWidth: .infinity)
        }
    }

    private func modeButton(_ icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Icon.img(icon).renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundColor(on ? green : Color.white.opacity(0.85))
                Circle().fill(on ? green : Color.clear).frame(width: 4, height: 4).offset(y: 19)
            }
            .frame(width: 52, height: 52)
        }
    }

    // which device is playing
    private var deviceRow: some View {
        HStack(spacing: 10) {
            Icon.img("ai_speaker").renderingMode(.template).resizable().scaledToFit()
                .frame(width: 17, height: 17).foregroundColor(green)
            Text(engine.now.deviceName.isEmpty ? "This device" : engine.now.deviceName)
                .font(.system(size: 13)).foregroundColor(green).lineLimit(1)
            Spacer()
            if let u = shareURL {
                ShareLink(item: u) {
                    Icon.img("ai_share").renderingMode(.template).resizable().scaledToFit().frame(width: 16, height: 16)
                        .frame(width: 30, height: 30).background(Color.white.opacity(0.14), in: Circle()).foregroundColor(.white)
                }
            }
        }
        .opacity(engine.connected ? 1 : 0)
    }

    // progress bar with a round handle; drag it to seek
    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let dur = max(engine.now.durationMs, 1)
            let cur = min(engine.now.currentProgressMs, dur)
            let frac = dragFrac ?? (Double(cur) / Double(dur))
            let shownMs = dragFrac.map { Int($0 * Double(dur)) } ?? cur
            VStack(spacing: 2) {
                GeometryReader { g in
                    let w = max(g.size.width, 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.3)).frame(height: 3)
                        Capsule().fill(Color.white).frame(width: w * CGFloat(frac), height: 3)
                        Circle().fill(Color.white).frame(width: 12, height: 12)
                            .offset(x: w * CGFloat(frac) - 6)
                    }
                    .frame(height: 24)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in dragFrac = Double(min(max(v.location.x / w, 0), 1)) }
                            .onEnded { v in
                                let f = Double(min(max(v.location.x / w, 0), 1))
                                dragFrac = nil
                                Task { await engine.seek(Int(f * Double(dur))) }
                            }
                    )
                }
                .frame(height: 24)
                HStack {
                    Text(ContentView.clock(shownMs))
                    Spacer()
                    Text("-" + ContentView.clock(dur - shownMs))
                }
                .font(.system(size: 11, weight: .medium)).foregroundColor(Color.white.opacity(0.65))
            }
        }
    }

    static func clock(_ ms: Int) -> String {
        let s = max(0, ms / 1000)
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    private func transport(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon.img(symbol).renderingMode(.template).resizable().scaledToFit()
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .frame(minWidth: 46, minHeight: 46)
        }
        .shadow(color: .black.opacity(0.4), radius: 6)
    }

    @ViewBuilder
    private var lyricsPreview: some View {
        if !lyrics.lines.isEmpty {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let pos = engine.now.currentProgressMs + 250
                let cur = lyrics.lines.lastIndex(where: { $0.timeMs <= pos }) ?? -1
                let a = cur >= 0 ? lyrics.lines[cur].text : ""
                let nextIdx = cur + 1
                let b = nextIdx < lyrics.lines.count ? lyrics.lines[nextIdx].text : ""
                VStack(alignment: .leading, spacing: 4) {
                    Text(a.isEmpty ? "\u{266A}" : a).font(.system(size: 18, weight: .bold)).lineLimit(1)
                    Text(b).font(.system(size: 16, weight: .semibold)).foregroundColor(Color.white.opacity(0.55)).lineLimit(1)
                }
            }
        } else if !lyrics.plain.isEmpty {
            Text(lyrics.plain).font(.system(size: 16, weight: .semibold)).lineLimit(2)
        } else {
            Text(lyrics.status).font(.system(size: 15)).foregroundColor(Color.white.opacity(0.75))
        }
    }

    /// The cover's average colour, darkened, for the lyrics card.
    static func average(_ img: UIImage) -> Color {
        guard let cg = img.cgImage else { return Color(red: 0.25, green: 0.2, blue: 0.2) }
        var px = [UInt8](repeating: 0, count: 4)
        px.withUnsafeMutableBytes { raw in
            if let ctx = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.interpolationQuality = .medium
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
        }
        return Color(red: Double(px[0]) / 255 * 0.75, green: Double(px[1]) / 255 * 0.75, blue: Double(px[2]) / 255 * 0.75)
    }

}


/// Everything the DJ can do, tucked behind the "..." button.
struct OptionsView: View {
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var cfg: Config
    var onSettings: () -> Void

    var body: some View {
        ZStack {
            Color.clear.background(.ultraThinMaterial).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("DJ OPTIONS").font(.system(size: 13, weight: .heavy)).foregroundColor(.white).tracking(2)
                        Spacer()
                        Button("SETTINGS", action: onSettings).font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                    }

                    // start / stop the DJ
                    Button {
                        if engine.running { engine.stop() } else { engine.start() }
                    } label: {
                        Text(engine.running ? "STOP DJ" : "START DJ").font(.system(size: 16, weight: .heavy))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(engine.running ? Color.red : Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundColor(engine.running ? .white : .black)
                    }
                    label(engine.busy ? "DJ IS TALKING..." : (engine.running ? "DJ IS LIVE" : "DJ IS OFF"))
                    if !engine.line.isEmpty {
                        Text("\u{201C}\(engine.line)\u{201D}").italic().font(.system(size: 13)).foregroundColor(.white)
                    }

                    Stepper("DJ talks at least every \(cfg.breakMin) song\(cfg.breakMin == 1 ? "" : "s")", value: $cfg.breakMin, in: 1...10)
                        .font(.system(size: 13)).foregroundColor(.white)
                        .onChange(of: cfg.breakMin) { v in if v > cfg.breakMax { cfg.breakMax = v } }
                    Stepper("...and at most every \(cfg.breakMax) (random in between)", value: $cfg.breakMax, in: 1...10)
                        .font(.system(size: 13)).foregroundColor(.white)
                        .onChange(of: cfg.breakMax) { v in if v < cfg.breakMin { cfg.breakMin = v } }
                    Stepper("Stinger chance: \(cfg.stingerChance)% of silent breaks", value: $cfg.stingerChance, in: 0...100, step: 5)
                        .font(.system(size: 13)).foregroundColor(.white)

                    sliderRow("DJ VOLUME", value: $cfg.djVolume)
                    sliderRow("STINGER VOLUME", value: $cfg.stingerVolume)

                    VStack(alignment: .leading, spacing: 6) {
                        label("DJ MOOD")
                        Picker("Mood", selection: $cfg.mood) {
                            Text("Chill").tag("chill")
                            Text("Normal").tag("normal")
                            Text("Unhinged").tag("unhinged")
                            Text("Mixed").tag("mixed")
                        }.pickerStyle(.segmented)
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
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        label("ACTIVITY")
                        ScrollView {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(engine.log.enumerated()), id: \.offset) { item in
                                    Text(item.element).font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(Color(red: 0.6, green: 0.82, blue: 0.66))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }.padding(8)
                        }
                        .frame(height: 180).background(Color.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .semibold)).foregroundColor(Color.white.opacity(0.6)).tracking(1)
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous)).foregroundColor(.white)
        }
    }

    private func queueButton(_ title: String, _ style: String) -> some View {
        Button { engine.queue(style) } label: {
            Text(title).font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous)).foregroundColor(.white)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(engine.queued == style ? Color.white : Color.clear, lineWidth: 2))
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label(title)
            Slider(value: value, in: 0...100).tint(.white)
        }
    }
}

extension View {
    /// Frosted-glass panel: blurs whatever is behind it, with a thin light edge.
    func frosted(_ radius: CGFloat = 22) -> some View {
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}

struct SettingsView: View {
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var cfg: Config
    @Environment(\.dismiss) private var dismiss
    @State private var cityText = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("SPOTIFY")) {
                    TextField("Client ID", text: $cfg.clientID).textInputAutocapitalization(.never).autocorrectionDisabled(true)
                    Text("In your Spotify app settings, add this Redirect URI:  caradj://callback").font(.footnote)
                    Button(Spotify.shared.isLoggedIn ? "Log out of Spotify" : "Connect Spotify") {
                        if Spotify.shared.isLoggedIn { Spotify.shared.logout(); engine.connected = false }
                        else { dismiss(); Task { await engine.connect() } }
                    }
                }
                Section(header: Text("ELEVENLABS (YOUR VOICE)")) {
                    SecureField("API key (starts with sk_)", text: $cfg.elevenKey).textInputAutocapitalization(.never)
                    TextField("Voice ID", text: $cfg.elevenVoice).textInputAutocapitalization(.never).autocorrectionDisabled(true)
                    Picker("Model", selection: $cfg.elevenModel) {
                        Text("Eleven v4 (most expressive)").tag("eleven_v4")
                        Text("Eleven v4 Turbo (faster)").tag("eleven_v4_turbo")
                        Text("Multilingual v2 (older)").tag("eleven_multilingual_v2")
                    }
                }
                Section(header: Text("GEMINI (WRITES HER LINES)")) {
                    SecureField("API key", text: $cfg.geminiKey).textInputAutocapitalization(.never)
                }
                Section(header: Text("TOWN")) {
                    TextField("Yakima, Washington", text: $cityText).onSubmit { Task { await engine.changeCity(cityText) } }
                    Button("Save town") { Task { await engine.changeCity(cityText) } }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { Task { await engine.changeCity(cityText) }; dismiss() } } }
            .onAppear { cityText = cfg.city }
        }
    }
}

/// A rectangle with only its top two corners rounded.
struct TopRounded: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: [.topLeft, .topRight],
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var cfg: Config
    @State private var showSettings = false
    @State private var showOptions = false
    @State private var showLyrics = false
    @StateObject private var lyrics = LyricsStore()
    // the cover that is currently on screen; it only changes once the next one has fully loaded, then cross-fades
    @State private var shown: UIImage? = nil
    @State private var shownKey = ""
    @State private var accent = Color(red: 0.25, green: 0.2, blue: 0.2)
    @State private var dragFrac: Double? = nil

    private var artURL: URL? {
        if let s = engine.now.track?.art, !s.isEmpty { return URL(string: s) }
        return nil
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 8)
                    cover
                    Spacer().frame(height: 24)
                    bottomPanel
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
                .contentShape(Rectangle())
                // swipe up anywhere on the player to open the lyrics
                .simultaneousGesture(
                    DragGesture(minimumDistance: 30).onEnded { v in
                        if v.translation.height < -60 && abs(v.translation.width) < abs(v.translation.height) * 1.25 {
                            withAnimation(.easeInOut(duration: 0.3)) { showLyrics = true }
                        }
                    }
                )
                lyricsCard
            }

            if showLyrics {
                lyricsOverlay.transition(.move(edge: .bottom))
            }
        }
        .preferredColorScheme(.dark)
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
        .frame(maxWidth: min(UIScreen.main.bounds.width * 0.78, UIScreen.main.bounds.height * 0.42, 400))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 22, y: 10)
    }

    // MARK: lyrics
    private var lyricsKey: String { (engine.now.track?.title ?? "") + "|" + (engine.now.track?.artist ?? "") }

    private var lyricsOverlay: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(engine.now.track?.title ?? "Nothing playing").font(.system(size: 16, weight: .bold)).foregroundColor(.white).lineLimit(1)
                        Text(engine.now.track?.artist ?? "").font(.system(size: 13)).foregroundColor(Color.white.opacity(0.7)).lineLimit(1)
                    }
                    Spacer()
                    Button { withAnimation(.easeInOut(duration: 0.3)) { showLyrics = false } } label: {
                        Image(systemName: "chevron.down").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                            .frame(width: 34, height: 34).background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 8)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 20).onEnded { v in
                    if v.translation.height > 60 { withAnimation(.easeInOut(duration: 0.3)) { showLyrics = false } }
                })

                lyricsBody

                HStack(spacing: 58) {
                    transport("ic_prev", size: 24) { Task { await engine.previous() } }
                    transport(engine.now.isPlaying ? "ic_pause" : "ic_play", size: 38) { Task { await engine.togglePlay() } }
                    transport("ic_next", size: 24) { Task { await engine.next() } }
                }
                .padding(.bottom, 10)
            }
        }
        .task(id: lyricsKey) { await lyrics.load(engine.now.track, durationMs: engine.now.durationMs) }
    }

    @ViewBuilder
    private var lyricsBody: some View {
        if !lyrics.lines.isEmpty {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let pos = engine.now.currentProgressMs + 250
                let cur = lyrics.lines.lastIndex(where: { $0.timeMs <= pos }) ?? -1
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            Spacer().frame(height: 120)
                            ForEach(lyrics.lines) { line in
                                Text(line.text.isEmpty ? "\u{266A}" : line.text)
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(line.id == cur ? .white : Color.white.opacity(0.35))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(line.id)
                            }
                            Spacer().frame(height: 200)
                        }
                        .padding(.horizontal, 22)
                    }
                    .onChange(of: cur) { c in
                        if c >= 0 { withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo(c, anchor: .center) } }
                    }
                }
            }
        } else if !lyrics.plain.isEmpty {
            ScrollView(showsIndicators: false) {
                Text(lyrics.plain).font(.system(size: 22, weight: .semibold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(22)
            }
        } else {
            Spacer()
            Text(lyrics.status).font(.system(size: 14)).foregroundColor(Color.white.opacity(0.7)).padding(22)
            Spacer()
        }
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
        VStack(spacing: 20) {
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
                    Image("ic_dj").renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 15, height: 15)
                        .foregroundColor(engine.running ? .black : .white)
                        .frame(width: 30, height: 30)
                        .background(engine.running ? AnyShapeStyle(Color.white) : AnyShapeStyle(Material.ultraThinMaterial), in: Circle())
                }
                Button { showOptions = true } label: {
                    Image("ic_more").renderingMode(.template).resizable().scaledToFit().frame(width: 17, height: 6).foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }

            progress
            controls
            deviceRow
        }
    }

    // shuffle, previous, the big round play/pause, next, repeat
    private var controls: some View {
        let repeatOn = engine.now.repeatMode != "off"
        return HStack {
            modeButton("ic_shuffle", on: engine.now.shuffle) { Task { await engine.toggleShuffle() } }
            Spacer()
            transport("ic_prev", size: 24) { Task { await engine.previous() } }
            Spacer()
            Button { Task { await engine.togglePlay() } } label: {
                ZStack {
                    Circle().fill(Color.white)
                    Image(engine.now.isPlaying ? "ic_pause" : "ic_play").renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 22, height: 22).foregroundColor(.black)
                        .offset(x: engine.now.isPlaying ? 0 : 2)
                }
                .frame(width: 60, height: 60)
            }
            Spacer()
            transport("ic_next", size: 24) { Task { await engine.next() } }
            Spacer()
            modeButton(engine.now.repeatMode == "track" ? "ic_repeat1" : "ic_repeat", on: repeatOn) { Task { await engine.cycleRepeat() } }
        }
    }

    private func modeButton(_ icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(icon).renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 21, height: 21)
                    .foregroundColor(on ? green : Color.white.opacity(0.85))
                Circle().fill(on ? green : Color.clear).frame(width: 5, height: 5)
            }
            .frame(width: 38, height: 38)
        }
    }

    // which device is playing
    private var deviceRow: some View {
        HStack(spacing: 10) {
            Image("ic_speaker").renderingMode(.template).resizable().scaledToFit()
                .frame(width: 17, height: 17).foregroundColor(green)
            Text(engine.now.deviceName.isEmpty ? "This device" : engine.now.deviceName)
                .font(.system(size: 13)).foregroundColor(green).lineLimit(1)
            Spacer()
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
            Image(symbol).renderingMode(.template).resizable().scaledToFit()
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .frame(minWidth: 46, minHeight: 46)
        }
        .shadow(color: .black.opacity(0.4), radius: 6)
    }

    // MARK: the lyrics card at the bottom (tap to open the full lyrics page)
    private var lyricsCard: some View {
        Button { withAnimation(.easeInOut(duration: 0.3)) { showLyrics = true } } label: {
            VStack(spacing: 8) {
                Capsule().fill(Color.white.opacity(0.35)).frame(width: 36, height: 4)
                HStack {
                    Text("Lyrics").font(.system(size: 16, weight: .bold))
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30).background(Color.black.opacity(0.22), in: Circle())
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TopRounded(radius: 22).fill(accent).ignoresSafeArea(edges: .bottom))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
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

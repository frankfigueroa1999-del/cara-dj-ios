import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var cfg: Config
    @State private var showSettings = false
    @State private var showOptions = false

    private var artURL: URL? {
        if let s = engine.now.track?.art, !s.isEmpty { return URL(string: s) }
        return nil
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomPanel
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 10)
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
            if let u = artURL {
                Color.clear.overlay(
                    AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { Color.clear }
                ).clipped()
            }
            // darkens the bottom so the text and buttons stay readable
            LinearGradient(colors: [Color.black.opacity(0.35), .clear, .clear, Color.black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
        }
        .animation(.easeInOut(duration: 0.6), value: engine.now.track?.art ?? "")
        .ignoresSafeArea()
    }

    // MARK: pieces
    private var topBar: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NON STOP POP").font(.system(size: 12, weight: .heavy)).foregroundColor(.white).tracking(2)
                    Text("LIVE FROM \(cfg.city.uppercased())").font(.system(size: 9)).foregroundColor(Color.white.opacity(0.7)).tracking(1)
                }
                Spacer()
            }
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

    private var bottomPanel: some View {
        VStack(spacing: 22) {
            // song name and artist, with the "..." button that opens every DJ option
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.now.track?.title ?? (engine.connected ? "Nothing playing" : "Not connected"))
                        .font(.system(size: 22, weight: .bold)).foregroundColor(.white).lineLimit(2)
                    Text(engine.now.track?.artist ?? "Start a playlist in the Spotify app.")
                        .font(.system(size: 18)).foregroundColor(Color.white.opacity(0.7)).lineLimit(1)
                }
                .shadow(color: .black.opacity(0.5), radius: 6)
                Spacer(minLength: 8)
                Button { showOptions = true } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }

            progress

            HStack(spacing: 58) {
                transport("ic_prev", size: 34) { Task { await engine.previous() } }
                transport(engine.now.isPlaying ? "ic_pause" : "ic_play", size: 42) { Task { await engine.togglePlay() } }
                transport("ic_next", size: 34) { Task { await engine.next() } }
            }

            djButton
        }
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let dur = max(engine.now.durationMs, 1)
            let cur = min(engine.now.currentProgressMs, dur)
            VStack(spacing: 6) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.3))
                        Capsule().fill(Color.white).frame(width: g.size.width * CGFloat(cur) / CGFloat(dur))
                    }
                }
                .frame(height: 5)
                HStack {
                    Text(ContentView.clock(cur))
                    Spacer()
                    Text("-" + ContentView.clock(dur - cur))
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
                .frame(minWidth: 56, minHeight: 56)
        }
        .shadow(color: .black.opacity(0.4), radius: 6)
    }

    /// Bottom-centre: starts and stops the DJ.
    private var djButton: some View {
        VStack(spacing: 6) {
            Button {
                if engine.running { engine.stop() } else { engine.start() }
            } label: {
                Image("ic_dj").renderingMode(.template).resizable().scaledToFit().frame(width: 26, height: 26)
                    .foregroundColor(engine.running ? .black : .white)
                    .frame(width: 54, height: 54)
                    .background(engine.running ? AnyShapeStyle(Color.white) : AnyShapeStyle(Material.ultraThinMaterial), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
            }
            Text(engine.busy ? "DJ IS TALKING..." : (engine.running ? "DJ IS LIVE - TAP TO STOP" : "START DJ"))
                .font(.system(size: 10, weight: .semibold)).foregroundColor(Color.white.opacity(0.75)).tracking(1)
            if !engine.line.isEmpty {
                Text("\u{201C}\(engine.line)\u{201D}").italic().font(.system(size: 12)).foregroundColor(.white)
                    .multilineTextAlignment(.center).lineLimit(3)
                    .shadow(color: .black.opacity(0.5), radius: 4)
            }
        }
        .padding(.top, 4)
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

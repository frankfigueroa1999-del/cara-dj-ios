import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var cfg: Config
    @State private var showSettings = false

    private let bg = Color(red: 0.05, green: 0.05, blue: 0.05)
    private let card = Color(red: 0.11, green: 0.11, blue: 0.11)

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if !engine.connected { connectButton }
                    nowPlaying
                    djCard
                    activity
                }
                .padding(16)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(engine).environmentObject(cfg) }
        .task {
            engine.startBackgroundPolling()
            if Spotify.shared.isLoggedIn { await engine.connect() }
            else if cfg.clientID.isEmpty { showSettings = true }
        }
    }

    // MARK: pieces
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("NON STOP POP").font(.system(size: 22, weight: .heavy)).foregroundColor(.white).tracking(2)
                Text("LIVE FROM \(cfg.city.uppercased())").font(.system(size: 10)).foregroundColor(.gray).tracking(1)
            }
            Spacer()
            Button("SETTINGS") { showSettings = true }
                .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
        }
    }

    private var connectButton: some View {
        Button {
            Task { await engine.connect() }
        } label: {
            Text("CONNECT SPOTIFY").font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color.white).foregroundColor(.black)
        }
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOW PLAYING").font(.system(size: 10, weight: .semibold)).foregroundColor(.gray).tracking(1)
            Text(engine.now.track?.title ?? (engine.connected ? "Nothing playing" : "Not connected"))
                .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
            Text(engine.now.track?.artist ?? "Start a playlist in the Spotify app.")
                .font(.system(size: 14)).foregroundColor(.gray)
            ProgressView(value: engine.now.durationMs > 0 ? Double(engine.now.currentProgressMs) / Double(engine.now.durationMs) : 0)
                .tint(.white)
            HStack(spacing: 12) {
                pill("PREV") { Task { await engine.previous() } }
                pill(engine.now.isPlaying ? "PAUSE" : "PLAY") { Task { await engine.togglePlay() } }
                pill("NEXT") { Task { await engine.next() } }
            }
        }
        .padding(16).background(card)
    }

    private var djCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                if engine.running { engine.stop() } else { engine.start() }
            } label: {
                Text(engine.running ? "STOP DJ" : "START DJ").font(.system(size: 16, weight: .heavy))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(engine.running ? Color.red : Color.white)
                    .foregroundColor(engine.running ? .white : .black)
            }
            Text(engine.busy ? "DJ IS TALKING..." : (engine.running ? "DJ IS LIVE" : "DJ IS OFF"))
                .font(.system(size: 10, weight: .semibold)).foregroundColor(.gray).tracking(1)
            if !engine.line.isEmpty {
                Text("\u{201C}\(engine.line)\u{201D}").italic().font(.system(size: 13)).foregroundColor(.white)
            }

            Divider().background(Color.gray.opacity(0.4))

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
                Text("DJ MOOD").font(.system(size: 10, weight: .semibold)).foregroundColor(.gray).tracking(1)
                Picker("Mood", selection: $cfg.mood) {
                    Text("Chill").tag("chill")
                    Text("Normal").tag("normal")
                    Text("Unhinged").tag("unhinged")
                    Text("Mixed").tag("mixed")
                }.pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("QUEUE NEXT (AT THE END OF THIS SONG)").font(.system(size: 10, weight: .semibold)).foregroundColor(.gray).tracking(1)
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
        }
        .padding(16).background(card)
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ACTIVITY").font(.system(size: 10, weight: .semibold)).foregroundColor(.gray).tracking(1)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(engine.log.enumerated()), id: \.offset) { item in
                        Text(item.element).font(.system(size: 11, design: .monospaced)).foregroundColor(Color(red: 0.6, green: 0.82, blue: 0.66))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(8)
            }
            .frame(height: 200).background(Color.black)
        }
    }

    // MARK: small builders
    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(Color(red: 0.17, green: 0.17, blue: 0.17)).foregroundColor(.white)
        }
    }

    private func queueButton(_ title: String, _ style: String) -> some View {
        Button { engine.queue(style) } label: {
            Text(title).font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(Color(red: 0.17, green: 0.17, blue: 0.17)).foregroundColor(.white)
                .overlay(Rectangle().stroke(engine.queued == style ? Color.white : Color.clear, lineWidth: 2))
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundColor(.gray).tracking(1)
            Slider(value: value, in: 0...100).tint(.white)
        }
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

import SwiftUI

/// Keys, Spotify connection, town and appearance.
struct SettingsView: View {
    @Environment(Engine.self) private var engine
    @Environment(Library.self) private var library
    @EnvironmentObject private var cfg: Config
    @Environment(\.dismiss) private var dismiss
    @State private var cityText = ""
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Artwork(library.me?.image, px: 150, circle: true)
                            .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(library.me?.name ?? (Spotify.shared.isLoggedIn ? "Spotify" : "Not connected"))
                                .font(.headline)
                            Text(Spotify.shared.isLoggedIn ? (engine.connected ? "Connected to Spotify" : "Logged in") : "Connect to use the player")
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    if Spotify.shared.isLoggedIn {
                        if library.needsReconnect {
                            Button("Reconnect Spotify (unlocks your library)") {
                                dismiss()
                                Task { await engine.connect(forceLogin: true) }
                            }
                        }
                        Button("Log Out of Spotify", role: .destructive) { confirmLogout = true }
                    } else {
                        Button("Connect Spotify") {
                            dismiss()
                            Task { await engine.connect(forceLogin: true) }
                        }
                        .disabled(cfg.clientID.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section {
                    TextField("Client ID", text: $cfg.clientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                } header: {
                    Text("Spotify App")
                } footer: {
                    Text("From developer.spotify.com. Its Redirect URI must be caradj://callback, and everyone using it has to be added under User Management (5 people at most).")
                }
                Section {
                    SecureField("API key (starts with sk_)", text: $cfg.elevenKey)
                        .textInputAutocapitalization(.never)
                    TextField("Voice ID", text: $cfg.elevenVoice)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    Picker("Model", selection: $cfg.elevenModel) {
                        Text("Eleven v4 (most expressive)").tag("eleven_v4")
                        Text("Eleven v4 Turbo (faster)").tag("eleven_v4_turbo")
                        Text("Multilingual v2 (older)").tag("eleven_multilingual_v2")
                    }
                } header: {
                    Text("Her Voice (ElevenLabs)")
                }
                Section {
                    SecureField("API key", text: $cfg.geminiKey)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Her Words (Gemini)")
                } footer: {
                    Text("Without a key she still talks, using simpler built-in lines.")
                }
                Section {
                    TextField("Yakima, Washington", text: $cityText)
                        .onSubmit { Task { await engine.changeCity(cityText) } }
                } header: {
                    Text("Your Town")
                } footer: {
                    Text("Town, State. Used for local news and weather.")
                }
                Section {
                    Picker("Appearance", selection: $cfg.appearance) {
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                        Text("Match iPhone").tag("system")
                    }
                } header: {
                    Text("Look")
                }
                Section {
                    Button("Show the Welcome Setup Again") {
                        dismiss()
                        let c = cfg
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { c.welcomed = false }
                    }
                } footer: {
                    Text("Cara DJ 2.0. Music plays through the Spotify app; Cara talks over it from here.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task { await engine.changeCity(cityText) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { cityText = cfg.city }
            .confirmationDialog("Log out of Spotify?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Log Out", role: .destructive) { engine.logout() }
                Button("Cancel", role: .cancel) { }
            }
        }
    }
}

/// First launch: a short, friendly setup. Shown once.
struct WelcomeView: View {
    @Environment(Engine.self) private var engine
    @Environment(Library.self) private var library
    @EnvironmentObject private var cfg: Config
    @State private var step = 0
    @State private var connecting = false
    @State private var connectError = ""
    @State private var cityText = ""
    @State private var forward = true

    var body: some View {
        ZStack {
            Theme.caraGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    if step > 0 && step < 5 {
                        Button {
                            go(step - 1)
                        } label: {
                            Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                        }
                    }
                    Spacer()
                    if step > 0 && step < 5 {
                        Text("\(step) of 4").font(.footnote.weight(.semibold)).opacity(0.8)
                        Spacer()
                        Button("Skip") { go(step + 1) }
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 22)
                .frame(height: 44)

                ZStack {
                    page
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .frame(maxHeight: .infinity)
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear { cityText = cfg.city }
    }

    private func go(_ s: Int) {
        Haptics.tap()
        forward = s > step
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step = max(0, min(5, s)) }
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case 0: hello
        case 1: spotifyStep
        case 2: voiceStep
        case 3: wordsStep
        case 4: townStep
        default: doneStep
        }
    }

    private var hello: some View {
        VStack(spacing: 22) {
            Spacer()
            StationLogo(active: true).frame(width: 150, height: 104)
            VStack(spacing: 10) {
                Text("Welcome to Cara DJ")
                    .font(.system(size: 34, weight: .heavy))
                    .multilineTextAlignment(.center)
                Text("Your own Non Stop Pop station. Cara talks between your Spotify songs about your town, the news, the music, and you.")
                    .font(.system(size: 17))
                    .opacity(0.85)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Text("I'll help you set up.").font(.headline).opacity(0.9)
            bigButton("Let's Go") { go(1) }
        }
        .foregroundStyle(Color.white)
        .padding(28)
    }

    private var spotifyStep: some View {
        stepPage(icon: "music.note", title: "Spotify",
                 text: "Make a free app at developer.spotify.com, set its Redirect URI to caradj://callback, add your Spotify email under User Management, then paste its Client ID here.") {
            field("Client ID", text: $cfg.clientID, secure: false)
            if Spotify.shared.isLoggedIn && engine.connected {
                Label("Connected" + (library.me.map { " as " + $0.name } ?? ""), systemImage: "checkmark.circle.fill")
                    .font(.headline)
            } else if !connectError.isEmpty {
                Text(connectError).font(.footnote).opacity(0.85)
            }
            bigButton(connecting ? "Connecting…" : (Spotify.shared.isLoggedIn && engine.connected ? "Next" : "Connect Spotify")) {
                if Spotify.shared.isLoggedIn && engine.connected { go(2); return }
                guard !cfg.clientID.trimmingCharacters(in: .whitespaces).isEmpty else {
                    connectError = "Paste the Client ID first."
                    return
                }
                connecting = true
                connectError = ""
                Task {
                    await engine.connect(forceLogin: true)
                    connecting = false
                    if engine.connected { go(2) } else { connectError = "That didn't work. Check the Client ID and Redirect URI, then try again." }
                }
            }
            .disabled(connecting)
        }
    }

    private var voiceStep: some View {
        stepPage(icon: "waveform", title: "Her Voice",
                 text: "Cara speaks with an ElevenLabs voice. Paste your API key (the secret one that starts with sk_) and the Voice ID.") {
            field("API key", text: $cfg.elevenKey, secure: true)
            field("Voice ID", text: $cfg.elevenVoice, secure: false)
            bigButton("Next") { go(3) }
        }
    }

    private var wordsStep: some View {
        stepPage(icon: "text.bubble.fill", title: "Her Words",
                 text: "Gemini writes what she says. A free key from Google AI Studio is plenty.") {
            field("Gemini API key", text: $cfg.geminiKey, secure: true)
            bigButton("Next") { go(4) }
        }
    }

    private var townStep: some View {
        stepPage(icon: "mappin.and.ellipse", title: "Your Town",
                 text: "She talks about your local news and weather. Town, State works best.") {
            field("Yakima, Washington", text: $cityText, secure: false)
            bigButton("Next") {
                Task { await engine.changeCity(cityText) }
                go(5)
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 76))
                .symbolRenderingMode(.hierarchical)
            VStack(spacing: 10) {
                Text(thanks)
                    .font(.system(size: 32, weight: .heavy))
                    .multilineTextAlignment(.center)
                Text("Enjoy the DJ app.")
                    .font(.system(size: 20, weight: .medium))
                    .opacity(0.9)
            }
            Spacer()
            bigButton("Start Listening") {
                Haptics.success()
                cfg.welcomed = true
            }
        }
        .foregroundStyle(Color.white)
        .padding(28)
    }

    private var thanks: String {
        guard let name = library.me?.name, !name.isEmpty else { return "Thank you." }
        let first = name.split(separator: " ").first.map(String.init) ?? name
        return "Thank you, " + first + "."
    }

    // MARK: building blocks
    private func stepPage<C: View>(icon: String, title: String, text: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 64, height: 64)
                .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 20)
            Text(title).font(.system(size: 34, weight: .heavy))
            Text(text).font(.system(size: 17)).opacity(0.88)
            Spacer().frame(height: 4)
            content()
            Spacer()
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
    }

    private func field(_ placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
        .font(.system(size: 17))
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func bigButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

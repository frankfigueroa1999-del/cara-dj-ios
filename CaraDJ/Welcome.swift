import SwiftUI

/// The first launch, as an unboxing: a matte black lid you pull up, Cara waiting inside,
/// four calm setup steps on frosted glass, a checkmark that draws itself, and the app rising into view.
struct WelcomeView: View {
    @Environment(Engine.self) private var engine
    @Environment(Library.self) private var library
    @EnvironmentObject private var cfg: Config

    fileprivate enum Stage: Int { case hello = 0, spotify, voice, words, town, done }
    private enum Field: Hashable { case client, key, voice, gemini, town }

    @State private var stage: Stage = .hello
    @State private var forward = true
    // the box
    @State private var boxHeight: CGFloat = 900
    @State private var lift: CGFloat = 0
    @State private var lidGone = false
    @State private var lifting = false
    @State private var touched = false
    @State private var hint = false
    // inside
    @State private var awake = false
    @State private var breathe = false
    @State private var leaving = false
    @State private var ring = false
    @State private var tick = false
    // setup
    @State private var connecting = false
    @State private var connectError = ""
    @State private var cityText = ""
    @FocusState private var focus: Field?

    var body: some View {
        ZStack {
            inside
                .scaleEffect(lidGone ? 1 : 0.9 + 0.1 * openness)
                .opacity(lidGone ? 1 : Double(0.25 + 0.75 * openness))
            if !lidGone {
                lid
                    .offset(y: -lift)
                    .ignoresSafeArea()
            }
        }
        .background(
            GeometryReader { g in
                Color.clear.onAppear {
                    boxHeight = g.size.height + g.safeAreaInsets.top + g.safeAreaInsets.bottom
                }
            }
        )
        .environment(\.colorScheme, .dark)
        .scaleEffect(leaving ? 1.07 : 1)
        .blur(radius: leaving ? 16 : 0)
        .opacity(leaving ? 0 : 1)
        .onAppear {
            cityText = cfg.city
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { hint = true }
        }
    }

    private var openness: CGFloat { min(1, max(0, lift / max(boxHeight, 1))) }

    // MARK: - The lid
    private var lid: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.095), Color(white: 0.035)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(0.07), .clear], center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: 400)
            // the logo, pressed into the lid
            VStack(spacing: 26) {
                StationLogo(active: false, color: Color.white.opacity(0.13))
                    .frame(width: 96, height: 66)
                    .shadow(color: Color.black.opacity(0.9), radius: 0, x: 0, y: -1)
                    .shadow(color: Color.white.opacity(0.09), radius: 0, x: 0, y: 1)
                Text("CARA DJ")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(7)
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            .offset(y: -24)
            // the pull tab
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .offset(y: hint ? -5 : 1)
                Text("PULL UP TO OPEN")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(Color.white.opacity(0.32))
                Capsule()
                    .fill(Color.white.opacity(0.24))
                    .frame(width: 44, height: 5)
                    .padding(.top, 8)
            }
            .padding(.bottom, 46)
            .opacity(Double(1 - min(1, lift / 120)))
        }
        .overlay(alignment: .bottom) {
            // the edge of the lid catching the light as it lifts
            Color.white.opacity(0.14).frame(height: 1)
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(lift > 1 ? 0.8 : 0), radius: 36, y: 26)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { v in
                    guard !lifting else { return }
                    if !touched {
                        touched = true
                        Haptics.soft()
                    }
                    // a snug lid: it gives a little less than you pull
                    lift = max(0, -v.translation.height) * 0.72
                }
                .onEnded { v in
                    guard !lifting else { return }
                    let pulledUp = -v.translation.height
                    let flung = -v.predictedEndTranslation.height
                    if pulledUp > 110 || flung > 340 {
                        openLid()
                    } else {
                        touched = false
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { lift = 0 }
                    }
                }
        )
        .onTapGesture { openLid() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cara DJ")
        .accessibilityHint("Opens the welcome setup")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openLid() }
    }

    private func openLid() {
        guard !lifting else { return }
        lifting = true
        Haptics.firm()
        // slow, like a lid sliding off a snug box
        withAnimation(.timingCurve(0.55, 0.0, 0.2, 1.0, duration: 1.25)) { lift = boxHeight + 140 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            awake = true
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) { breathe = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { lidGone = true }
    }

    // MARK: - Inside the box
    private var inside: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            CaraGlow()
                .scaleEffect(breathe ? 1.12 : 1)
                .opacity(breathe ? 1 : 0.72)
                .ignoresSafeArea()
            stageView
                .id(stage)
                .transition(.asymmetric(
                    insertion: .welcomeBlur(x: forward ? 36 : -36, scale: 1.03),
                    removal: .welcomeBlur(x: forward ? -36 : 36, scale: 0.97)))
            if stage != .hello && stage != .done {
                VStack {
                    topBar
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .foregroundStyle(Color.white)
    }

    @ViewBuilder
    private var stageView: some View {
        switch stage {
        case .hello: hello
        case .spotify: spotifyStep
        case .voice: voiceStep
        case .words: wordsStep
        case .town: townStep
        case .done: finale
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                go(Stage(rawValue: stage.rawValue - 1) ?? .hello)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back")
            Spacer()
            HStack(spacing: 6) {
                ForEach(1..<5, id: \.self) { i in
                    Capsule()
                        .fill(i <= stage.rawValue ? Color.white : Color.white.opacity(0.22))
                        .frame(width: i == stage.rawValue ? 22 : 7, height: 7)
                }
            }
            .animation(Theme.spring, value: stage)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(stage.rawValue) of 4")
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    // MARK: hello
    private var hello: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.accent.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 130))
                    .frame(width: 280, height: 280)
                    .blur(radius: 18)
                    .opacity(awake ? 1 : 0)
                    .animation(.easeOut(duration: 1.6), value: awake)
                StationLogo(active: awake)
                    .frame(width: 124, height: 86)
                    .scaleEffect(awake ? 1 : 0.86)
                    .opacity(awake ? 1 : 0)
                    .animation(.spring(response: 1.1, dampingFraction: 0.8), value: awake)
            }
            .frame(height: 200)
            Text("Hi, I'm Cara.")
                .font(.system(size: 40, weight: .bold))
                .padding(.top, 28)
                .modifier(Reveal(on: awake, delay: 0.35))
            Text("Your own Non Stop Pop station.")
                .font(.system(size: 19))
                .foregroundStyle(Theme.text2)
                .padding(.top, 10)
                .modifier(Reveal(on: awake, delay: 0.65))
            Spacer()
            Button {
                go(.spotify)
            } label: {
                PillLabel(title: "Set Up", primary: true, height: 54)
            }
            .buttonStyle(PressableStyle())
            .padding(.horizontal, 32)
            .modifier(Reveal(on: awake, delay: 1.15))
            Text("Takes about a minute.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text3)
                .padding(.top, 14)
                .padding(.bottom, 20)
                .modifier(Reveal(on: awake, delay: 1.3))
        }
        .multilineTextAlignment(.center)
    }

    // MARK: the four steps
    private var spotifyConnected: Bool { engine.loggedIn && engine.connected }

    private var spotifyStep: some View {
        step(icon: "music.note",
             title: "Spotify",
             text: "Make a free app in the Spotify developer dashboard, set its Redirect URI to caradj://callback, add your Spotify email under User Management, then paste its Client ID here.",
             primary: connecting ? "Connecting…" : (spotifyConnected ? "Continue" : "Connect Spotify"),
             next: .voice,
             action: connectSpotify) {
            field("Client ID", "Paste it here", text: $cfg.clientID, secure: false, id: .client)
            if spotifyConnected {
                Label(connectedText, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NowPlayingView.green)
                    .transition(.opacity)
            } else if !connectError.isEmpty {
                Text(connectError)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            if let u = URL(string: "https://developer.spotify.com/dashboard") {
                Link(destination: u) {
                    HStack(spacing: 4) {
                        Text("Open the developer dashboard")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.text2)
                }
            }
        }
    }

    private var voiceStep: some View {
        step(icon: "waveform",
             title: "Her Voice",
             text: "Cara speaks with an ElevenLabs voice. Paste your API key (the secret one that starts with sk_) and the Voice ID.",
             primary: "Continue",
             next: .words,
             action: { go(.words) }) {
            field("API Key", "sk_…", text: $cfg.elevenKey, secure: true, id: .key)
            field("Voice ID", "Voice ID", text: $cfg.elevenVoice, secure: false, id: .voice)
        }
    }

    private var wordsStep: some View {
        step(icon: "text.bubble",
             title: "Her Words",
             text: "Gemini writes what she says. A free key from Google AI Studio is plenty. Without one she still talks, with simpler lines.",
             primary: "Continue",
             next: .town,
             action: { go(.town) }) {
            field("Gemini API Key", "Paste it here", text: $cfg.geminiKey, secure: true, id: .gemini)
            if let u = URL(string: "https://aistudio.google.com/apikey") {
                Link(destination: u) {
                    HStack(spacing: 4) {
                        Text("Get a free key")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.text2)
                }
            }
        }
    }

    private var townStep: some View {
        step(icon: "mappin.and.ellipse",
             title: "Your Town",
             text: "She talks about your local news and weather. Town, State works best.",
             primary: "Continue",
             next: .done,
             action: {
                 let c = cityText
                 Task { await engine.changeCity(c) }
                 go(.done)
             }) {
            field("Town", "Yakima, Washington", text: $cityText, secure: false, id: .town)
        }
    }

    private func connectSpotify() {
        if spotifyConnected { go(.voice); return }
        guard !cfg.clientID.trimmingCharacters(in: .whitespaces).isEmpty else {
            withAnimation(.easeInOut(duration: 0.25)) { connectError = "Paste the Client ID first." }
            focus = .client
            return
        }
        focus = nil
        connecting = true
        withAnimation(.easeInOut(duration: 0.25)) { connectError = "" }
        Task {
            await engine.connect(forceLogin: true)
            connecting = false
            if engine.connected {
                Haptics.success()
                try? await Task.sleep(nanoseconds: 700_000_000)
                go(.voice)
            } else {
                let why = engine.problem.isEmpty
                    ? "That didn't work. Check the Client ID and that the Redirect URI is caradj://callback, then try again."
                    : engine.problem
                withAnimation(.easeInOut(duration: 0.25)) { connectError = why }
            }
        }
    }

    private var connectedText: String {
        if let n = library.me?.name, !n.isEmpty { return "Connected as " + n }
        return "Connected"
    }

    // MARK: the finale
    private var finale: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.7))
                Circle()
                    .trim(from: 0, to: ring ? 1 : 0)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                CheckShape()
                    .trim(from: 0, to: tick ? 1 : 0)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    .frame(width: 50, height: 38)
                    .offset(x: 2, y: 2)
            }
            .frame(width: 128, height: 128)
            .shadow(color: Theme.accent.opacity(tick ? 0.55 : 0), radius: 34)
            .animation(.easeOut(duration: 0.8), value: tick)
            Text(allSet)
                .font(.system(size: 32, weight: .bold))
                .padding(.top, 40)
                .modifier(Reveal(on: tick, delay: 0.25))
            Text("Enjoy the show.")
                .font(.system(size: 19))
                .foregroundStyle(Theme.text2)
                .padding(.top, 10)
                .modifier(Reveal(on: tick, delay: 0.5))
            Spacer()
            Button {
                finish()
            } label: {
                PillLabel(title: "Start Listening", primary: true, height: 54)
            }
            .buttonStyle(PressableStyle())
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .modifier(Reveal(on: tick, delay: 0.85))
        }
        .multilineTextAlignment(.center)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).delay(0.3)) { ring = true }
            withAnimation(.easeOut(duration: 0.4).delay(1.05)) { tick = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { Haptics.success() }
        }
    }

    private var allSet: String {
        guard let name = library.me?.name, !name.isEmpty else { return "You're all set." }
        let first = name.split(separator: " ").first.map(String.init) ?? name
        return "You're all set, " + first + "."
    }

    private func finish() {
        Haptics.firm()
        focus = nil
        withAnimation(.easeIn(duration: 0.6)) { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeInOut(duration: 0.45)) { cfg.welcomed = true }
        }
    }

    // MARK: - Building blocks
    private func go(_ s: Stage) {
        focus = nil
        Haptics.tap()
        forward = s.rawValue > stage.rawValue
        // let the page that's leaving learn which way it goes before it goes
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.9)) { stage = s }
        }
    }

    private func step<F: View>(icon: String, title: String, text: String, primary: String, next: Stage,
                               action: @escaping () -> Void, @ViewBuilder fields: () -> F) -> some View {
        let card = VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 23, weight: .regular))
                .frame(width: 56, height: 56)
                .glass(28, tint: 0.1)
                .padding(.bottom, 20)
            Text(title)
                .font(.system(size: 30, weight: .bold))
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 14) {
                fields()
            }
            .padding(.top, 22)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(30, tint: 0.055)
        .padding(.horizontal, 20)

        return VStack(spacing: 0) {
            Color.clear.frame(height: 52)          // room for the back button and the dots
            ViewThatFits(in: .vertical) {
                VStack(spacing: 0) {
                    Spacer(minLength: 8)
                    card
                    Spacer(minLength: 8)
                }
                ScrollView(showsIndicators: false) {
                    card.padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            VStack(spacing: 4) {
                Button(action: action) {
                    PillLabel(title: primary, primary: true, height: 54)
                }
                .buttonStyle(PressableStyle())
                .disabled(connecting)
                Button("Skip for now") { go(next) }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text2)
                    .frame(height: 40)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 10)
        }
    }

    private func field(_ label: String, _ placeholder: String, text: Binding<String>, secure: Bool, id: Field) -> some View {
        let on = focus == id
        return VStack(alignment: .leading, spacing: 7) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.text3)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .focused($focus, equals: id)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .submitLabel(.done)
            .onSubmit { focus = nil }
            .font(.system(size: 17))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.28)))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(on ? 0.5 : 0.13), lineWidth: on ? 1 : 0.7)
            )
            .animation(.easeInOut(duration: 0.2), value: on)
        }
    }
}

/// Text and buttons that drift up into focus, one after another.
private struct Reveal: ViewModifier {
    var on: Bool
    var delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .blur(radius: on ? 0 : 10)
            .offset(y: on ? 0 : 14)
            .animation(.easeOut(duration: 0.9).delay(delay), value: on)
    }
}

/// How the setup pages come and go: a soft blur, a fade and a little drift.
private struct WelcomeBlur: ViewModifier {
    var amount: Double
    var x: CGFloat
    var scale: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(1 - amount)
            .blur(radius: 14 * amount)
            .scaleEffect(1 + (scale - 1) * amount)
            .offset(x: x * amount)
    }
}

private extension AnyTransition {
    static func welcomeBlur(x: CGFloat, scale: CGFloat) -> AnyTransition {
        .modifier(active: WelcomeBlur(amount: 1, x: x, scale: scale),
                  identity: WelcomeBlur(amount: 0, x: x, scale: scale))
    }
}

/// The tick inside the finale's circle.
private struct CheckShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.55))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.36, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

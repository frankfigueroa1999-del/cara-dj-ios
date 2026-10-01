import SwiftUI

/// Cara's tab: go live, set her mood, line up the next transition, fine-tune her, and read her log.
struct CaraView: View {
    @Environment(Engine.self) private var engine
    @Environment(Router.self) private var router
    @EnvironmentObject private var cfg: Config
    @State private var showLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                if !engine.line.isEmpty { lastLine }
                card("Next Transition", footer: "Lines up how she comes in at the end of this song.") {
                    HStack(spacing: 8) {
                        styleButton("Talk Over", "waveform", "talkover")
                        styleButton("Over Intro", "forward.end.fill", "intro")
                        styleButton("Silent", "pause.fill", "silent")
                    }
                }
                card("Right Now", footer: nil) {
                    HStack(spacing: 8) {
                        actionTile("Talk Now", "mic.fill") { engine.testBreak() }
                        actionTile("Pop In", "sparkles") { engine.testPopin() }
                        actionTile("Stinger", "bolt.fill") { Task { await engine.testStinger() } }
                    }
                }
                card("Her Mood", footer: moodFooter) {
                    Picker("Mood", selection: $cfg.mood) {
                        Text("Chill").tag("chill")
                        Text("Normal").tag("normal")
                        Text("Unhinged").tag("unhinged")
                        Text("Mixed").tag("mixed")
                    }
                    .pickerStyle(.segmented)
                }
                card("How Often She Talks", footer: "A random number of songs in between, every time.") {
                    VStack(spacing: 10) {
                        Stepper(value: $cfg.breakMin, in: 1...10) {
                            row("At least every", "\(cfg.breakMin) song\(cfg.breakMin == 1 ? "" : "s")")
                        }
                        .onChange(of: cfg.breakMin) { _, v in if v > cfg.breakMax { cfg.breakMax = v } }
                        Divider()
                        Stepper(value: $cfg.breakMax, in: 1...10) {
                            row("At most every", "\(cfg.breakMax) song\(cfg.breakMax == 1 ? "" : "s")")
                        }
                        .onChange(of: cfg.breakMax) { _, v in if v < cfg.breakMin { cfg.breakMin = v } }
                    }
                }
                card("Pop-Ins", footer: "After a talk-over or intro break she can pop back in a few seconds into the next song, over the music.") {
                    VStack(spacing: 10) {
                        Toggle(isOn: $cfg.popinEnabled) { Text("Pop back in") }
                        Divider()
                        Stepper(value: $cfg.popinChance, in: 0...100, step: 5) {
                            row("Chance", "\(cfg.popinChance)%")
                        }
                        .disabled(!cfg.popinEnabled)
                        Divider()
                        Stepper(value: $cfg.popinSeconds, in: 5...120, step: 5) {
                            row("Seconds into the song", "about \(cfg.popinSeconds)")
                        }
                        .disabled(!cfg.popinEnabled)
                        Divider()
                        Toggle(isOn: $cfg.popinTest) { Text("Test mode (after every break)") }
                            .disabled(!cfg.popinEnabled)
                    }
                }
                card("Sound", footer: "Silent breaks start with one of your stingers this often.") {
                    VStack(alignment: .leading, spacing: 12) {
                        slider("Cara's volume", value: $cfg.djVolume)
                        slider("Stinger volume", value: $cfg.stingerVolume)
                        Divider()
                        Stepper(value: $cfg.stingerChance, in: 0...100, step: 5) {
                            row("Stinger chance", "\(cfg.stingerChance)%")
                        }
                    }
                }
                card("Her Town", footer: "Local news and weather come from here.") {
                    Button {
                        router.showSettings = true
                    } label: {
                        HStack {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.accent)
                            Text(cfg.city).foregroundStyle(Color.primary)
                            Spacer()
                            Text("Change").foregroundStyle(Theme.accent)
                        }
                    }
                    .buttonStyle(.plain)
                }
                logCard
            }
            .padding(.top, 6)
        }
        .chromeInset()
        .navigationTitle("Cara")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AvatarButton()
            }
        }
    }

    private var moodFooter: String {
        switch cfg.mood {
        case "chill": return "Laid-back and dry, a bit quieter."
        case "unhinged": return "Maximum drama. Still clean, still short."
        case "mixed": return "A different mood every break."
        default: return "Her usual cheeky self."
        }
    }

    // MARK: pieces
    private var hero: some View {
        VStack(spacing: 16) {
            StationLogo(active: engine.running)
                .frame(width: 120, height: 82)
                .padding(.top, 10)
            VStack(spacing: 4) {
                Text("Non Stop Pop")
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(Color.white.opacity(0.8))
                Text(engine.running ? (engine.speaking ? "Cara's on the mic" : "Cara is live") : "Cara is off air")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Color.white)
                Text(engine.statusLine)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            Button {
                Haptics.firm()
                if engine.running { engine.stop() } else { engine.start() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: engine.running ? "stop.fill" : "dot.radiowaves.left.and.right")
                    Text(engine.running ? "End Show" : "Go Live")
                }
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(engine.running ? Color.white : Color.black)
                .frame(maxWidth: 260, minHeight: 52)
                .background(engine.running ? Color.white.opacity(0.2) : Color.white, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .padding(.bottom, 6)
            if !engine.connected {
                Text("Connect Spotify first (Home tab).")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Theme.caraGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Theme.accent.opacity(0.25), radius: 18, y: 8)
        .padding(.horizontal, Theme.hPad)
        .animation(.easeInOut(duration: 0.3), value: engine.running)
    }

    private var lastLine: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "quote.opening").foregroundStyle(Theme.accent)
                Text(engine.speaking ? "On air now" : "Last on air")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                if !engine.lineStyle.isEmpty {
                    Text("· " + styleName(engine.lineStyle))
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
            }
            Text(engine.line.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression))
                .font(.system(size: 17, weight: .medium))
                .italic()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, Theme.hPad)
    }

    private func styleName(_ s: String) -> String {
        switch s {
        case "talkover": return "talk-over"
        case "intro": return "over the intro"
        case "silent": return "silent break"
        default: return s
        }
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showLog.toggle() }
            } label: {
                HStack {
                    Text("Activity").font(.title3.weight(.bold)).foregroundStyle(Color.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showLog ? 180 : 0))
                        .foregroundStyle(Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showLog {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(engine.log.reversed().enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color(red: 0.55, green: 0.85, blue: 0.62))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(12)
                }
                .frame(height: 260)
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("Newest at the top. If something goes wrong, a screenshot of this helps.")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, Theme.hPad)
    }

    private func card<C: View>(_ title: String, footer: String?, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.bold)).padding(.horizontal, Theme.hPad + 4)
            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, Theme.hPad)
            if let f = footer {
                Text(f)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, Theme.hPad + 4)
            }
        }
    }

    private func row(_ left: String, _ right: String) -> some View {
        HStack {
            Text(left)
            Spacer()
            Text(right).monospacedDigit().foregroundStyle(Color.secondary)
        }
    }

    private func slider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))%").monospacedDigit().foregroundStyle(Color.secondary)
            }
            Slider(value: value, in: 0...100, step: 1)
        }
    }

    private func styleButton(_ title: String, _ icon: String, _ style: String) -> some View {
        let on = engine.queued == style
        return Button {
            Haptics.tap()
            engine.queue(style)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(on ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(on ? Theme.accent : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private func actionTile(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

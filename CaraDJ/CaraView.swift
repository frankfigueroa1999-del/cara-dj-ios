import SwiftUI

/// Cara's tab: go live, set her mood, line up the next transition, fine-tune her, and read her log.
struct CaraView: View {
    @Environment(Engine.self) private var engine
    @Environment(Router.self) private var router
    @EnvironmentObject private var cfg: Config
    @State private var showLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
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
                        actionTile("With Scratch", "person.2.fill") { engine.testDuo() }
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
                card("How Much She Says", footer: chatFooter) {
                    Picker("How much she says", selection: $cfg.chattiness) {
                        Text("Quick").tag("quick")
                        Text("Normal").tag("normal")
                        Text("Chatty").tag("chatty")
                    }
                    .pickerStyle(.segmented)
                }
                card("How Often She Talks", footer: "A random number of songs in between, every time.") {
                    VStack(spacing: 12) {
                        Stepper(value: $cfg.breakMin, in: 1...10) {
                            row("At least every", "\(cfg.breakMin) song\(cfg.breakMin == 1 ? "" : "s")")
                        }
                        .onChange(of: cfg.breakMin) { _, v in if v > cfg.breakMax { cfg.breakMax = v } }
                        hairline
                        Stepper(value: $cfg.breakMax, in: 1...10) {
                            row("At most every", "\(cfg.breakMax) song\(cfg.breakMax == 1 ? "" : "s")")
                        }
                        .onChange(of: cfg.breakMax) { _, v in if v < cfg.breakMin { cfg.breakMin = v } }
                    }
                }
                card("Pop-Ins", footer: "After a talk-over or intro break she can pop back in a few seconds into the next song, over the music.") {
                    VStack(spacing: 12) {
                        Toggle(isOn: $cfg.popinEnabled) { Text("Pop back in") }
                        hairline
                        Stepper(value: $cfg.popinChance, in: 0...100, step: 5) {
                            row("Chance", "\(cfg.popinChance)%")
                        }
                        .disabled(!cfg.popinEnabled)
                        hairline
                        Stepper(value: $cfg.popinSeconds, in: 5...120, step: 5) {
                            row("Seconds into the song", "about \(cfg.popinSeconds)")
                        }
                        .disabled(!cfg.popinEnabled)
                        hairline
                        Toggle(isOn: $cfg.popinTest) { Text("Test mode (after every break)") }
                            .disabled(!cfg.popinEnabled)
                    }
                    .tint(Theme.accent)
                }
                card("Co-Host", footer: cfg.coHost
                     ? "MC Scratch, Cara's West Coast co-host, joins this share of her breaks for a back-and-forth. His voice is in Settings."
                       + (cfg.coHostSwears ? " He curses when it lands; Cara keeps it clean." : " He keeps it clean.")
                     : "Turn on MC Scratch, Cara's West Coast co-host, for back-and-forth breaks.") {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(isOn: $cfg.coHost) { Text("MC Scratch").foregroundStyle(Color.white) }
                            .tint(Theme.accent)
                        if cfg.coHost {
                            hairline
                            Stepper(value: $cfg.coHostChance, in: 10...100, step: 10) {
                                row("Together", "\(cfg.coHostChance)% of breaks")
                            }
                            hairline
                            Toggle(isOn: $cfg.coHostSwears) { Text("Scratch Can Curse").foregroundStyle(Color.white) }
                                .tint(Theme.accent)
                        }
                    }
                }
                card("Sound", footer: cfg.stationStingers
                     ? "Silent breaks start with a stinger this often. Station stingers are your stingers word for word, with the name of whatever's playing in place of Non-Stop-Pop, read by the station voice (Settings)."
                     : "Silent breaks start with one of your stingers this often.") {
                    VStack(alignment: .leading, spacing: 14) {
                        slider("Cara's volume", value: $cfg.djVolume)
                        slider("Stinger volume", value: $cfg.stingerVolume)
                        hairline
                        Stepper(value: $cfg.stingerChance, in: 0...100, step: 5) {
                            row("Stinger chance", "\(cfg.stingerChance)%")
                        }
                        hairline
                        Toggle(isOn: $cfg.stationStingers) { Text("Station stingers").foregroundStyle(Color.white) }
                            .tint(Theme.accent)
                        if cfg.stationStingers {
                            hairline
                            Button {
                                Haptics.tap()
                                StationStingers.shared.clearAll()
                                Toasts.shared.show("New takes on the way", "bolt.fill")
                            } label: {
                                HStack {
                                    Text("Re-record stingers").foregroundStyle(Color.white)
                                    Spacer()
                                    Image(systemName: "arrow.clockwise").foregroundStyle(Theme.text2)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                card("Her Town", footer: "Local news and weather come from here.") {
                    Button {
                        router.showSettings = true
                    } label: {
                        HStack {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(Color.white)
                            Text(cfg.city).foregroundStyle(Color.white)
                            Spacer()
                            Text("Change").foregroundStyle(Theme.text2)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.text3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                logCard
            }
            .padding(.top, 6)
        }
        .chromeInset()
        .frostedPage()
        .navigationTitle("Cara")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AvatarButton()
            }
        }
    }

    private var chatFooter: String {
        switch cfg.chattiness {
        case "quick": return "Short drop-ins, in and out."
        case "normal": return "A few lines each time."
        default: return "Proper segments: stories, games, news and nonsense. Silent breaks are her longest."
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

    private var hairline: some View {
        Theme.line.frame(height: 0.5)
    }

    // MARK: pieces
    private var hero: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.accent.opacity(engine.running ? 0.55 : 0.3), .clear], center: .center, startRadius: 0, endRadius: 90))
                    .frame(width: 180, height: 180)
                    .blur(radius: 10)
                StationLogo(active: engine.running)
                    .frame(width: 110, height: 76)
            }
            .frame(height: 120)
            .padding(.top, 6)
            VStack(spacing: 5) {
                Text(engine.stationFull.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 24)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: engine.stationFull)
                Text(engine.running ? (engine.speaking ? "Cara's on the mic" : "Cara is live") : "Cara is off air")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.white)
                    .contentTransition(.opacity)
                Text(engine.statusLine)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text2)
            }
            Button {
                Haptics.firm()
                if engine.running { engine.stop() } else { engine.start() }
            } label: {
                PillLabel(title: engine.running ? "End Show" : "Go Live",
                          icon: engine.running ? "stop.fill" : "dot.radiowaves.left.and.right",
                          primary: !engine.running, height: 52)
                    .frame(maxWidth: 260)
            }
            .buttonStyle(PressableStyle())
            if !engine.connected {
                Text("Connect Spotify first (Home tab).")
                    .font(.footnote)
                    .foregroundStyle(Theme.text2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .glass(28, tint: 0.05)
        .padding(.horizontal, Theme.hPad)
        .animation(.easeInOut(duration: 0.35), value: engine.running)
    }

    private var lastLine: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "quote.opening").foregroundStyle(Theme.accent)
                Text(engine.speaking ? "On air now" : "Last on air")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.text2)
                if !engine.lineStyle.isEmpty {
                    Text("· " + styleName(engine.lineStyle))
                        .font(.footnote)
                        .foregroundStyle(Theme.text2)
                }
            }
            Text(engine.line.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression))
                .font(.system(size: 17, weight: .medium))
                .italic()
                .foregroundStyle(Color.white)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(22)
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
                    Text("Activity").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.white)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showLog ? 180 : 0))
                        .foregroundStyle(Theme.text2)
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
                                .foregroundStyle(Color(red: 0.6, green: 0.88, blue: 0.68))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(12)
                }
                .frame(height: 260)
                .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("Newest at the top. If something goes wrong, a screenshot of this helps.")
                    .font(.caption)
                    .foregroundStyle(Theme.text2)
            }
        }
        .padding(18)
        .glass(22)
        .padding(.horizontal, Theme.hPad)
    }

    private func card<C: View>(_ title: String, footer: String?, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, Theme.hPad + 4)
            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(20)
                .padding(.horizontal, Theme.hPad)
            if let f = footer {
                Text(f)
                    .font(.footnote)
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, Theme.hPad + 4)
            }
        }
    }

    private func row(_ left: String, _ right: String) -> some View {
        HStack {
            Text(left).foregroundStyle(Color.white)
            Spacer()
            Text(right).monospacedDigit().foregroundStyle(Theme.text2)
        }
    }

    private func slider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).foregroundStyle(Color.white)
                Spacer()
                Text("\(Int(value.wrappedValue))%").monospacedDigit().foregroundStyle(Theme.text2)
            }
            Slider(value: value, in: 0...100, step: 1)
                .tint(Color.white)
        }
    }

    private func styleButton(_ title: String, _ icon: String, _ style: String) -> some View {
        let on = engine.queued == style
        return Button {
            Haptics.tap()
            engine.queue(style)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(on ? Color.black : Color.white)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(on ? Color.white : Color.white.opacity(0.08))
            }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(on ? 0 : 0.1), lineWidth: 0.7))
            .animation(.easeInOut(duration: 0.2), value: on)
        }
        .buttonStyle(PressableStyle())
    }

    private func actionTile(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.7))
        }
        .buttonStyle(PressableStyle())
    }
}

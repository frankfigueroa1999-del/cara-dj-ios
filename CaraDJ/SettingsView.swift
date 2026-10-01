import SwiftUI

/// Keys, Spotify connection and her town, on the same frosted glass as the rest of the app.
struct SettingsView: View {
    @Environment(Engine.self) private var engine
    @Environment(Library.self) private var library
    @EnvironmentObject private var cfg: Config
    @Environment(\.dismiss) private var dismiss
    @State private var cityText = ""
    @State private var confirmLogout = false

    private let rowGlass = Color.white.opacity(0.07)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Artwork(library.me?.image, px: 150, circle: true)
                            .frame(width: 54, height: 54)
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.7))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(library.me?.name ?? (engine.loggedIn ? "Spotify" : "Not connected"))
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(Color.white)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(engine.connected ? NowPlayingView.green : Color.white.opacity(0.35))
                                    .frame(width: 7, height: 7)
                                Text(engine.loggedIn ? (engine.connected ? "Connected to Spotify" : "Logged in") : "Connect to use the player")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.text2)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    if engine.loggedIn {
                        if library.needsReconnect {
                            Button("Reconnect Spotify (unlocks your library)") {
                                dismiss()
                                Task { await engine.connect(forceLogin: true) }
                            }
                            .foregroundStyle(Color.white)
                        }
                        Button("Log Out of Spotify", role: .destructive) { confirmLogout = true }
                    } else {
                        Button("Connect Spotify") {
                            dismiss()
                            Task { await engine.connect(forceLogin: true) }
                        }
                        .foregroundStyle(Color.white)
                        .disabled(cfg.clientID.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .listRowBackground(rowGlass)

                Section {
                    TextField("Client ID", text: $cfg.clientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                } header: {
                    Text("Spotify App")
                } footer: {
                    Text("From developer.spotify.com. Its Redirect URI must be caradj://callback, and everyone using it has to be added under User Management (5 people at most).")
                }
                .listRowBackground(rowGlass)

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
                .listRowBackground(rowGlass)

                Section {
                    SecureField("API key", text: $cfg.geminiKey)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Her Words (Gemini)")
                } footer: {
                    Text("Without a key she still talks, using simpler built-in lines.")
                }
                .listRowBackground(rowGlass)

                Section {
                    TextField("Yakima, Washington", text: $cityText)
                        .onSubmit { Task { await engine.changeCity(cityText) } }
                } header: {
                    Text("Your Town")
                } footer: {
                    Text("Town, State. Used for local news and weather.")
                }
                .listRowBackground(rowGlass)

                Section {
                    Button("Show the Welcome Setup Again") {
                        dismiss()
                        let c = cfg
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                            withAnimation(.easeInOut(duration: 0.5)) { c.welcomed = false }
                        }
                    }
                    .foregroundStyle(Color.white)
                } footer: {
                    Text("Cara DJ 2.0. Music plays through the Spotify app; Cara talks over it from here.")
                }
                .listRowBackground(rowGlass)
            }
            .tint(Color.white)
            .frostedPage()
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

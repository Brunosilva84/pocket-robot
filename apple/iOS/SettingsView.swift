import SwiftUI

/// Hub URL and token (sent on to the watch), a connection test, and starting a new conversation.
struct SettingsView: View {
    let app: AppModel
    let relay: WatchRelay

    private enum Check: Equatable {
        case idle, running, ok, failed(String)
    }

    @State private var url = ""
    @State private var token = ""
    @State private var saved = HubSettings.current
    @State private var check = Check.idle
    @State private var confirmNew = false
    @State private var newResult: String?

    private var edited: HubSettings {
        HubSettings(url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                    token: token.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        Form {
            Section {
                TextField("http://your-mac.local:8787", text: $url)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Hub")
            } footer: {
                Text("`scripts/configure` on your Mac prints the address; the token is in ~/.pocket-robot/config.json. Away from home, use the Mac's Tailscale name, like http://my-mac.tail1234.ts.net:8787.")
            }

            Section {
                Button(action: testConnection) {
                    HStack {
                        Text("Test connection")
                        Spacer()
                        checkBadge
                    }
                }
                .disabled(check == .running)
            }

            Section {
                Button("New conversation", role: .destructive) { confirmNew = true }
                    .confirmationDialog("Start a new conversation?", isPresented: $confirmNew, titleVisibility: .visible) {
                        Button("New conversation", role: .destructive, action: newConversation)
                    } message: {
                        Text("Claude Code forgets what you talked about so far.")
                    }
            } footer: {
                if let newResult { Text(newResult) }
            }

            Section {
                LabeledContent("Apple Watch", value: relay.status.label)
            } footer: {
                Text("Saved settings are sent to the watch. When the watch can't reach your Mac, it talks through this iPhone.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(edited == saved || edited.url.isEmpty || edited.token.isEmpty)
            }
        }
        .onAppear(perform: load)
        .onChange(of: edited) { check = .idle }
    }

    @ViewBuilder private var checkBadge: some View {
        switch check {
        case .idle: EmptyView()
        case .running: ProgressView()
        case .ok:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let why):
            Label(why, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func load() {
        saved = .current
        url = saved.url
        token = saved.token
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "demo") { // screenshots: no real address
            url = "http://my-mac.local:8787"
            saved = edited
        }
        #endif
    }

    private func save() {
        edited.save()
        saved = .current
        relay.push(saved)
        app.settingsChanged()
    }

    /// Tests what's in the fields, saved or not.
    private func testConnection() {
        check = .running
        let client = HubClient(edited)
        Task {
            check = switch await client.health() {
            case .ok: .ok
            case .unauthorized: .failed("Token rejected")
            case .unreachable: .failed("Can't reach the hub")
            }
        }
    }

    private func newConversation() {
        newResult = nil
        Task {
            do {
                try await HubClient().newConversation()
                app.forgetConversation()
                newResult = "The next thing you say starts a new conversation."
            } catch {
                newResult = "Couldn't reach the hub. Try again when your Mac is online."
            }
        }
    }
}

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Auto-connect on launch", isOn: $environment.settings.autoConnect)
                    Toggle("Kill Switch", isOn: $environment.settings.killSwitch)
                } header: {
                    Label("Connection", systemImage: "wifi")
                } footer: {
                    Text("Kill Switch blocks all internet traffic when VPN disconnects unexpectedly.")
                }

                Section {
                    Picker("DNS Server", selection: $environment.settings.selectedDNS) {
                        ForEach(DNSOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                } header: {
                    Label("DNS", systemImage: "network")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(buildNumber)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Backend")
                        Spacer()
                        Text("api.yeats.uz")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("About", systemImage: "info.circle")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppEnvironment.preview())
}

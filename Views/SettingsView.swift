import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: ControlViewModel
    @State private var showRestartHint = false

    var body: some View {
        List {
            NavigationLink {
                languagePickerView
            } label: {
                HStack {
                    Text(NSLocalizedString("title_language", comment: "Language"))
                    Spacer()
                    Text(languageLabel(vm.appLanguage))
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(NSLocalizedString("label_debug", comment: "Debug"), isOn: Binding(
                get: { vm.debugEnabled },
                set: { vm.setDebugEnabled($0) }
            ))

            NavigationLink {
                NumericAdjustView(
                    title: NSLocalizedString("label_random_shuffle_time", comment: "Random shuffle time"),
                    value: vm.randomRunInitialIntervalSeconds,
                    range: 10...120,
                    step: 5
                ) {
                    vm.setRandomRunInitialInterval(seconds: $0)
                }
            } label: {
                HStack {
                    Text(NSLocalizedString("label_random_shuffle_time", comment: "Random shuffle time"))
                    Spacer()
                    Text("\(vm.randomRunInitialIntervalSeconds) s")
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                NumericAdjustView(
                    title: NSLocalizedString("label_machine_start_delay", comment: "Machine start delay"),
                    value: vm.randomRunStartDelaySeconds,
                    range: 5...15,
                    step: 1
                ) {
                    vm.setRandomRunStartDelay(seconds: $0)
                }
            } label: {
                HStack {
                    Text(NSLocalizedString("label_machine_start_delay", comment: "Machine start delay"))
                    Spacer()
                    Text("\(vm.randomRunStartDelaySeconds) s")
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                NumericAdjustView(
                    title: NSLocalizedString("label_heartbeat_interval", comment: "Heartbeat interval"),
                    value: vm.heartbeatIntervalSeconds,
                    range: 0...30,
                    step: 1
                ) {
                    vm.setHeartbeatInterval(seconds: $0)
                }
            } label: {
                HStack {
                    Text(NSLocalizedString("label_heartbeat_interval", comment: "Heartbeat interval"))
                    Spacer()
                    Text("\(vm.heartbeatIntervalSeconds) s")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(NSLocalizedString("title_settings", comment: "Settings"))
    }

    private var languagePickerView: some View {
        List {
            ForEach(ControlViewModel.AppLanguage.allCases) { language in
                Button {
                    vm.setAppLanguage(language)
                    showRestartHint = true
                } label: {
                    HStack {
                        Text(languageLabel(language))
                        Spacer()
                        if vm.appLanguage == language {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(NSLocalizedString("title_language", comment: "Language"))
        .alert(NSLocalizedString("title_language_applied", comment: "Language changed title"), isPresented: $showRestartHint) {
            Button(NSLocalizedString("action_ok", comment: "OK"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("message_restart_required", comment: "Restart required message"))
        }
    }

    private func languageLabel(_ language: ControlViewModel.AppLanguage) -> String {
        switch language {
        case .system:
            return NSLocalizedString("label_system", comment: "System language")
        case .english:
            return NSLocalizedString("label_english", comment: "English language")
        case .chineseSimplified:
            return NSLocalizedString("label_chinese_simplified", comment: "Simplified Chinese language")
        }
    }
}

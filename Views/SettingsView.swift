import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: ControlViewModel

    var body: some View {
        List {
            Toggle("Debug", isOn: Binding(
                get: { vm.debugEnabled },
                set: { vm.setDebugEnabled($0) }
            ))

            NavigationLink {
                NumericAdjustView(
                    title: "Random Shuffle Time",
                    value: vm.randomRunInitialIntervalSeconds,
                    range: 10...120,
                    step: 5
                ) {
                    vm.setRandomRunInitialInterval(seconds: $0)
                }
            } label: {
                HStack {
                    Text("Random Shuffle Time")
                    Spacer()
                    Text("\(vm.randomRunInitialIntervalSeconds)s")
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                NumericAdjustView(
                    title: "Machine Start Delay",
                    value: vm.randomRunStartDelaySeconds,
                    range: 5...15,
                    step: 1
                ) {
                    vm.setRandomRunStartDelay(seconds: $0)
                }
            } label: {
                HStack {
                    Text("Machine Start Delay")
                    Spacer()
                    Text("\(vm.randomRunStartDelaySeconds)s")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
    }
}

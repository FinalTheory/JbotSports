import SwiftUI

struct Page2View: View {
    @ObservedObject var vm: ControlViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("S+") { vm.incOverallSpeed() }
                    .buttonStyle(.bordered)
                VStack(spacing: 2) {
                    Text("U:\(vm.topSpeed)")
                    Text("D:\(vm.bottomSpeed)")
                }
                .font(.headline)
                .frame(minWidth: 44)
                Button("S-") { vm.decOverallSpeed() }
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button("H+") { vm.incHeight() }
                    .buttonStyle(.bordered)
                VStack(spacing: 2) {
                    Text("H:\(vm.shortAngle)")
                    Text("Spin:\(vm.spinValue)")
                        .font(.footnote)
                }
                .font(.headline)
                .frame(minWidth: 52)
                Button("H-") { vm.decHeight() }
                    .buttonStyle(.bordered)
            }

            Slider(
                value: Binding(
                    get: { Double(vm.spinValue) },
                    set: { vm.applySpin(diff: Int($0.rounded())) }
                ),
                in: -50...50,
                step: 5
            )
        }
        .padding(.horizontal, 6)
    }
}

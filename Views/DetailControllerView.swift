import SwiftUI

struct DetailControllerView: View {
    @ObservedObject var vm: ControlViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("S-") { vm.decOverallSpeed() }
                    .buttonStyle(.bordered)
                VStack(spacing: 2) {
                    Text("U:\(vm.topSpeed)")
                    Text("D:\(vm.bottomSpeed)")
                }
                .font(.headline)
                .frame(minWidth: 44)
                Button("S+") { vm.incOverallSpeed() }
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button("H-") { vm.decHeight() }
                    .buttonStyle(.bordered)
                VStack(spacing: 2) {
                    Text("H:\(vm.shortAngle)")
                    Text("S:\(vm.spinValue)")
                }
                .font(.headline)
                .frame(minWidth: 52)
                Button("H+") { vm.incHeight() }
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button("SPIN-") { vm.applySpin(diff: vm.spinValue - 5) }
                    .buttonStyle(.bordered)

                Text("\(vm.spinValue)")
                    .font(.headline)
                    .frame(minWidth: 44)

                Button("SPIN+") { vm.applySpin(diff: vm.spinValue + 5) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 6)
    }
}

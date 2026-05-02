import SwiftUI

struct DetailControllerView: View {
    @ObservedObject var vm: ControlViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(NSLocalizedString("label_speed_minus", comment: "Speed minus")) { vm.decOverallSpeed() }
                    .buttonStyle(.bordered)
                VStack(spacing: 2) {
                    Text("\(NSLocalizedString("label_upper_wheel_short", comment: "Upper wheel short")):\(vm.topSpeed)")
                    Text("\(NSLocalizedString("label_lower_wheel_short", comment: "Lower wheel short")):\(vm.bottomSpeed)")
                }
                .font(.headline)
                .frame(minWidth: 44)
                Button(NSLocalizedString("label_speed_plus", comment: "Speed plus")) { vm.incOverallSpeed() }
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button(NSLocalizedString("label_height_minus", comment: "Height minus")) { vm.decHeight() }
                    .buttonStyle(.bordered)
                VStack(spacing: 2) {
                    Text("\(NSLocalizedString("label_height_short", comment: "Height short")):\(vm.shortAngle)")
                    Text("\(NSLocalizedString("label_spin_short", comment: "Spin short")):\(vm.spinValue)")
                }
                .font(.headline)
                .frame(minWidth: 52)
                Button(NSLocalizedString("label_height_plus", comment: "Height plus")) { vm.incHeight() }
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button(NSLocalizedString("label_spin_minus", comment: "Spin minus")) { vm.applySpin(diff: vm.spinValue - 5) }
                    .buttonStyle(.bordered)

                Text("\(vm.spinValue)")
                    .font(.headline)
                    .frame(minWidth: 44)

                Button(NSLocalizedString("label_spin_plus", comment: "Spin plus")) { vm.applySpin(diff: vm.spinValue + 5) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 6)
    }

}

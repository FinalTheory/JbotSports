import SwiftUI

struct RandomShuffleControllerView: View {
    @ObservedObject var vm: ControlViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                iconButton(systemName: "play.fill", color: .green) { vm.startRandomRun() }
                iconButton(systemName: "stop.fill", color: .red) { vm.stop() }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                Button(NSLocalizedString("label_time_minus", comment: "Time minus")) { vm.decRandomRunInterval() }
                    .buttonStyle(.bordered)
                    .frame(maxHeight: 30)

                Text("\(vm.randomRunInterval)")
                    .font(.headline)
                    .frame(minWidth: 36)

                Button(NSLocalizedString("label_time_plus", comment: "Time plus")) { vm.incRandomRunInterval() }
                    .buttonStyle(.bordered)
                    .frame(maxHeight: 30)
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                Button("←") { vm.fineTuneLeft() }
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.gray.opacity(0.35))
                    )
                    .buttonStyle(.plain)

                Button("→") { vm.fineTuneRight() }
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.gray.opacity(0.35))
                    )
                    .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(
            NSLocalizedString("title_cannot_start", comment: "Cannot start"),
            isPresented: Binding(
                get: { vm.randomRunAlertMessage != nil },
                set: { newValue in
                    if !newValue {
                        vm.randomRunAlertMessage = nil
                    }
                }
            )
        ) {
            Button(NSLocalizedString("action_ok", comment: "OK"), role: .cancel) {
                vm.randomRunAlertMessage = nil
            }
        } message: {
            Text(vm.randomRunAlertMessage ?? "")
        }
    }

    private func iconButton(systemName: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 14)
                .fill(color)
                .overlay {
                    Image(systemName: systemName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

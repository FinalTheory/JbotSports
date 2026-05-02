import SwiftUI

struct MainControllerView: View {
    @ObservedObject var vm: ControlViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                iconButton(systemName: "play.fill", color: .green) { vm.start() }
                iconButton(systemName: "stop.fill", color: .red) { vm.stop() }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                Button(NSLocalizedString("label_freq_minus", comment: "Frequency minus")) { vm.decFrequency() }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 60)
                Text("\(vm.frequency)")
                    .font(.headline)
                    .frame(minWidth: 28)
                Button(NSLocalizedString("label_freq_plus", comment: "Frequency plus")) { vm.incFrequency() }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 60)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

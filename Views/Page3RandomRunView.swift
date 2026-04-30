import SwiftUI

struct Page3RandomRunView: View {
    @ObservedObject var vm: ControlViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                iconButton(systemName: "play.fill", color: .green) { vm.startRandomRun() }
                iconButton(systemName: "stop.fill", color: .red) { vm.stop() }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                Button("TIME-") { vm.decRandomRunInterval() }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 60)

                Text("\(vm.randomRunInterval)")
                    .font(.headline)
                    .frame(minWidth: 36)

                Button("TIME+") { vm.incRandomRunInterval() }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 60)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(
            "Cannot Start",
            isPresented: Binding(
                get: { vm.randomRunAlertMessage != nil },
                set: { newValue in
                    if !newValue {
                        vm.randomRunAlertMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
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

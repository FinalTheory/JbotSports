import SwiftUI

struct Page3View: View {
    @ObservedObject var vm: ControlViewModel
    @State private var editingPreset: Preset?

    var body: some View {
        List {
            ForEach(vm.presets) { p in
                HStack(spacing: 8) {
                    Button {
                        vm.selectPreset(p)
                    } label: {
                        HStack {
                            Text(p.name)
                                .lineLimit(1)
                            Spacer()
                            Text(modeTag(for: p))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(vm.activePresetID == p.id ? Color.green.opacity(0.25) : .clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button {
                        editingPreset = p
                    } label: {
                        Image(systemName: "pencil")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .padding(.horizontal, 2)
                }
                .listRowInsets(.init(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            }
        }
        .sheet(item: $editingPreset) { preset in
            NavigationStack {
                PresetEditorView(preset: preset) { updated in
                    vm.updatePreset(updated)
                }
            }
        }
    }

    private func modeTag(for preset: Preset) -> String {
        let base = preset.isRandom ? "R" : "S"
        return preset.shuffle ? "\(base)*" : base
    }
}

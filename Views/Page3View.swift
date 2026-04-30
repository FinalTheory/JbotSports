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
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(vm.activePresetID == p.id ? Color.green.opacity(0.25) : Color.clear)

                            HStack {
                                Text(p.name)
                                    .lineLimit(1)
                                Spacer()
                                Text(p.isRandom ? "R" : "S")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
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
}

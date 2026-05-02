import SwiftUI

struct PresetView: View {
    @ObservedObject var vm: ControlViewModel
    @State private var editingPreset: Preset?
    @State private var creatingPreset = false
    @State private var showSettings = false

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
                            .foregroundStyle(p.shuffle ? .orange : .primary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .padding(.horizontal, 2)
                }
                .listRowInsets(.init(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                Button {
                    creatingPreset = true
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                        .frame(width: 34, height: 26)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 26)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .listRowInsets(.init(top: 2, leading: 0, bottom: 2, trailing: 0))
            .listRowBackground(Color.clear)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView(vm: vm)
            }
        }
        .sheet(item: $editingPreset) { preset in
            NavigationStack {
                PresetEditorView(
                    preset: preset,
                    onSave: { updated in
                        vm.updatePreset(updated)
                    },
                    onDelete: {
                        _ = vm.deletePreset(id: preset.id)
                    },
                    canDelete: vm.presets.count > 1
                )
            }
        }
        .sheet(isPresented: $creatingPreset) {
            NavigationStack {
                PresetEditorView(
                    preset: newPresetTemplate(),
                    onSave: { created in
                        vm.addPreset(created)
                    }
                )
            }
        }
    }

    private func modeTag(for preset: Preset) -> String {
        let base = preset.isRandom ? "R" : "S"
        return preset.shuffle ? "\(base)*" : base
    }

    private func newPresetTemplate() -> Preset {
        Preset(
            name: "New Preset",
            order: [25],
            isRandom: true,
            shuffle: false,
            interval: 0,
            topSpeed: vm.topSpeed,
            bottomSpeed: vm.bottomSpeed,
            frequency: vm.frequency,
            shortAngle: vm.shortAngle
        )
    }
}

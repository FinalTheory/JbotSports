import SwiftUI

struct PresetEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var orderText: String
    @State private var isRandom: Bool
    @State private var topSpeedValue: Int
    @State private var bottomSpeedValue: Int
    @State private var frequencyValue: Int
    @State private var shortAngleValue: Int
    @State private var error: String = ""

    let preset: Preset
    let onSave: (Preset) -> Void

    init(preset: Preset, onSave: @escaping (Preset) -> Void) {
        self.preset = preset
        self.onSave = onSave
        _name = State(initialValue: preset.name)
        _orderText = State(initialValue: preset.orderText)
        _isRandom = State(initialValue: preset.isRandom)
        _topSpeedValue = State(initialValue: preset.topSpeed)
        _bottomSpeedValue = State(initialValue: preset.bottomSpeed)
        _frequencyValue = State(initialValue: preset.frequency)
        _shortAngleValue = State(initialValue: preset.shortAngle)
    }

    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("Order: 1 2 3", text: $orderText)

            NavigationLink {
                NumericAdjustView(title: "Top Speed", value: topSpeedValue, range: 0...100, step: 5) {
                    topSpeedValue = $0
                }
            } label: {
                numericRow(title: "Top Speed", value: topSpeedValue)
            }

            NavigationLink {
                NumericAdjustView(title: "Bottom Speed", value: bottomSpeedValue, range: 0...100, step: 5) {
                    bottomSpeedValue = $0
                }
            } label: {
                numericRow(title: "Bottom Speed", value: bottomSpeedValue)
            }

            NavigationLink {
                NumericAdjustView(title: "Frequency", value: frequencyValue, range: 1...9) {
                    frequencyValue = $0
                }
            } label: {
                numericRow(title: "Frequency", value: frequencyValue)
            }

            NavigationLink {
                NumericAdjustView(title: "Height", value: shortAngleValue, range: 6...60) {
                    shortAngleValue = $0
                }
            } label: {
                numericRow(title: "Height", value: shortAngleValue)
            }

            Toggle("Random", isOn: $isRandom)

            if !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                do {
                    let parsed = try parseOrder(orderText)
                    let topSpeed = try validate(topSpeedValue, in: 0...100, name: "Top Speed")
                    let bottomSpeed = try validate(bottomSpeedValue, in: 0...100, name: "Bottom Speed")
                    let frequency = try validate(frequencyValue, in: 1...9, name: "Frequency")
                    let shortAngle = try validate(shortAngleValue, in: 6...60, name: "Short Angle")
                    guard abs(topSpeed - bottomSpeed) <= 50 else {
                        throw NSError(
                            domain: "Preset",
                            code: 6,
                            userInfo: [NSLocalizedDescriptionKey: "Top/Bottom difference must be within 50"]
                        )
                    }
                    var p = preset
                    p.name = name.isEmpty ? preset.name : name
                    p.order = parsed
                    p.isRandom = isRandom
                    p.topSpeed = topSpeed
                    p.bottomSpeed = bottomSpeed
                    p.frequency = frequency
                    p.shortAngle = shortAngle
                    onSave(p)
                    dismiss()
                } catch {
                    self.error = error.localizedDescription
                }
            } label: {
                Text("Save")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .listRowBackground(Color.clear)
        }
        .navigationTitle("Edit Preset")
    }

    private func numericRow(title: String, value: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(value)")
                .font(.headline)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func parseOrder(_ text: String) throws -> [UInt8] {
        let tokens = text
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)

        guard !tokens.isEmpty else {
            throw NSError(domain: "Preset", code: 1, userInfo: [NSLocalizedDescriptionKey: "Order cannot be empty"])
        }

        var out: [UInt8] = []
        for tok in tokens {
            guard let n = Int(tok) else {
                throw NSError(domain: "Preset", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid token: \(tok)"])
            }
            guard (1...28).contains(n) else {
                throw NSError(domain: "Preset", code: 3, userInfo: [NSLocalizedDescriptionKey: "Out of range: \(n), must be 1...28"])
            }
            out.append(UInt8(n))
        }
        return out
    }

    private func validate(_ v: Int, in range: ClosedRange<Int>, name: String) throws -> Int {
        guard range.contains(v) else {
            throw NSError(
                domain: "Preset",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "\(name) out of range: \(v), must be \(range.lowerBound)...\(range.upperBound)"]
            )
        }
        return v
    }
}

private struct NumericAdjustView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let range: ClosedRange<Int>
    let step: Int
    let onSave: (Int) -> Void

    @State private var value: Int
    @FocusState private var crownFocused: Bool

    init(title: String, value: Int, range: ClosedRange<Int>, step: Int = 1, onSave: @escaping (Int) -> Void) {
        self.title = title
        self.range = range
        self.step = step
        self.onSave = onSave
        _value = State(initialValue: value)
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.headline)
            Text("\(value)")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .focusable()
                .focused($crownFocused)
                .digitalCrownRotation(
                    Binding(
                        get: { Double(value) },
                        set: { value = snapped(Int($0.rounded())) }
                    ),
                    from: Double(range.lowerBound),
                    through: Double(range.upperBound),
                    by: Double(step),
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )

            HStack(spacing: 8) {
                Button("-") {
                    value = snapped(value - step)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("+") {
                    value = snapped(value + step)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }

            Button("Save") {
                onSave(value)
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(6)
        .onAppear {
            value = snapped(value)
            crownFocused = true
        }
        .navigationTitle(title)
    }

    private func snapped(_ raw: Int) -> Int {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        let offset = clamped - range.lowerBound
        let snappedOffset = Int((Double(offset) / Double(step)).rounded()) * step
        return min(max(range.lowerBound + snappedOffset, range.lowerBound), range.upperBound)
    }
}

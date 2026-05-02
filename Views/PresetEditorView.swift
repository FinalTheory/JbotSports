import SwiftUI
import WatchKit

struct PresetEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var orderText: String
    @State private var isRandom: Bool
    @State private var shuffle: Bool
    @State private var intervalValue: Int
    @State private var topSpeedValue: Int
    @State private var bottomSpeedValue: Int
    @State private var frequencyValue: Int
    @State private var shortAngleValue: Int
    @State private var error: String = ""
    @State private var showDeleteConfirm = false

    let preset: Preset
    let onSave: (Preset) -> Void
    let onDelete: (() -> Void)?
    let canDelete: Bool

    init(
        preset: Preset,
        onSave: @escaping (Preset) -> Void,
        onDelete: (() -> Void)? = nil,
        canDelete: Bool = false
    ) {
        self.preset = preset
        self.onSave = onSave
        self.onDelete = onDelete
        self.canDelete = canDelete
        _name = State(initialValue: preset.name)
        _orderText = State(initialValue: preset.orderText)
        _isRandom = State(initialValue: preset.isRandom)
        _shuffle = State(initialValue: preset.shuffle)
        _intervalValue = State(initialValue: preset.interval)
        _topSpeedValue = State(initialValue: preset.topSpeed)
        _bottomSpeedValue = State(initialValue: preset.bottomSpeed)
        _frequencyValue = State(initialValue: preset.frequency)
        _shortAngleValue = State(initialValue: preset.shortAngle)
    }

    var body: some View {
        Form {
            TextField(NSLocalizedString("field_name", comment: "Name"), text: $name)
            NavigationLink {
                OrderKeypadView(value: orderText) {
                    orderText = $0
                }
            } label: {
                HStack {
                    Text(NSLocalizedString("field_order", comment: "Order"))
                    Spacer()
                    Text(orderPreview)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                NumericAdjustView(title: NSLocalizedString("field_top_speed", comment: "Top speed"), value: topSpeedValue, range: 30...100, step: 5) {
                    topSpeedValue = $0
                }
            } label: {
                numericRow(title: NSLocalizedString("field_top_speed", comment: "Top speed"), value: topSpeedValue)
            }

            NavigationLink {
                NumericAdjustView(title: NSLocalizedString("field_bottom_speed", comment: "Bottom speed"), value: bottomSpeedValue, range: 30...100, step: 5) {
                    bottomSpeedValue = $0
                }
            } label: {
                numericRow(title: NSLocalizedString("field_bottom_speed", comment: "Bottom speed"), value: bottomSpeedValue)
            }

            NavigationLink {
                NumericAdjustView(title: NSLocalizedString("field_frequency", comment: "Frequency"), value: frequencyValue, range: 1...9) {
                    frequencyValue = $0
                }
            } label: {
                numericRow(title: NSLocalizedString("field_frequency", comment: "Frequency"), value: frequencyValue)
            }

            NavigationLink {
                NumericAdjustView(title: NSLocalizedString("field_height", comment: "Height"), value: shortAngleValue, range: 12...60) {
                    shortAngleValue = $0
                }
            } label: {
                numericRow(title: NSLocalizedString("field_height", comment: "Height"), value: shortAngleValue)
            }

            Toggle(NSLocalizedString("field_random", comment: "Random"), isOn: $isRandom)
            Toggle(NSLocalizedString("field_shuffle", comment: "Shuffle"), isOn: $shuffle)

            NavigationLink {
                NumericAdjustView(title: NSLocalizedString("field_interval", comment: "Interval"), value: intervalValue, range: 0...120, step: 5) {
                    intervalValue = $0
                }
            } label: {
                numericRow(title: NSLocalizedString("field_interval", comment: "Interval"), value: intervalValue)
            }

            if !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                do {
                    let parsed = try parseOrder(orderText)
                    let topSpeed = try validate(topSpeedValue, in: 30...100, name: "Top Speed")
                    let bottomSpeed = try validate(bottomSpeedValue, in: 30...100, name: "Bottom Speed")
                    let frequency = try validate(frequencyValue, in: 1...9, name: "Frequency")
                    let shortAngle = try validate(shortAngleValue, in: 12...60, name: "Short Angle")
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
                    p.shuffle = shuffle
                    p.interval = intervalValue
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
                Text(NSLocalizedString("action_save", comment: "Save"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .listRowBackground(Color.clear)

            if let onDelete {
                Button {
                    showDeleteConfirm = true
                }
                label: {
                    Text(NSLocalizedString("action_delete", comment: "Delete"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.red.opacity(0.45))
                .foregroundStyle(.red)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .listRowBackground(Color.clear)
                .disabled(!canDelete)
            }
        }
        .navigationTitle(NSLocalizedString("title_edit_preset", comment: "Edit preset"))
        .alert(NSLocalizedString("confirm_delete_preset", comment: "Delete preset confirm"), isPresented: $showDeleteConfirm) {
            Button(NSLocalizedString("action_cancel", comment: "Cancel"), role: .cancel) {}
            Button(NSLocalizedString("action_delete", comment: "Delete"), role: .destructive) {
                onDelete?()
                dismiss()
            }
        } message: {
            Text(NSLocalizedString("message_delete_irreversible", comment: "Delete irreversible message"))
        }
    }

    private var orderPreview: String {
        orderText.isEmpty ? NSLocalizedString("hint_tap_to_edit", comment: "Tap to edit") : orderText
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
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        guard !tokens.isEmpty else {
            throw NSError(domain: "Preset", code: 1, userInfo: [NSLocalizedDescriptionKey: "Order cannot be empty"])
        }
        guard tokens.count <= 28 else {
            throw NSError(domain: "Preset", code: 2, userInfo: [NSLocalizedDescriptionKey: "Order count must be <= 28"])
        }

        let out = tokens
            .compactMap { Int($0) }
            .filter { (1...28).contains($0) }
            .map(UInt8.init)

        guard !out.isEmpty else {
            throw NSError(domain: "Preset", code: 3, userInfo: [NSLocalizedDescriptionKey: "Order cannot be empty"])
        }
        return Array(out.prefix(28))
    }

    private func validate(_ v: Int, in range: ClosedRange<Int>, name: String) throws -> Int {
        guard range.contains(v) else {
            let message = "\(name) out of range: \(v), must be \(range.lowerBound)...\(range.upperBound)"
            throw NSError(
                domain: "Preset",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        return v
    }
}

private struct OrderKeypadView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String) -> Void
    @State private var values: [Int]
    @State private var candidate: Int
    @FocusState private var crownFocused: Bool

    init(value: String, onSave: @escaping (String) -> Void) {
        self.onSave = onSave
        let parsed = value
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .compactMap { Int($0) }
            .filter { (1...28).contains($0) }
        _values = State(initialValue: Array(parsed.prefix(28)))
        _candidate = State(initialValue: parsed.last ?? 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(orderText.isEmpty ? NSLocalizedString("hint_no_points", comment: "No points") : orderText)
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    Color.clear
                        .frame(height: 1)
                        .id("order-bottom")
                }
                .onAppear {
                    proxy.scrollTo("order-bottom", anchor: .bottom)
                }
                .onChange(of: orderText) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("order-bottom", anchor: .bottom)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 68)

            HStack(spacing: 4) {
                Text("\(candidate) ")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.green)
                Text(positionName(candidate))
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .focusable()
                    .focused($crownFocused)
                    .digitalCrownRotation(
                        Binding(
                            get: { Double(candidate) },
                            set: { candidate = Int($0.rounded()) }
                        ),
                        from: 1,
                        through: 28,
                        by: 1,
                        sensitivity: .medium,
                        isContinuous: false,
                        isHapticFeedbackEnabled: true
                    )
            }
            .frame(maxWidth: .infinity, minHeight: 34)

            HStack(spacing: 8) {
                Button(NSLocalizedString("action_add", comment: "Add")) {
                    guard values.count < 28 else { return }
                    values.append(candidate)
                    haptic()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button(NSLocalizedString("action_del", comment: "Delete last")) {
                    if !values.isEmpty {
                        _ = values.removeLast()
                        haptic()
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button(NSLocalizedString("action_save", comment: "Save")) {
                    haptic()
                    onSave(orderText)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(6)
        .onAppear {
            crownFocused = true
        }
        .navigationTitle(NSLocalizedString("title_order", comment: "Order title"))
    }

    private var orderText: String {
        values.prefix(28).map(String.init).joined(separator: " ")
    }

    private func positionName(_ value: Int) -> String {
        guard (1...28).contains(value) else { return NSLocalizedString("position_unknown", comment: "Unknown position") }
        let rows = [
            NSLocalizedString("position_row_front", comment: "Front row"),
            NSLocalizedString("position_row_mid", comment: "Middle row"),
            NSLocalizedString("position_row_rear", comment: "Rear row"),
            NSLocalizedString("position_row_baseline", comment: "Baseline row")
        ]
        let lanes = [
            NSLocalizedString("position_lane_l3", comment: "Left 3"),
            NSLocalizedString("position_lane_l2", comment: "Left 2"),
            NSLocalizedString("position_lane_l1", comment: "Left 1"),
            NSLocalizedString("position_lane_center", comment: "Center"),
            NSLocalizedString("position_lane_r1", comment: "Right 1"),
            NSLocalizedString("position_lane_r2", comment: "Right 2"),
            NSLocalizedString("position_lane_r3", comment: "Right 3")
        ]
        let rowIndex = (value - 1) / 7
        let colIndex = (value - 1) % 7
        return rows[rowIndex] + lanes[colIndex]
    }

    private func haptic(_ type: WKHapticType = .click) {
        WKInterfaceDevice.current().play(type)
    }
}

struct NumericAdjustView: View {
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

            Button(NSLocalizedString("action_save", comment: "Save")) {
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

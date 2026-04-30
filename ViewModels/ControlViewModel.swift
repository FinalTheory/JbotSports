import Foundation
import Combine

@MainActor
final class ControlViewModel: ObservableObject {
    @Published var isStarted: Bool = false

    @Published var topSpeed: Int = 60
    @Published var bottomSpeed: Int = 60
    @Published var frequency: Int = 5
    @Published var shortAngle: Int = 26

    @Published var presets: [Preset]
    @Published var activePresetID: UUID?

    private let ble: BLEManager
    private var spinAnchor: Int = 60

    private static let presetsStorageKey = "tennis_ctl.presets"

    init(ble: BLEManager) {
        self.ble = ble
        self.presets = Self.loadPresets()
    }

    var spinValue: Int {
        topSpeed - bottomSpeed
    }

    var allowedSpinValues: [Int] {
        stride(from: -50, through: 50, by: 5).filter { spin in
            let speeds = resolvedSpeeds(anchor: spinAnchor, spin: spin)
            return (0...100).contains(speeds.top) && (0...100).contains(speeds.bottom)
        }
    }

    func applySpin(diff: Int) {
        let clamped = nearestAllowedSpin(to: diff)
        let speeds = resolvedSpeeds(anchor: spinAnchor, spin: clamped)
        guard speeds.top != topSpeed || speeds.bottom != bottomSpeed else { return }
        topSpeed = speeds.top
        bottomSpeed = speeds.bottom
        sendStartPreview()
    }

    func incFrequency() {
        updateFrequency(by: 1)
    }

    func decFrequency() {
        updateFrequency(by: -1)
    }

    func incHeight() {
        updateShortAngle(by: 1)
    }

    func decHeight() {
        updateShortAngle(by: -1)
    }

    func incOverallSpeed() {
        adjustOverallSpeed(by: 5)
    }

    func decOverallSpeed() {
        adjustOverallSpeed(by: -5)
    }

    func selectPreset(_ preset: Preset) {
        activePresetID = preset.id
        applyPresetState(preset)
    }

    func updatePreset(_ updated: Preset) {
        guard let idx = presets.firstIndex(where: { $0.id == updated.id }) else { return }
        let normalized = normalizedPreset(updated)
        presets[idx] = normalized
        persistPresets()

        if activePresetID == normalized.id {
            applyPresetState(normalized)
        }
    }

    func start() {
        let preset = activePreset ?? presets.first
        sendStart(order: preset?.order ?? [], random: preset?.isRandom ?? false, startFlag: 1)
        isStarted = true
    }

    func stop() {
        ble.send(TennisCommand.stopV6())
        isStarted = false
    }

    func sendStartPreview() {
        let preset = activePreset ?? presets.first
        sendStart(order: preset?.order ?? [], random: preset?.isRandom ?? false, startFlag: 2)
    }

    private var activePreset: Preset? {
        guard let id = activePresetID else { return nil }
        return presets.first(where: { $0.id == id })
    }

    private func nearestAllowedSpin(to proposed: Int) -> Int {
        guard !allowedSpinValues.isEmpty else { return 0 }
        return allowedSpinValues.min(by: { abs($0 - proposed) < abs($1 - proposed) }) ?? 0
    }

    private func updateFrequency(by delta: Int) {
        let updated = min(max(frequency + delta, 1), 9)
        guard updated != frequency else { return }
        frequency = updated
        ble.send(TennisCommand.setFrequency(UInt8(frequency)))
    }

    private func updateShortAngle(by delta: Int) {
        let updated = min(max(shortAngle + delta, 6), 60)
        guard updated != shortAngle else { return }
        shortAngle = updated
        ble.send(TennisCommand.setShortAngle(UInt8(shortAngle)))
    }

    private func adjustOverallSpeed(by delta: Int) {
        let updatedTop = topSpeed + delta
        let updatedBottom = bottomSpeed + delta
        guard (0...100).contains(updatedTop), (0...100).contains(updatedBottom) else { return }

        topSpeed = updatedTop
        bottomSpeed = updatedBottom
        spinAnchor += delta
        sendStartPreview()
    }

    private func applyPresetState(_ preset: Preset) {
        let normalized = normalizedPreset(preset)
        topSpeed = normalized.topSpeed
        bottomSpeed = normalized.bottomSpeed
        frequency = normalized.frequency
        shortAngle = normalized.shortAngle
        spinAnchor = anchorFor(top: topSpeed, bottom: bottomSpeed)
    }

    private func normalizedPreset(_ preset: Preset) -> Preset {
        var normalized = preset
        normalized.topSpeed = snapped(preset.topSpeed, step: 5, range: 0...100)
        normalized.bottomSpeed = snapped(preset.bottomSpeed, step: 5, range: 0...100)
        normalized.frequency = snapped(preset.frequency, step: 1, range: 1...9)
        normalized.shortAngle = snapped(preset.shortAngle, step: 1, range: 6...60)

        let spin = min(max(normalized.topSpeed - normalized.bottomSpeed, -50), 50)
        let anchor = anchorFor(top: normalized.topSpeed, spin: spin)
        let speeds = resolvedSpeeds(anchor: anchor, spin: spin)
        normalized.topSpeed = speeds.top
        normalized.bottomSpeed = speeds.bottom
        return normalized
    }

    private func anchorFor(top: Int, bottom: Int) -> Int {
        let spin = min(max(top - bottom, -50), 50)
        return anchorFor(top: top, spin: spin)
    }

    private func anchorFor(top: Int, spin: Int) -> Int {
        let magnitudeSteps = abs(spin) / 5
        let primarySteps = (magnitudeSteps + 1) / 2

        if spin >= 0 {
            return top - primarySteps * 5
        } else {
            return top + primarySteps * 5
        }
    }

    private func resolvedSpeeds(anchor: Int, spin: Int) -> (top: Int, bottom: Int) {
        let magnitudeSteps = abs(spin) / 5
        let primarySteps = (magnitudeSteps + 1) / 2
        let secondarySteps = magnitudeSteps / 2

        if spin >= 0 {
            return (
                top: anchor + primarySteps * 5,
                bottom: anchor - secondarySteps * 5
            )
        } else {
            return (
                top: anchor - primarySteps * 5,
                bottom: anchor + secondarySteps * 5
            )
        }
    }

    private func snapped(_ value: Int, step: Int, range: ClosedRange<Int>) -> Int {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let offset = clamped - range.lowerBound
        let snappedOffset = Int((Double(offset) / Double(step)).rounded()) * step
        return min(max(range.lowerBound + snappedOffset, range.lowerBound), range.upperBound)
    }

    private func sendStart(order: [UInt8], random: Bool, startFlag: UInt8) {
        let data = TennisCommand.startV6(
            order: order,
            top: UInt8(topSpeed),
            bottom: UInt8(bottomSpeed),
            frequency: UInt8(frequency),
            shortAngle: UInt8(shortAngle),
            random: random,
            startFlag: startFlag
        )
        ble.send(data)
    }

    private func persistPresets() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: Self.presetsStorageKey)
    }

    private static func loadPresets() -> [Preset] {
        guard
            let data = UserDefaults.standard.data(forKey: presetsStorageKey),
            let decoded = try? JSONDecoder().decode([Preset].self, from: data),
            !decoded.isEmpty
        else {
            return defaultPresets
        }
        return decoded
    }

    private static var defaultPresets: [Preset] {
        [
            Preset(name: "后场定点", order: [25], isRandom: true, topSpeed: 65, bottomSpeed: 65, frequency: 7, shortAngle: 27),
            Preset(name: "后场水平", order: [24, 25, 26], isRandom: true, topSpeed: 75, bottomSpeed: 75, frequency: 7, shortAngle: 26),
            Preset(name: "后场上旋", order: [24, 25, 26], isRandom: true, topSpeed: 85, bottomSpeed: 70, frequency: 7, shortAngle: 28),
            Preset(name: "后场大范围", order: [23, 24, 25, 26, 27], isRandom: true, topSpeed: 75, bottomSpeed: 75, frequency: 7, shortAngle: 26),
        ]
    }
}

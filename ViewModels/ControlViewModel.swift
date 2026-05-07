import Foundation
import Combine

@MainActor
final class ControlViewModel: ObservableObject {
    enum AppLanguage: String, CaseIterable, Identifiable {
        case system
        case english = "en"
        case chineseSimplified = "zh-Hans"

        var id: String { rawValue }
    }

    @Published var randomRunInterval: Int = 20
    @Published var randomRunInitialIntervalSeconds: Int = 20
    @Published var randomRunStartDelaySeconds: Int = 8
    @Published var heartbeatIntervalSeconds: Int = 0
    @Published var debugEnabled: Bool = false
    @Published var diagnosticsLoggingEnabled: Bool = true
    @Published var appLanguage: AppLanguage = .system
    @Published var isRandomRunActive: Bool = false
    @Published var randomRunAlertMessage: String?
    @Published var flashHint: String = ""

    @Published var topSpeed: Int = 60
    @Published var bottomSpeed: Int = 60
    @Published var frequency: Int = 5
    @Published var shortAngle: Int = 26

    @Published var presets: [Preset]
    @Published var activePresetID: UUID?

    private let ble: BLEManager
    private var spinAnchor: Int = 60
    private var randomRunTimer: Timer?
    private var heartbeatTimer: Timer?
    private var randomCycleQueue: [UUID] = []
    private var randomCycleIndex: Int = 0
    private var randomRunNeedsInitialDelay: Bool = false

    private static let presetsStorageKey = "tennis_ctl.presets"
    private static let randomRunInitialIntervalStorageKey = "tennis_ctl.random_run_initial_interval"
    private static let randomRunStartDelayStorageKey = "tennis_ctl.random_run_start_delay"
    private static let heartbeatIntervalStorageKey = "tennis_ctl.heartbeat_interval"
    private static let legacyAngleHeartbeatIntervalStorageKey = "tennis_ctl.angle_heartbeat_interval"
    private static let debugEnabledStorageKey = "tennis_ctl.debug_enabled"
    private static let diagnosticsLoggingEnabledStorageKey = "tennis_ctl.diagnostics_logging_enabled"
    private static let appLanguageStorageKey = "tennis_ctl.app_language"

    init(ble: BLEManager) {
        self.ble = ble
        self.presets = Self.loadPresets()
        let storedInitialInterval = UserDefaults.standard.integer(forKey: Self.randomRunInitialIntervalStorageKey)
        let initialInterval = storedInitialInterval == 0 ? 20 : storedInitialInterval
        self.randomRunInitialIntervalSeconds = initialInterval
        self.randomRunInterval = initialInterval
        let storedDelay = UserDefaults.standard.integer(forKey: Self.randomRunStartDelayStorageKey)
        self.randomRunStartDelaySeconds = storedDelay == 0 ? 8 : storedDelay
        let storedHeartbeat = UserDefaults.standard.object(forKey: Self.heartbeatIntervalStorageKey) as? Int
        if let storedHeartbeat {
            self.heartbeatIntervalSeconds = storedHeartbeat
        } else {
            self.heartbeatIntervalSeconds = UserDefaults.standard.integer(forKey: Self.legacyAngleHeartbeatIntervalStorageKey)
        }
        self.debugEnabled = UserDefaults.standard.bool(forKey: Self.debugEnabledStorageKey)
        if UserDefaults.standard.object(forKey: Self.diagnosticsLoggingEnabledStorageKey) == nil {
            self.diagnosticsLoggingEnabled = true
        } else {
            self.diagnosticsLoggingEnabled = UserDefaults.standard.bool(forKey: Self.diagnosticsLoggingEnabledStorageKey)
        }
        if let raw = UserDefaults.standard.string(forKey: Self.appLanguageStorageKey),
           let language = AppLanguage(rawValue: raw) {
            self.appLanguage = language
        }
        applyLanguagePreference(self.appLanguage)
        ble.setDiagnosticsLoggingEnabled(self.diagnosticsLoggingEnabled)
        if let firstPreset = self.presets.first {
            self.activePresetID = firstPreset.id
            self.topSpeed = firstPreset.topSpeed
            self.bottomSpeed = firstPreset.bottomSpeed
            self.frequency = firstPreset.frequency
            self.shortAngle = firstPreset.shortAngle
            self.spinAnchor = anchorFor(top: firstPreset.topSpeed, bottom: firstPreset.bottomSpeed)
        }
    }

    var spinValue: Int {
        topSpeed - bottomSpeed
    }

    var allowedSpinValues: [Int] {
        stride(from: -50, through: 50, by: 5).filter { spin in
            let speeds = resolvedSpeeds(anchor: spinAnchor, spin: spin)
            return (30...100).contains(speeds.top) && (30...100).contains(speeds.bottom)
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

    func fineTuneLeft() {
        ble.send(TennisCommand.fineTune(2))
    }

    func fineTuneRight() {
        ble.send(TennisCommand.fineTune(1))
    }

    func selectPreset(_ preset: Preset) {
        activePresetID = preset.id
        applyPresetState(preset)
        flashHint = "PRESET \(preset.name)"
    }

    func updatePreset(_ updated: Preset) {
        guard let idx = presets.firstIndex(where: { $0.id == updated.id }) else { return }
        let normalized = normalizedPreset(updated)
        let changed = presets[idx] != normalized
        presets[idx] = normalized
        if changed {
            persistPresets(presets)
        }

        if activePresetID == normalized.id {
            applyPresetState(normalized)
        }
    }

    func addPreset(_ preset: Preset) {
        let normalized = normalizedPreset(preset)
        presets.append(normalized)
        persistPresets(presets)
    }

    @discardableResult
    func deletePreset(id: UUID) -> Bool {
        guard presets.count > 1 else { return false }
        guard let idx = presets.firstIndex(where: { $0.id == id }) else { return false }
        let deletingActive = (activePresetID == id)
        presets.remove(at: idx)
        persistPresets(presets)

        if deletingActive, let first = presets.first {
            activePresetID = first.id
            applyPresetState(first)
        }
        return true
    }

    func start() {
        stopRandomRunLoop()
        guard let preset = activePreset else { return }
        sendStart(order: preset.order, random: preset.isRandom, startFlag: 1)
        startHeartbeatIfNeeded()
    }

    func stop() {
        stopRandomRunLoop()
        stopHeartbeat()
        ble.send(TennisCommand.stopV6())
    }

    func incRandomRunInterval() {
        randomRunInterval = min(120, randomRunInterval + 5)
    }

    func decRandomRunInterval() {
        randomRunInterval = max(10, randomRunInterval - 5)
    }

    func startRandomRun() {
        stopRandomRunLoop()

        let candidates = presets.filter(\.shuffle)
        guard !candidates.isEmpty else {
            randomRunAlertMessage = "No shuffle preset"
            return
        }

        isRandomRunActive = true
        randomRunNeedsInitialDelay = true
        rebuildRandomCycleQueue(from: candidates)
        startHeartbeatIfNeeded()
        runCurrentRandomCyclePresetAndScheduleNext()
    }

    func setRandomRunStartDelay(seconds: Int) {
        guard seconds != randomRunStartDelaySeconds else { return }
        randomRunStartDelaySeconds = seconds
        UserDefaults.standard.set(seconds, forKey: Self.randomRunStartDelayStorageKey)
    }

    func setRandomRunInitialInterval(seconds: Int) {
        guard seconds != randomRunInitialIntervalSeconds else { return }
        randomRunInitialIntervalSeconds = seconds
        randomRunInterval = seconds
        UserDefaults.standard.set(seconds, forKey: Self.randomRunInitialIntervalStorageKey)
    }

    func setDebugEnabled(_ enabled: Bool) {
        guard enabled != debugEnabled else { return }
        debugEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.debugEnabledStorageKey)
    }

    func setDiagnosticsLoggingEnabled(_ enabled: Bool) {
        guard enabled != diagnosticsLoggingEnabled else { return }
        diagnosticsLoggingEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.diagnosticsLoggingEnabledStorageKey)
        ble.setDiagnosticsLoggingEnabled(enabled)
    }

    func setHeartbeatInterval(seconds: Int) {
        let normalized = max(0, min(30, seconds))
        guard normalized != heartbeatIntervalSeconds else { return }
        heartbeatIntervalSeconds = normalized
        UserDefaults.standard.set(normalized, forKey: Self.heartbeatIntervalStorageKey)

        // Reconfigure active heartbeat without creating duplicate timers.
        if heartbeatTimer != nil {
            startHeartbeatIfNeeded()
        }
    }

    func setAppLanguage(_ language: AppLanguage) {
        guard language != appLanguage else { return }
        appLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.appLanguageStorageKey)
        applyLanguagePreference(language)
    }

    func uploadBLELog() async throws -> URL {
        try await ble.uploadDiagnosticsLog()
    }

    func clearBLELog() throws {
        try ble.clearDiagnosticsLog()
    }

    private func applyLanguagePreference(_ language: AppLanguage) {
        switch language {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .english:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        case .chineseSimplified:
            UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        }
    }

    func sendStartPreview() {
        guard let preset = activePreset else { return }
        sendStart(order: preset.order, random: preset.isRandom, startFlag: 2)
    }

    private var activePreset: Preset? {
        guard let id = activePresetID else { return nil }
        return presets.first(where: { $0.id == id })
    }

    private func stopRandomRunLoop() {
        randomRunTimer?.invalidate()
        randomRunTimer = nil
        isRandomRunActive = false
        randomRunNeedsInitialDelay = false
    }

    private func startHeartbeatIfNeeded() {
        stopHeartbeat()
        guard heartbeatIntervalSeconds > 0 else { return }

        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(heartbeatIntervalSeconds),
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.ble.send(TennisCommand.setFrequency(UInt8(self.frequency)))
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func runCurrentRandomCyclePresetAndScheduleNext() {
        guard isRandomRunActive else { return }

        if randomCycleQueue.isEmpty {
            rebuildRandomCycleQueue(from: presets.filter(\.shuffle))
            guard !randomCycleQueue.isEmpty else {
                stopRandomRunLoop()
                randomRunAlertMessage = "No shuffle preset"
                return
            }
        }

        if randomCycleIndex >= randomCycleQueue.count {
            rebuildRandomCycleQueue(from: presets.filter(\.shuffle))
        }

        guard randomCycleIndex < randomCycleQueue.count else {
            stopRandomRunLoop()
            randomRunAlertMessage = "No shuffle preset"
            return
        }

        let presetID = randomCycleQueue[randomCycleIndex]
        randomCycleIndex += 1
        guard let preset = presets.first(where: { $0.id == presetID }) else {
            runCurrentRandomCyclePresetAndScheduleNext()
            return
        }

        activePresetID = preset.id
        applyPresetState(preset)
        flashHint = "PRESET \(preset.name)"
        sendPresetStart(preset)
        var nextSeconds = effectiveInterval(for: preset)
        if randomRunNeedsInitialDelay {
            nextSeconds += randomRunStartDelaySeconds
            randomRunNeedsInitialDelay = false
        }
        scheduleRandomRunTick(after: nextSeconds)
    }

    private func scheduleRandomRunTick(after seconds: Int) {
        randomRunTimer?.invalidate()
        randomRunTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.runCurrentRandomCyclePresetAndScheduleNext()
            }
        }
    }

    private func effectiveInterval(for preset: Preset) -> Int {
        if preset.interval > 0 {
            return preset.interval
        }
        return randomRunInterval
    }

    private func rebuildRandomCycleQueue(from candidates: [Preset]) {
        let ids = candidates.map(\.id)
        randomCycleQueue = ids.shuffled()
        randomCycleIndex = 0
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
        let updated = min(max(shortAngle + delta, 12), 60)
        guard updated != shortAngle else { return }
        shortAngle = updated
        ble.send(TennisCommand.setShortAngle(UInt8(shortAngle)))
    }

    private func adjustOverallSpeed(by delta: Int) {
        let updatedTop = topSpeed + delta
        let updatedBottom = bottomSpeed + delta
        guard (30...100).contains(updatedTop), (30...100).contains(updatedBottom) else { return }

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
        normalized.topSpeed = snapped(preset.topSpeed, step: 5, range: 30...100)
        normalized.bottomSpeed = snapped(preset.bottomSpeed, step: 5, range: 30...100)
        normalized.frequency = snapped(preset.frequency, step: 1, range: 1...9)
        normalized.shortAngle = snapped(preset.shortAngle, step: 1, range: 12...60)
        let snappedInterval = snapped(max(0, preset.interval), step: 5, range: 0...120)
        normalized.interval = (snappedInterval == 0 || snappedInterval >= 10) ? snappedInterval : 10

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

    private func sendPresetStart(_ preset: Preset) {
        sendStart(order: preset.order, random: preset.isRandom, startFlag: 1)
    }

    private func persistPresets(_ snapshots: [Preset]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
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
            Preset(name: "后场定点", order: [25], isRandom: true, shuffle: true, topSpeed: 65, bottomSpeed: 65, frequency: 7, shortAngle: 27),
            Preset(name: "后场水平", order: [24, 25, 26], isRandom: true, shuffle: true, topSpeed: 75, bottomSpeed: 75, frequency: 7, shortAngle: 26),
            Preset(name: "后场上旋", order: [24, 25, 26], isRandom: true, shuffle: true, topSpeed: 85, bottomSpeed: 70, frequency: 7, shortAngle: 28),
            Preset(name: "后场大范围", order: [23, 24, 25, 26, 27], isRandom: true, shuffle: true, topSpeed: 75, bottomSpeed: 75, frequency: 7, shortAngle: 26),
        ]
    }
}

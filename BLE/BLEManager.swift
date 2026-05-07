import Foundation
import CoreBluetooth
import Combine

final class BLEManager: NSObject, ObservableObject {
    @Published private(set) var discovered: [CBPeripheral] = []
    @Published private(set) var connected: CBPeripheral?
    @Published private(set) var connectingID: UUID?
    @Published private(set) var isScanning: Bool = false
    @Published var isReady: Bool = false
    @Published var lastTxHex: String = ""
    @Published var lastRxHex: String = ""

    private var central: CBCentralManager!
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var discoveredByID: [UUID: CBPeripheral] = [:]
    private var pendingConnection: CBPeripheral?
    private var pendingCharacteristicServices: Set<CBUUID> = []
    private var preSuspendPeripheralID: UUID?
    private var resumeTimeoutWorkItem: DispatchWorkItem?
    private var reconnectTargetID: UUID?
    private var reconnectWorkItem: DispatchWorkItem?
    private var rssiTimer: Timer?
    private var manualDisconnectRequested = false
    private let logger = BLEDiagnosticsLogger()

    private let serviceUUID = CBUUID(string: BLEConstants.UUIDs.service)
    private let writeUUID = CBUUID(string: BLEConstants.UUIDs.write)
    private let notifyUUID = CBUUID(string: BLEConstants.UUIDs.notify)
    private let reconnectInterval: TimeInterval = 2.0
    private let rssiPollInterval: TimeInterval = 5.0

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func setDiagnosticsLoggingEnabled(_ enabled: Bool) {
        logger.setEnabled(enabled)
    }

    func clearDiagnosticsLog() throws {
        try logger.clear()
    }

    func startScan() {
        guard central.state == .poweredOn else { return }

        central.stopScan()
        isScanning = true
        logger.log("scan_start", [
            "state": centralStateName(central.state),
            "filterService": serviceUUID.uuidString,
            "allowDuplicates": "true"
        ])

        discoveredByID.removeAll()
        if let current = connected {
            discoveredByID[current.identifier] = current
        }
        publishDiscovered()

        // Keep scanning aggressive for better reconnect behavior at weak signal edges.
        central.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
        logger.log("scan_stop")
    }

    func connect(_ peripheral: CBPeripheral) {
        cancelReconnectLoop()
        manualDisconnectRequested = false
        logger.log("connect_request", [
            "id": peripheral.identifier.uuidString,
            "name": peripheral.name ?? "",
            "isReady": "\(isReady)"
        ])

        if connected?.identifier == peripheral.identifier && isReady {
            discoveredByID[peripheral.identifier] = peripheral
            publishDiscovered()
            return
        }

        pendingConnection = peripheral
        stopScan()

        if let current = connected, current.identifier != peripheral.identifier {
            central.cancelPeripheralConnection(current)
            return
        }

        if let current = connected, current.identifier == peripheral.identifier {
            connectingID = peripheral.identifier
            isReady = false
            writeChar = nil
            notifyChar = nil
            pendingCharacteristicServices.removeAll()
            peripheral.delegate = self
            peripheral.discoverServices([serviceUUID])
            return
        }

        if let currentConnectingID = connectingID, currentConnectingID != peripheral.identifier {
            if let currentConnecting = discoveredByID[currentConnectingID] {
                central.cancelPeripheralConnection(currentConnecting)
                return
            }
            connectingID = nil
        }

        beginConnection(to: peripheral)
    }

    func send(_ data: Data) {
        lastTxHex = TennisCommand.hex(data)
        logger.log("tx", ["hex": lastTxHex])
        guard let peripheral = connected, let characteristic = writeChar else { return }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    func prepareForBackground() {
        preSuspendPeripheralID = connected?.identifier ?? preSuspendPeripheralID
        logger.log("app_background", ["rememberID": preSuspendPeripheralID?.uuidString ?? ""])
    }

    func uploadDiagnosticsLog() async throws -> URL {
        let payload = try diagnosticsLogPayload()
        var request = URLRequest(url: URL(string: "https://paste.rs/")!)
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.upload(for: request, from: payload)
        let body = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        logger.log("upload_log", [
            "status": "\(statusCode)",
            "response": body
        ])

        guard [200, 201, 206].contains(statusCode), let url = URL(string: body) else {
            throw BLEDiagnosticsUploadError.invalidResponse
        }
        return url
    }

    func resumeConnectionAfterForeground(timeout: TimeInterval = 3.0) {
        cancelResumeTimeout()
        logger.log("app_foreground", [
            "state": centralStateName(central.state),
            "targetID": preSuspendPeripheralID?.uuidString ?? "",
            "timeout": "\(timeout)"
        ])
        guard central.state == .poweredOn else {
            resetToInitialState()
            return
        }
        guard let targetID = preSuspendPeripheralID else {
            startScan()
            return
        }

        // Already recovered.
        if connected?.identifier == targetID && isReady {
            return
        }

        // Try connecting from known cache first; if missing, ask CoreBluetooth cache.
        let targetPeripheral: CBPeripheral?
        if let cached = discoveredByID[targetID] {
            targetPeripheral = cached
        } else {
            targetPeripheral = central.retrievePeripherals(withIdentifiers: [targetID]).first
        }

        if let peripheral = targetPeripheral {
            connect(peripheral)
        } else {
            startReconnectLoop(for: targetID)
        }

        let timeoutItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let recovered = (self.connected?.identifier == targetID && self.isReady)
            if !recovered {
                self.startReconnectLoop(for: targetID)
            }
        }
        resumeTimeoutWorkItem = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
    }

    private func beginConnection(to peripheral: CBPeripheral) {
        clearProtocolState()
        connectingID = peripheral.identifier
        discoveredByID[peripheral.identifier] = peripheral
        publishDiscovered()
        logger.log("connect_begin", [
            "id": peripheral.identifier.uuidString,
            "name": peripheral.name ?? ""
        ])

        peripheral.delegate = self
        central.connect(
            peripheral,
            options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true]
        )
    }

    private func clearProtocolState() {
        stopRSSIMonitoring()
        writeChar = nil
        notifyChar = nil
        pendingCharacteristicServices.removeAll()
        isReady = false
        connected = nil
    }

    private func clearAttemptState() {
        connectingID = nil
        pendingConnection = nil
    }

    private func cancelReconnectLoop() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        if reconnectTargetID != nil {
            logger.log("reconnect_stop", ["targetID": reconnectTargetID?.uuidString ?? ""])
        }
        reconnectTargetID = nil
    }

    private func startReconnectLoop(for peripheralID: UUID) {
        reconnectTargetID = peripheralID
        logger.log("reconnect_start", [
            "targetID": peripheralID.uuidString,
            "intervalSec": "\(reconnectInterval)"
        ])
        startScan()
        scheduleReconnectTick()
    }

    private func scheduleReconnectTick() {
        reconnectWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let targetID = self.reconnectTargetID else { return }
            guard self.central.state == .poweredOn else { return }
            guard !(self.connected?.identifier == targetID && self.isReady) else {
                self.cancelReconnectLoop()
                return
            }
            guard self.connectingID == nil else {
                self.scheduleReconnectTick()
                return
            }

            // 1) Try already-connected peripherals from system cache.
            let connectedPeripherals = self.central.retrieveConnectedPeripherals(withServices: [self.serviceUUID])
            if let existing = connectedPeripherals.first(where: { $0.identifier == targetID }) {
                self.logger.log("reconnect_hit_connected_cache", ["targetID": targetID.uuidString])
                self.beginConnection(to: existing)
                self.scheduleReconnectTick()
                return
            }

            // 2) Try known identifier cache.
            if let known = self.central.retrievePeripherals(withIdentifiers: [targetID]).first {
                self.logger.log("reconnect_hit_identifier_cache", ["targetID": targetID.uuidString])
                self.beginConnection(to: known)
                self.scheduleReconnectTick()
                return
            }

            // 3) Keep scanning; didDiscover may pick it up later.
            if !self.isScanning {
                self.startScan()
            }
            self.logger.log("reconnect_wait_discover", ["targetID": targetID.uuidString])
            self.scheduleReconnectTick()
        }
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectInterval, execute: item)
    }

    private func cancelResumeTimeout() {
        resumeTimeoutWorkItem?.cancel()
        resumeTimeoutWorkItem = nil
    }

    private func resetToInitialState() {
        cancelResumeTimeout()
        manualDisconnectRequested = true
        logger.log("reset_initial_state")
        if let current = connected {
            central.cancelPeripheralConnection(current)
        }
        cancelReconnectLoop()
        clearProtocolState()
        clearAttemptState()
        discoveredByID.removeAll()
        publishDiscovered()
        startScan()
    }

    private func finishConnectionAttempt(resumeScan: Bool) {
        clearAttemptState()
        if resumeScan {
            startScan()
        }
    }

    private func failCurrentAttempt(resumeScan: Bool = true) {
        clearProtocolState()
        logger.log("connect_attempt_fail", ["resumeScan": "\(resumeScan)"])
        finishConnectionAttempt(resumeScan: resumeScan)
    }

    private func publishDiscovered() {
        discovered = discoveredByID.values.sorted { lhs, rhs in
            let lhsConnected = lhs.identifier == connected?.identifier
            let rhsConnected = rhs.identifier == connected?.identifier

            if lhsConnected != rhsConnected {
                return lhsConnected
            }

            let lhsName = lhs.name ?? ""
            let rhsName = rhs.name ?? ""
            if lhsName != rhsName {
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }

            return lhs.identifier.uuidString < rhs.identifier.uuidString
        }
    }

    private func startRSSIMonitoring(for peripheral: CBPeripheral) {
        stopRSSIMonitoring()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: rssiPollInterval, repeats: true) { [weak self, weak peripheral] _ in
            guard let self, let peripheral else { return }
            guard self.connected?.identifier == peripheral.identifier, self.isReady else { return }
            peripheral.readRSSI()
        }
    }

    private func stopRSSIMonitoring() {
        rssiTimer?.invalidate()
        rssiTimer = nil
    }

    private func diagnosticsLogPayload() throws -> Data {
        let fileManager = FileManager.default
        if let currentURL = BLEDiagnosticsLogger.logFileURL(),
           fileManager.fileExists(atPath: currentURL.path),
           let currentText = try? String(contentsOf: currentURL, encoding: .utf8),
           !currentText.isEmpty {
            guard let data = currentText.data(using: .utf8) else {
                throw BLEDiagnosticsUploadError.encodingFailed
            }
            return data
        }

        throw BLEDiagnosticsUploadError.emptyLog
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.log("central_state_change", ["state": centralStateName(central.state)])
        if central.state == .poweredOn {
            startScan()
        } else {
            cancelResumeTimeout()
            cancelReconnectLoop()
            stopScan()
            clearProtocolState()
            clearAttemptState()
            manualDisconnectRequested = false
            discoveredByID.removeAll()
            publishDiscovered()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, !name.isEmpty else { return }
        discoveredByID[peripheral.identifier] = peripheral
        publishDiscovered()
        if reconnectTargetID == peripheral.identifier {
            logger.log("discover_target", [
                "id": peripheral.identifier.uuidString,
                "name": name,
                "rssi": "\(RSSI.intValue)"
            ])
        }

        if reconnectTargetID == peripheral.identifier, connectingID == nil, connected?.identifier != peripheral.identifier {
            beginConnection(to: peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        manualDisconnectRequested = false
        cancelReconnectLoop()
        cancelResumeTimeout()
        connectingID = nil
        connected = peripheral
        preSuspendPeripheralID = peripheral.identifier
        discoveredByID[peripheral.identifier] = peripheral
        publishDiscovered()
        logger.log("connect_ok", [
            "id": peripheral.identifier.uuidString,
            "name": peripheral.name ?? ""
        ])

        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let next = pendingConnection
        let shouldRetryNext = next != nil && next?.identifier != peripheral.identifier
        let shouldResumeScan = !shouldRetryNext
        let shouldAutoReconnect = !manualDisconnectRequested && preSuspendPeripheralID == peripheral.identifier
        logger.log("disconnect", [
            "id": peripheral.identifier.uuidString,
            "name": peripheral.name ?? "",
            "autoReconnect": "\(shouldAutoReconnect)",
            "error": cbErrorString(error)
        ])

        clearProtocolState()
        connectingID = nil

        if let next, next.identifier != peripheral.identifier {
            pendingConnection = nil
            beginConnection(to: next)
            return
        }

        finishConnectionAttempt(resumeScan: shouldResumeScan)
        if shouldAutoReconnect {
            startReconnectLoop(for: peripheral.identifier)
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.log("connect_fail", [
            "id": peripheral.identifier.uuidString,
            "name": peripheral.name ?? "",
            "error": cbErrorString(error)
        ])
        failCurrentAttempt()
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        logger.log("discover_services", [
            "id": peripheral.identifier.uuidString,
            "error": cbErrorString(error)
        ])
        guard error == nil, let services = peripheral.services else {
            central.cancelPeripheralConnection(peripheral)
            return
        }

        if let targetService = services.first(where: { $0.uuid == serviceUUID }) {
            pendingCharacteristicServices = [targetService.uuid]
            peripheral.discoverCharacteristics([writeUUID, notifyUUID], for: targetService)
            return
        }

        pendingCharacteristicServices = Set(services.map(\.uuid))
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        logger.log("discover_chars", [
            "id": peripheral.identifier.uuidString,
            "service": service.uuid.uuidString,
            "error": cbErrorString(error)
        ])
        guard error == nil, let chars = service.characteristics else {
            pendingCharacteristicServices.remove(service.uuid)
            if pendingCharacteristicServices.isEmpty && !isReady {
                central.cancelPeripheralConnection(peripheral)
            }
            return
        }

        for characteristic in chars {
            if characteristic.uuid == writeUUID {
                writeChar = characteristic
            }
            if characteristic.uuid == notifyUUID {
                notifyChar = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }

        pendingCharacteristicServices.remove(service.uuid)
        isReady = (writeChar != nil && notifyChar != nil)
        if isReady {
            cancelResumeTimeout()
            pendingConnection = nil
            stopScan()
            startRSSIMonitoring(for: peripheral)
            connected = peripheral
            discoveredByID[peripheral.identifier] = peripheral
            publishDiscovered()
            logger.log("ready", ["id": peripheral.identifier.uuidString])
        } else if pendingCharacteristicServices.isEmpty {
            central.cancelPeripheralConnection(peripheral)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        lastRxHex = TennisCommand.hex(data)
        logger.log("rx", ["hex": lastRxHex, "error": cbErrorString(error)])
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        logger.log("write_ack", [
            "id": peripheral.identifier.uuidString,
            "char": characteristic.uuid.uuidString,
            "hex": lastTxHex,
            "error": cbErrorString(error)
        ])
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        logger.log("rssi", [
            "id": peripheral.identifier.uuidString,
            "value": "\(RSSI.intValue)",
            "error": cbErrorString(error)
        ])
    }
}

private extension BLEManager {
    enum BLEDiagnosticsUploadError: LocalizedError {
        case emptyLog
        case encodingFailed
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .emptyLog:
                return "BLE log is empty."
            case .encodingFailed:
                return "BLE log encoding failed."
            case .invalidResponse:
                return "BLE log upload failed."
            }
        }
    }

    func centralStateName(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "unknownFuture"
        }
    }

    func cbErrorString(_ error: Error?) -> String {
        guard let error else { return "" }
        let ns = error as NSError
        return "\(ns.domain)#\(ns.code):\(ns.localizedDescription)"
    }
}

private final class BLEDiagnosticsLogger {
    private static let fileName = "ble_diagnostics.log"

    private let queue = DispatchQueue(label: "ble.logger.queue")
    private var enabled = true

    func log(_ event: String, _ fields: [String: String] = [:]) {
        guard enabled else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        var line = "\(timestamp) event=\(event)"
        if !fields.isEmpty {
            let payload = fields
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value.replacingOccurrences(of: " ", with: "_"))" }
                .joined(separator: " ")
            line += " \(payload)"
        }
        line += "\n"

        queue.async {
            self.write(line)
        }
    }

    func setEnabled(_ enabled: Bool) {
        queue.sync {
            self.enabled = enabled
        }
    }

    func clear() throws {
        try queue.sync {
            if let currentURL = Self.logFileURL(), FileManager.default.fileExists(atPath: currentURL.path) {
                try FileManager.default.removeItem(at: currentURL)
            }
        }
    }

    private func write(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        guard let url = Self.logFileURL() else { return }

        do {
            try ensureFileExists(at: url)
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            // Intentionally swallow logger errors to avoid affecting BLE control path.
        }
    }

    static func logFileURL() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = support.appendingPathComponent("tennis_ctl", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent(Self.fileName)
        } catch {
            return nil
        }
    }

    private func ensureFileExists(at url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }
}

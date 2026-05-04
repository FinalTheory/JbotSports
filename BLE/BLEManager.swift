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
    private var manualDisconnectRequested = false

    private let serviceUUID = CBUUID(string: BLEConstants.UUIDs.service)
    private let writeUUID = CBUUID(string: BLEConstants.UUIDs.write)
    private let notifyUUID = CBUUID(string: BLEConstants.UUIDs.notify)
    private let reconnectInterval: TimeInterval = 2.0

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        guard central.state == .poweredOn else { return }

        central.stopScan()
        isScanning = true

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
    }

    func connect(_ peripheral: CBPeripheral) {
        cancelReconnectLoop()
        manualDisconnectRequested = false

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
        guard let peripheral = connected, let characteristic = writeChar else { return }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    func prepareForBackground() {
        preSuspendPeripheralID = connected?.identifier ?? preSuspendPeripheralID
    }

    func resumeConnectionAfterForeground(timeout: TimeInterval = 3.0) {
        cancelResumeTimeout()
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

        peripheral.delegate = self
        central.connect(
            peripheral,
            options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true]
        )
    }

    private func clearProtocolState() {
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
        reconnectTargetID = nil
    }

    private func startReconnectLoop(for peripheralID: UUID) {
        reconnectTargetID = peripheralID
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
                self.beginConnection(to: existing)
                self.scheduleReconnectTick()
                return
            }

            // 2) Try known identifier cache.
            if let known = self.central.retrievePeripherals(withIdentifiers: [targetID]).first {
                self.beginConnection(to: known)
                self.scheduleReconnectTick()
                return
            }

            // 3) Keep scanning; didDiscover may pick it up later.
            if !self.isScanning {
                self.startScan()
            }
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
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
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

        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let next = pendingConnection
        let shouldRetryNext = next != nil && next?.identifier != peripheral.identifier
        let shouldResumeScan = !shouldRetryNext
        let shouldAutoReconnect = !manualDisconnectRequested && preSuspendPeripheralID == peripheral.identifier

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
        failCurrentAttempt()
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
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
            connected = peripheral
            discoveredByID[peripheral.identifier] = peripheral
            publishDiscovered()
        } else if pendingCharacteristicServices.isEmpty {
            central.cancelPeripheralConnection(peripheral)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        lastRxHex = TennisCommand.hex(data)
    }
}

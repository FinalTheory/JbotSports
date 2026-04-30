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

    private let serviceUUID = CBUUID(string: BLEConstants.UUIDs.service)
    private let writeUUID = CBUUID(string: BLEConstants.UUIDs.write)
    private let notifyUUID = CBUUID(string: BLEConstants.UUIDs.notify)

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

        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    func connect(_ peripheral: CBPeripheral) {
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
        guard let peripheral = connected, let characteristic = writeChar else { return }
        lastTxHex = TennisCommand.hex(data)
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    private func beginConnection(to peripheral: CBPeripheral) {
        clearProtocolState()
        connectingID = peripheral.identifier
        discoveredByID[peripheral.identifier] = peripheral
        publishDiscovered()

        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    private func clearProtocolState() {
        writeChar = nil
        notifyChar = nil
        pendingCharacteristicServices.removeAll()
        isReady = false
        connected = nil
    }

    private func finishConnectionAttempt(resumeScan: Bool) {
        connectingID = nil
        pendingConnection = nil
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
            stopScan()
            clearProtocolState()
            discoveredByID.removeAll()
            publishDiscovered()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, !name.isEmpty else { return }
        discoveredByID[peripheral.identifier] = peripheral
        publishDiscovered()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectingID = nil
        connected = peripheral
        discoveredByID[peripheral.identifier] = peripheral
        publishDiscovered()

        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let next = pendingConnection
        let shouldRetryNext = next != nil && next?.identifier != peripheral.identifier
        let shouldResumeScan = !shouldRetryNext

        clearProtocolState()
        connectingID = nil

        if let next, next.identifier != peripheral.identifier {
            pendingConnection = nil
            beginConnection(to: next)
            return
        }

        finishConnectionAttempt(resumeScan: shouldResumeScan)
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

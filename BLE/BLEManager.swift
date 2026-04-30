import Foundation
import CoreBluetooth
import Combine

final class BLEManager: NSObject, ObservableObject {
    @Published var discovered: [CBPeripheral] = []
    @Published var connected: CBPeripheral?
    @Published var isReady: Bool = false
    @Published var lastTxHex: String = ""
    @Published var lastRxHex: String = ""

    private var central: CBCentralManager!
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?

    private let serviceUUID = CBUUID(string: "0000FF10-0000-1000-8000-00805F9B34FB")
    private let writeUUID = CBUUID(string: "0000FF11-0000-1000-8000-00805F9B34FB")
    private let notifyUUID = CBUUID(string: "0000FF12-0000-1000-8000-00805F9B34FB")

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        guard central.state == .poweredOn else { return }
        discovered.removeAll()
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        central.stopScan()
    }

    func connect(_ p: CBPeripheral) {
        p.delegate = self
        central.connect(p, options: nil)
    }

    func send(_ data: Data) {
        guard let p = connected, let c = writeChar else { return }
        lastTxHex = TennisCommand.hex(data)
        p.writeValue(data, for: c, type: .withResponse)
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScan()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, !name.isEmpty else { return }
        if !discovered.contains(where: { $0.identifier == peripheral.identifier }) {
            discovered.append(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connected = peripheral
        isReady = false
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connected = nil
        writeChar = nil
        notifyChar = nil
        isReady = false
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for s in services where s.uuid == serviceUUID {
            peripheral.discoverCharacteristics([writeUUID, notifyUUID], for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for c in chars {
            if c.uuid == writeUUID { writeChar = c }
            if c.uuid == notifyUUID {
                notifyChar = c
                peripheral.setNotifyValue(true, for: c)
            }
        }
        isReady = (writeChar != nil && notifyChar != nil)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let d = characteristic.value else { return }
        lastRxHex = TennisCommand.hex(d)
    }
}
